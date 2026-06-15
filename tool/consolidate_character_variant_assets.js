#!/usr/bin/env node

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const assetRoot = path.join(projectRoot, 'assets', 'file');
const manifestPath = path.join(assetRoot, 'character_assets_manifest.json');
const pubspecPath = path.join(projectRoot, 'pubspec.yaml');

const childVariantPattern = /^(\d{8}_\d+)_\d+$/;
const textureOnlyExtensionPattern = /^(\d{8})_0\d+$/;
const generatedPubspecMarker =
  '    # Character gallery assets generated from assets/file/11100001..11301006.';

function sha1(file) {
  const hash = crypto.createHash('sha1');
  hash.update(fs.readFileSync(file));
  return hash.digest('hex');
}

function compareFolderKeys(a, b) {
  const aParts = a.split('_').map(Number);
  const bParts = b.split('_').map(Number);
  const length = Math.max(aParts.length, bParts.length);
  for (let i = 0; i < length; i += 1) {
    const diff = (aParts[i] || 0) - (bParts[i] || 0);
    if (diff !== 0) {
      return diff;
    }
  }
  return a.localeCompare(b);
}

function parentFolderForConsolidatedFolder(folder) {
  const splitVariantMatch = folder.match(childVariantPattern);
  if (splitVariantMatch) {
    return splitVariantMatch[1];
  }

  const textureOnlyMatch = folder.match(textureOnlyExtensionPattern);
  if (textureOnlyMatch && isTextureOnlyExtensionFolder(folder, textureOnlyMatch[1])) {
    return textureOnlyMatch[1];
  }

  return null;
}

function isConsolidatedChildVariantFolder(folder) {
  return parentFolderForConsolidatedFolder(folder) !== null;
}

function isTextureOnlyExtensionFolder(folder, parentFolder) {
  const childDir = path.join(assetRoot, folder);
  const parentDir = path.join(assetRoot, parentFolder);
  if (!fs.existsSync(childDir) || !fs.existsSync(parentDir)) {
    return false;
  }

  const childEntries = fs
    .readdirSync(childDir, {withFileTypes: true})
    .filter((entry) => entry.name !== '.DS_Store' && entry.name !== 'character_info.json');
  if (childEntries.length === 0) {
    return false;
  }

  const childHasOnlyTextureDir = childEntries.every(
    (entry) => entry.isDirectory() && entry.name === 'texture',
  );
  const parentHasSpine = fs.existsSync(path.join(parentDir, 'spine'));
  return childHasOnlyTextureDir && parentHasSpine;
}

function findExistingFileByHash(dir, sourceHash) {
  for (const existingFile of walkFiles(dir)) {
    if (sha1(existingFile) === sourceHash) {
      return existingFile;
    }
  }
  return null;
}

function walkFiles(dir) {
  const files = [];
  if (!fs.existsSync(dir)) {
    return files;
  }

  for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
    if (entry.name === '.DS_Store' || entry.name === 'character_info.json') {
      continue;
    }

    const current = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...walkFiles(current));
    } else if (entry.isFile()) {
      files.push(current);
    }
  }
  return files;
}

function ensureUniqueDestination(targetFile, sourceHash) {
  if (!fs.existsSync(targetFile)) {
    return {
      file: targetFile,
      duplicate: false,
    };
  }

  if (sha1(targetFile) === sourceHash) {
    return {
      file: targetFile,
      duplicate: true,
    };
  }

  const parsed = path.parse(targetFile);
  let counter = 1;
  let candidate = path.join(
    parsed.dir,
    `${parsed.name}__merged${parsed.ext}`,
  );
  while (fs.existsSync(candidate) && sha1(candidate) !== sourceHash) {
    counter += 1;
    candidate = path.join(
      parsed.dir,
      `${parsed.name}__merged_${counter}${parsed.ext}`,
    );
  }

  return {
    file: candidate,
    duplicate: fs.existsSync(candidate),
  };
}

function assetTypeFromRelativePath(relativePath) {
  const parts = relativePath.split(path.sep);
  return parts.length > 1 ? parts[0] : 'misc';
}

function getManifestFileByRelativePath(manifest, relativeFile) {
  const normalized = relativeFile.split(path.sep).join('/');
  for (const folder of Object.values(manifest.folders || {})) {
    for (const file of folder.files || []) {
      if (file.file === normalized) {
        return file;
      }
    }
  }
  return null;
}

function ensureManifestFolder(manifest, folder) {
  if (!manifest.folders[folder]) {
    manifest.folders[folder] = {
      counts: {},
      files: [],
    };
  }
  return manifest.folders[folder];
}

function addManifestEntry({
  manifest,
  parentFolder,
  childFolder,
  sourceFile,
  destinationFile,
}) {
  const relativeDestination = path
    .relative(assetRoot, destinationFile)
    .split(path.sep)
    .join('/');
  const parentManifest = ensureManifestFolder(manifest, parentFolder);

  if (
    parentManifest.files.some((file) => file.file === relativeDestination)
  ) {
    return false;
  }

  const relativeSource = path
    .relative(assetRoot, sourceFile)
    .split(path.sep)
    .join('/');
  const sourceEntry = getManifestFileByRelativePath(manifest, relativeSource);
  const relativeToChild = path.relative(
    path.join(assetRoot, childFolder),
    sourceFile,
  );
  const type =
    sourceEntry?.type || assetTypeFromRelativePath(relativeToChild) || 'misc';
  const stat = fs.statSync(sourceFile);
  const hash = sha1(sourceFile);

  parentManifest.counts[type] = (parentManifest.counts[type] || 0) + 1;
  parentManifest.files.push({
    type,
    file: relativeDestination,
    source: sourceEntry?.source || sourceFile,
    bytes: sourceEntry?.bytes || stat.size,
    sha1: sourceEntry?.sha1 || hash,
    consolidatedFrom: childFolder,
  });
  return true;
}

function consolidateFolders(manifest) {
  const folders = fs
    .readdirSync(assetRoot, {withFileTypes: true})
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .filter(isConsolidatedChildVariantFolder)
    .sort(compareFolderKeys);

  let copiedFiles = 0;
  let duplicateFilesSkipped = 0;
  let manifestEntriesAdded = 0;
  let manifestChildFoldersRemoved = 0;
  const parents = new Set();

  for (const childFolder of folders) {
    const parentFolder = parentFolderForConsolidatedFolder(childFolder);
    if (!parentFolder) {
      continue;
    }
    const childDir = path.join(assetRoot, childFolder);
    const parentDir = path.join(assetRoot, parentFolder);
    fs.mkdirSync(parentDir, {recursive: true});
    parents.add(parentFolder);

    for (const sourceFile of walkFiles(childDir)) {
      const relative = path.relative(childDir, sourceFile);
      const targetFile = path.join(parentDir, relative);
      const sourceHash = sha1(sourceFile);
      const duplicateByHash = findExistingFileByHash(parentDir, sourceHash);
      const destination = duplicateByHash
        ? {file: duplicateByHash, duplicate: true}
        : ensureUniqueDestination(targetFile, sourceHash);

      if (destination.duplicate) {
        duplicateFilesSkipped += 1;
      } else {
        fs.mkdirSync(path.dirname(destination.file), {recursive: true});
        fs.copyFileSync(sourceFile, destination.file);
        copiedFiles += 1;
      }

      if (
        addManifestEntry({
          manifest,
          parentFolder,
          childFolder,
          sourceFile,
          destinationFile: destination.file,
        })
      ) {
        manifestEntriesAdded += 1;
      }
    }
  }

  for (const childFolder of folders) {
    if (manifest.folders && manifest.folders[childFolder]) {
      delete manifest.folders[childFolder];
      manifestChildFoldersRemoved += 1;
    }
  }

  return {
    childFolders: folders.length,
    parentFolders: parents.size,
    copiedFiles,
    duplicateFilesSkipped,
    manifestEntriesAdded,
    manifestChildFoldersRemoved,
  };
}

function dirsWithFiles(dir) {
  const dirs = [];

  function walk(current) {
    const relativeToAssetRoot = path.relative(assetRoot, current);
    const topFolder = relativeToAssetRoot.split(path.sep)[0];
    if (
      relativeToAssetRoot &&
      isConsolidatedChildVariantFolder(topFolder)
    ) {
      return;
    }

    let hasFile = false;
    for (const entry of fs.readdirSync(current, {withFileTypes: true})) {
      if (entry.name === '.DS_Store') {
        continue;
      }
      const next = path.join(current, entry.name);
      if (entry.isDirectory()) {
        walk(next);
      } else if (entry.isFile()) {
        hasFile = true;
      }
    }

    if (hasFile && current !== assetRoot) {
      dirs.push(path.relative(projectRoot, current).split(path.sep).join('/'));
    }
  }

  walk(dir);
  return dirs.sort((a, b) => compareFolderKeys(a.replace('assets/file/', ''), b.replace('assets/file/', '')));
}

function updatePubspecAssets() {
  const pubspec = fs.readFileSync(pubspecPath, 'utf8');
  const lines = pubspec.split('\n');
  const markerIndex = lines.indexOf(generatedPubspecMarker);
  if (markerIndex === -1) {
    throw new Error('Could not find generated asset marker in pubspec.yaml');
  }

  const endIndex = lines.findIndex(
    (line, index) => index > markerIndex && line.startsWith('  # To add assets'),
  );
  if (endIndex === -1) {
    throw new Error('Could not find generated asset section end in pubspec.yaml');
  }

  const generatedLines = dirsWithFiles(assetRoot).map((dir) => `    - ${dir}/`);
  const nextLines = [
    ...lines.slice(0, markerIndex + 1),
    ...generatedLines,
    '',
    ...lines.slice(endIndex),
  ];
  fs.writeFileSync(pubspecPath, nextLines.join('\n'));
  return generatedLines.length;
}

function main() {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const result = consolidateFolders(manifest);

  manifest.generatedAt = new Date().toISOString();
  manifest.notes = Array.from(
    new Set([
      ...(manifest.notes || []),
      'Folders like 11101003_3_1, 11101003_3_2, or 11202009_1_3 are consolidated into the first variant folder so one character variant folder contains all related layers.',
      'Texture-only folders like 11101002_01 and 11101002_02 are consolidated into the base character folder and are not treated as separate character variants.',
    ]),
  );
  manifest.totals.folders = Object.keys(manifest.folders || {}).length;

  for (const folder of Object.values(manifest.folders || {})) {
    folder.files = (folder.files || []).sort((a, b) => {
      const typeCompare = String(a.type).localeCompare(String(b.type));
      if (typeCompare !== 0) {
        return typeCompare;
      }
      return String(a.file).localeCompare(String(b.file));
    });
  }

  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  const pubspecAssetDirs = updatePubspecAssets();

  console.log(`consolidatedChildFolders=${result.childFolders}`);
  console.log(`parentFolders=${result.parentFolders}`);
  console.log(`copiedFiles=${result.copiedFiles}`);
  console.log(`duplicateFilesSkipped=${result.duplicateFilesSkipped}`);
  console.log(`manifestEntriesAdded=${result.manifestEntriesAdded}`);
  console.log(`manifestChildFoldersRemoved=${result.manifestChildFoldersRemoved}`);
  console.log(`pubspecAssetDirs=${pubspecAssetDirs}`);
}

main();
