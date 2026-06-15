#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const galleryRoot = path.join(
  projectRoot,
  'assets',
  'gallery_player',
  'gallery-assets',
);
const characterRoot = path.join(galleryRoot, 'file');
const voiceRoot = path.join(galleryRoot, 'voice');
const sourceRoot =
  process.env.EDEN_ASSETS_ROOT || '/Users/zhuhaiming/Desktop/edenAssets';

const audioExtensions = new Set(['.wav', '.mp3', '.ogg', '.m4a', '.aac']);

const categories = [
  {key: 'recruitment', name: '招募语音'},
  {key: 'login', name: '登录语音'},
  {key: 'idle', name: '待机语音'},
  {key: 'progression', name: '养成语音'},
  {key: 'affection', name: '好感度语音'},
  {key: 'sortie', name: '出击语音'},
  {key: 'battle', name: '战斗语音'},
  {key: 'home', name: '家园语音'},
  {key: 'special', name: '特殊语音'},
  {key: 'uncategorized', name: '未分类语音'},
];
const categoryOrder = new Map(
  categories.map((category, index) => [category.key, index]),
);
const categoryNameByKey = new Map(
  categories.map((category) => [category.key, category.name]),
);

function walkFiles(dir, predicate, result = []) {
  if (!fs.existsSync(dir)) {
    return result;
  }

  for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
    if (entry.name === '.DS_Store') {
      continue;
    }

    const current = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkFiles(current, predicate, result);
    } else if (entry.isFile() && predicate(current)) {
      result.push(current);
    }
  }

  return result;
}

function compareFolderKeys(a, b) {
  const aParts = a.split('_').map(Number);
  const bParts = b.split('_').map(Number);
  const length = Math.max(aParts.length, bParts.length);
  for (let index = 0; index < length; index += 1) {
    const diff = (aParts[index] || 0) - (bParts[index] || 0);
    if (diff !== 0) {
      return diff;
    }
  }
  return a.localeCompare(b);
}

function buildAudioIndex() {
  const files = walkFiles(sourceRoot, (file) =>
    audioExtensions.has(path.extname(file).toLowerCase()),
  );
  const index = new Map();

  for (const file of files) {
    const extension = path.extname(file);
    const name = path.basename(file, extension);
    const key = name.toLowerCase();
    const list = index.get(key) || [];
    list.push(file);
    index.set(key, list);
  }

  for (const list of index.values()) {
    list.sort((left, right) => left.length - right.length || left.localeCompare(right));
  }

  return index;
}

function suffixOf(voicePath) {
  const match = String(voicePath || '').match(
    /_(Battle_Hit|Battle_Die|Battle_N|Battle_H|Battle_C|Home_Talk|Home_In|Bir_Cr_One|Bir_Mas|Bir_Ser|Interaction|Valentine|Stage|Main|Star|Get|In|Go|Win|Fail|Game)(?:_|$)/,
  );
  return match ? match[1] : '';
}

function classifyVoiceLine(line) {
  const detail = line && line.detail ? line.detail : {};
  const voicePath = detail.voicePath || '';
  const suffix = suffixOf(voicePath);
  const name = `${detail.nameCn || ''} ${detail.name || ''}`;

  if (suffix === 'Get' || /成员招募|メンバー募集/.test(name)) {
    return {
      category: 'recruitment',
      subcategory: 'recruitment',
      subcategoryName: '招募',
    };
  }
  if (suffix === 'In' || /登录语音|ログイン/.test(name)) {
    return {category: 'login', subcategory: 'login', subcategoryName: '登录'};
  }
  if (suffix === 'Main' || /待机语音|待機/.test(name)) {
    return {category: 'idle', subcategory: 'idle', subcategoryName: '待机'};
  }
  if (suffix === 'Interaction' || /好感度|互动语音/.test(name)) {
    return {
      category: 'affection',
      subcategory: 'affection',
      subcategoryName: '好感度',
    };
  }
  if (suffix === 'Stage') {
    return {
      category: 'progression',
      subcategory: 'stage',
      subcategoryName: '突破/立绘解锁',
    };
  }
  if (suffix === 'Star') {
    return {
      category: 'progression',
      subcategory: 'star',
      subcategoryName: '升星',
    };
  }
  if (suffix === 'Go') {
    return {category: 'sortie', subcategory: 'sortie', subcategoryName: '出击'};
  }
  if (suffix === 'Battle_N') {
    return {
      category: 'battle',
      subcategory: 'normalAttack',
      subcategoryName: '普通攻击',
    };
  }
  if (suffix === 'Battle_Hit') {
    return {category: 'battle', subcategory: 'hit', subcategoryName: '受击'};
  }
  if (suffix === 'Battle_Die') {
    return {
      category: 'battle',
      subcategory: 'defeat',
      subcategoryName: '战斗倒下',
    };
  }
  if (suffix === 'Battle_H') {
    return {category: 'battle', subcategory: 'skill', subcategoryName: '技能'};
  }
  if (suffix === 'Battle_C') {
    return {category: 'battle', subcategory: 'ultimate', subcategoryName: '必杀'};
  }
  if (suffix === 'Win') {
    return {category: 'battle', subcategory: 'win', subcategoryName: '胜利'};
  }
  if (suffix === 'Fail') {
    return {category: 'battle', subcategory: 'fail', subcategoryName: '失败'};
  }
  if (suffix === 'Home_In') {
    return {category: 'home', subcategory: 'homeEntry', subcategoryName: '进屋'};
  }
  if (suffix === 'Home_Talk') {
    return {category: 'home', subcategory: 'homeTalk', subcategoryName: '通讯'};
  }
  if (suffix === 'Valentine' || suffix.startsWith('Bir_') || suffix === 'Game') {
    return {category: 'special', subcategory: suffix || 'special', subcategoryName: '特殊'};
  }

  return {
    category: 'uncategorized',
    subcategory: 'uncategorized',
    subcategoryName: '未分类',
  };
}

function findAudio(audioIndex, voicePath) {
  if (!voicePath) {
    return null;
  }

  const direct = audioIndex.get(String(voicePath).toLowerCase());
  if (direct && direct.length > 0) {
    return direct[0];
  }

  return null;
}

function copyAudio({source, voicePath, copiedFiles}) {
  const extension = path.extname(source) || '.wav';
  const fileName = `${voicePath}${extension}`;
  const destination = path.join(voiceRoot, fileName);
  const sourceStat = fs.statSync(source);
  fs.mkdirSync(voiceRoot, {recursive: true});

  if (
    !fs.existsSync(destination) ||
    fs.statSync(destination).size !== sourceStat.size
  ) {
    fs.copyFileSync(source, destination);
    copiedFiles.count += 1;
    copiedFiles.bytes += sourceStat.size;
  }

  return {
    audioFile: fileName,
    audioPath: `/gallery-assets/voice/${fileName}`,
    audioBytes: sourceStat.size,
  };
}

function compareGroups(left, right) {
  const leftOrder = categoryOrder.get(left.category) ?? 999;
  const rightOrder = categoryOrder.get(right.category) ?? 999;
  return leftOrder - rightOrder || left.category.localeCompare(right.category);
}

function enrichVoiceLines(role, audioIndex, stats) {
  const groups = new Map();
  const lines = Array.isArray(role.voiceLines) ? role.voiceLines : [];

  role.voiceLines = lines.map((line) => {
    const detail = line && line.detail ? line.detail : {};
    const voicePath = detail.voicePath || '';
    const classification = classifyVoiceLine(line);
    const categoryName = categoryNameByKey.get(classification.category) || '未分类语音';
    const source = findAudio(audioIndex, voicePath);
    let audio = {
      audioFile: null,
      audioPath: null,
      audioBytes: 0,
    };

    if (source) {
      audio = copyAudio({
        source,
        voicePath,
        copiedFiles: stats.copiedFiles,
      });
      stats.matchedVoiceLines += 1;
    } else if (voicePath) {
      stats.missingVoiceLines += 1;
      stats.missingVoicePaths.add(voicePath);
    }

    const group = groups.get(classification.category) || {
      category: classification.category,
      categoryName,
      count: 0,
      voiceLineIds: [],
      voicePaths: [],
    };
    group.count += 1;
    if (line.id !== undefined) {
      group.voiceLineIds.push(line.id);
    }
    if (voicePath) {
      group.voicePaths.push(voicePath);
    }
    groups.set(classification.category, group);

    return {
      ...line,
      category: classification.category,
      categoryName,
      subcategory: classification.subcategory,
      subcategoryName: classification.subcategoryName,
      audioFile: audio.audioFile,
      audioPath: audio.audioPath,
      audioBytes: audio.audioBytes,
      detail: {
        ...detail,
        voiceCategory: classification.category,
        voiceCategoryName: categoryName,
        voiceSubcategory: classification.subcategory,
        voiceSubcategoryName: classification.subcategoryName,
        audioFile: audio.audioFile,
        audioPath: audio.audioPath,
        audioBytes: audio.audioBytes,
      },
    };
  });

  role.voiceGroups = Array.from(groups.values()).sort(compareGroups);
}

function enrichRoleVoice(role, audioIndex, stats) {
  const voicePath = role.voicePath || '';
  if (!voicePath) {
    return;
  }

  const source = findAudio(audioIndex, voicePath);
  if (!source) {
    stats.missingRoleVoicePaths.add(voicePath);
    role.voiceAudioFile = null;
    role.voiceAudioPath = null;
    role.voiceAudioBytes = 0;
    return;
  }

  const audio = copyAudio({
    source,
    voicePath,
    copiedFiles: stats.copiedFiles,
  });
  role.voiceAudioFile = audio.audioFile;
  role.voiceAudioPath = audio.audioPath;
  role.voiceAudioBytes = audio.audioBytes;
}

function processCharacterInfo(file, audioIndex, stats) {
  const json = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!json.role || typeof json.role !== 'object') {
    return;
  }

  enrichRoleVoice(json.role, audioIndex, stats);
  enrichVoiceLines(json.role, audioIndex, stats);
  delete json.voiceProcessedAt;
  json.voiceProcessingVersion = 1;
  json.voiceAssetRoot = '/gallery-assets/voice';

  fs.writeFileSync(file, `${JSON.stringify(json, null, 2)}\n`);
  stats.processedFiles += 1;
}

function main() {
  if (!fs.existsSync(characterRoot)) {
    throw new Error(`Character root not found: ${characterRoot}`);
  }
  if (!fs.existsSync(sourceRoot)) {
    throw new Error(`Eden assets root not found: ${sourceRoot}`);
  }

  const characterInfoFiles = walkFiles(
    characterRoot,
    (file) => path.basename(file) === 'character_info.json',
  ).sort((left, right) =>
    compareFolderKeys(path.basename(path.dirname(left)), path.basename(path.dirname(right))),
  );
  const audioIndex = buildAudioIndex();
  const stats = {
    processedFiles: 0,
    matchedVoiceLines: 0,
    missingVoiceLines: 0,
    missingVoicePaths: new Set(),
    missingRoleVoicePaths: new Set(),
    copiedFiles: {
      count: 0,
      bytes: 0,
    },
  };

  for (const file of characterInfoFiles) {
    processCharacterInfo(file, audioIndex, stats);
  }

  const voiceFiles = walkFiles(voiceRoot, (file) =>
    audioExtensions.has(path.extname(file).toLowerCase()),
  );
  const voiceBytes = voiceFiles.reduce(
    (total, file) => total + fs.statSync(file).size,
    0,
  );
  const summary = {
    characterInfoFiles: characterInfoFiles.length,
    processedFiles: stats.processedFiles,
    matchedVoiceLines: stats.matchedVoiceLines,
    missingVoiceLines: stats.missingVoiceLines,
    missingVoicePaths: Array.from(stats.missingVoicePaths).sort(),
    missingRoleVoicePaths: Array.from(stats.missingRoleVoicePaths).sort(),
    voiceFiles: voiceFiles.length,
    voiceTotalMB: Number((voiceBytes / 1024 / 1024).toFixed(2)),
    newlyCopiedAudioFiles: stats.copiedFiles.count,
    newlyCopiedAudioMB: Number((stats.copiedFiles.bytes / 1024 / 1024).toFixed(2)),
    voiceRoot: path.relative(projectRoot, voiceRoot).split(path.sep).join('/'),
  };

  fs.writeFileSync(
    path.join(voiceRoot, 'voice_processing_summary.json'),
    `${JSON.stringify(summary, null, 2)}\n`,
  );
  console.log(JSON.stringify(summary, null, 2));
}

main();
