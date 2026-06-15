#!/usr/bin/env node

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const sourceRoot = '/Users/zhuhaiming/Desktop/edenAssets';
const destinationRoot = path.join(projectRoot, 'assets', 'file');
const outputPath = path.join(destinationRoot, 'character_assets_manifest.json');

const sourceDirectories = Array.from(
  new Set(
    [
      path.join(sourceRoot, 'edenAssets', 'edenAssets'),
      path.join(sourceRoot, 'edenAssets', 'edenAssets2'),
      path.join(sourceRoot, 'edenAssets2'),
    ].filter((dir) => fs.existsSync(dir)),
  ),
);

const matchedFiles = [];
const childVariantPattern = /^(\d{8}_\d+)_\d+$/;
const textureOnlyExtensionPattern = /^(\d{8})_0\d+$/;

function createAsset({file, relativeSource, folder, type}) {
  return {
    source: file,
    relativeSource,
    folder: normalizeVariantFolder(folder, type),
    type,
  };
}

function normalizeVariantFolder(folder, type) {
  const match = folder.match(childVariantPattern);
  if (match) {
    return match[1];
  }

  const textureOnlyMatch = folder.match(textureOnlyExtensionPattern);
  if (type === 'texture' && textureOnlyMatch) {
    return textureOnlyMatch[1];
  }

  return folder;
}

function walk(dir) {
  for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
    if (entry.name === '.DS_Store') {
      continue;
    }
    const current = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(current);
    } else if (entry.isFile()) {
      const asset = classifyAsset(current);
      if (asset) {
        matchedFiles.push(asset);
      }
    }
  }
}

function classifyAsset(file) {
  const baseName = path.basename(file);
  const lowerBaseName = baseName.toLowerCase();
  const parent = path.basename(path.dirname(file));
  const relativeSource = path.relative(sourceRoot, file);
  const stem = stripKnownExtensions(baseName);

  let match = stem.match(/^CardShowSpin(?:e|g)_(\d{8}(?:_\d+)*)/i);
  if (match) {
    return createAsset({
      file,
      relativeSource,
      folder: match[1],
      type: getCardShowType(baseName, lowerBaseName, parent),
    });
  }

  match = stem.match(/^CardSpine_(\d{8}(?:_\d+)*)/i);
  if (match) {
    return createAsset({
      file,
      relativeSource,
      folder: match[1],
      type: getCardSpineType(baseName, lowerBaseName, parent),
    });
  }

  match = stem.match(/^img_(\d{8})(?:_\d+)*/i);
  if (match && lowerBaseName.endsWith('.png')) {
    return createAsset({
      file,
      relativeSource,
      folder: match[1],
      type: 'portrait',
    });
  }

  match = stem.match(/^(?:FX|Fx)_timeline_(\d{8})/);
  if (match) {
    return createAsset({
      file,
      relativeSource,
      folder: match[1],
      type: lowerBaseName.endsWith('.m4v')
        ? 'video'
        : lowerBaseName.endsWith('.fbx')
          ? 'animation'
          : 'metadata',
    });
  }

  match = stem.match(/^(?:FX|Fx)_uniqueskill_(\d{8})/);
  if (match) {
    return createAsset({
      file,
      relativeSource,
      folder: match[1],
      type: lowerBaseName.endsWith('.fbx') ? 'animation' : getGenericType(lowerBaseName),
    });
  }

  match = stem.match(/^av_(\d{8})/i);
  if (match && lowerBaseName.endsWith('.m4v')) {
    return createAsset({
      file,
      relativeSource,
      folder: match[1],
      type: 'video',
    });
  }

  match = stem.match(/^skillscript(\d{8})/i);
  if (match) {
    return createAsset({
      file,
      relativeSource,
      folder: match[1],
      type: 'script',
    });
  }

  return null;
}

function stripKnownExtensions(baseName) {
  return baseName
    .replace(/\.(atlas|skel)\.prefab$/i, '')
    .replace(/\.(png|json|bytes|m4v|fbx)$/i, '');
}

function getCardShowType(baseName, lowerBaseName, parent) {
  if (parent === 'TextAsset' && /\.(atlas|skel)\.prefab$/i.test(baseName)) {
    return 'spine';
  }
  if (parent === 'MonoBehaviour' && /\.json$/i.test(baseName)) {
    return 'metadata';
  }
  if (parent === 'Texture2D' && /\.png$/i.test(baseName)) {
    if (/(?:_bg\b|_bg_|_background\b|dimian)/i.test(baseName)) {
      return 'background';
    }
    return 'texture';
  }
  return getGenericType(lowerBaseName);
}

function getCardSpineType(baseName, lowerBaseName, parent) {
  if (parent === 'TextAsset' && /\.(atlas|skel)\.prefab$/i.test(baseName)) {
    return 'battle_spine';
  }
  if (parent === 'MonoBehaviour' && /\.json$/i.test(baseName)) {
    return 'battle_metadata';
  }
  if (parent === 'Texture2D' && /\.png$/i.test(baseName)) {
    return 'battle_texture';
  }
  return getGenericType(lowerBaseName);
}

function getGenericType(lowerBaseName) {
  if (lowerBaseName.endsWith('.m4v')) {
    return 'video';
  }
  if (lowerBaseName.endsWith('.png')) {
    return 'texture';
  }
  if (lowerBaseName.endsWith('.json')) {
    return 'metadata';
  }
  if (lowerBaseName.endsWith('.bytes')) {
    return 'script';
  }
  if (lowerBaseName.endsWith('.fbx')) {
    return 'animation';
  }
  return 'misc';
}

function sha1(file) {
  const hash = crypto.createHash('sha1');
  hash.update(fs.readFileSync(file));
  return hash.digest('hex');
}

function ensureUniqueDestination(targetFile, sourceSha1) {
  if (!fs.existsSync(targetFile)) {
    return {
      file: targetFile,
      duplicate: false,
    };
  }

  const targetSha1 = sha1(targetFile);
  if (targetSha1 === sourceSha1) {
    return {
      file: targetFile,
      duplicate: true,
    };
  }

  const parsed = path.parse(targetFile);
  let candidate = path.join(parsed.dir, `${parsed.name}__${sourceSha1.slice(0, 8)}${parsed.ext}`);
  let counter = 2;
  while (fs.existsSync(candidate) && sha1(candidate) !== sourceSha1) {
    candidate = path.join(
      parsed.dir,
      `${parsed.name}__${sourceSha1.slice(0, 8)}_${counter}${parsed.ext}`,
    );
    counter += 1;
  }

  return {
    file: candidate,
    duplicate: fs.existsSync(candidate),
  };
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

function main() {
  for (const dir of sourceDirectories) {
    walk(dir);
  }

  matchedFiles.sort((a, b) => {
    const folderCompare = compareFolderKeys(a.folder, b.folder);
    if (folderCompare !== 0) {
      return folderCompare;
    }
    const typeCompare = a.type.localeCompare(b.type);
    if (typeCompare !== 0) {
      return typeCompare;
    }
    return a.relativeSource.localeCompare(b.relativeSource);
  });

  const manifest = {
    generatedAt: new Date().toISOString(),
    sourceRoot,
    destinationRoot,
    grouping: 'assets/file/<characterId_or_variant>/<spine|texture|background|video|metadata|portrait|battle_spine|battle_texture|battle_metadata|animation|script>/',
    notes: [
      'Source scan includes both /edenAssets/edenAssets2 and the sibling /edenAssets2 directories when present.',
      'CardShowSpine and misspelled CardShowSping resources are both collected.',
      'CardShowSping_11300065 style names are preserved on disk, but grouped by the numeric role/variant id.',
      'CardShowSpine_11200009_3_b/q/r style multipart assets are grouped under 11200009_3.',
      'Variant split folders like 11101003_3_1 are normalized into 11101003_3.',
      'Texture-only suffixes like 11101002_01 are normalized into their base character folder.',
      'Existing identical files are skipped; differing files with the same name receive a short hash suffix.',
    ],
    totals: {
      sourceFiles: matchedFiles.length,
      copiedFiles: 0,
      duplicateFilesSkipped: 0,
      folders: 0,
      bytesCopied: 0,
      megabytesCopied: 0,
    },
    folders: {},
  };

  for (const item of matchedFiles) {
    const sourceSha1 = sha1(item.source);
    const targetDir = path.join(destinationRoot, item.folder, item.type);
    fs.mkdirSync(targetDir, {recursive: true});

    const destination = ensureUniqueDestination(path.join(targetDir, path.basename(item.source)), sourceSha1);
    const relativeFile = path.relative(destinationRoot, destination.file);
    const stat = fs.statSync(item.source);

    if (!destination.duplicate) {
      fs.copyFileSync(item.source, destination.file);
      manifest.totals.copiedFiles += 1;
      manifest.totals.bytesCopied += stat.size;
    } else {
      manifest.totals.duplicateFilesSkipped += 1;
    }

    if (!manifest.folders[item.folder]) {
      manifest.folders[item.folder] = {
        counts: {},
        files: [],
      };
    }
    const folder = manifest.folders[item.folder];
    folder.counts[item.type] = (folder.counts[item.type] || 0) + 1;
    folder.files.push({
      type: item.type,
      file: relativeFile,
      source: item.source,
      bytes: stat.size,
      sha1: sourceSha1,
      skippedAsDuplicate: destination.duplicate || undefined,
    });
  }

  manifest.totals.folders = Object.keys(manifest.folders).length;
  manifest.totals.megabytesCopied = Number((manifest.totals.bytesCopied / 1024 / 1024).toFixed(1));

  fs.writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);

  console.log(`Wrote ${outputPath}`);
  console.log(`sourceFiles=${manifest.totals.sourceFiles}`);
  console.log(`folders=${manifest.totals.folders}`);
  console.log(`copiedFiles=${manifest.totals.copiedFiles}`);
  console.log(`duplicateFilesSkipped=${manifest.totals.duplicateFilesSkipped}`);
  console.log(`megabytesCopied=${manifest.totals.megabytesCopied}`);
}

main();
