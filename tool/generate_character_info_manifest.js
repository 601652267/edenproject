#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const sourceRoot = '/Users/zhuhaiming/Desktop/edenAssets/edenAssets';
const textAssetRoot = path.join(sourceRoot, 'edenAssets', 'TextAsset');
const destinationRoot = path.join(projectRoot, 'assets', 'file');
const assetManifestPath = path.join(destinationRoot, 'character_assets_manifest.json');
const outputPath = path.join(destinationRoot, 'character_info_manifest.json');
const translationOverridesPath = path.join(__dirname, 'character_translation_overrides.json');
const translationCachePath = path.join(destinationRoot, 'character_translation_cache.json');

const sourceFiles = {
  card: path.join(textAssetRoot, 'basecarddata.lua.bytes'),
  fashion: path.join(textAssetRoot, 'basefashiondata.lua.bytes'),
  fashionBubble: path.join(textAssetRoot, 'basefashionbubbledata.lua.bytes'),
  handbookRole: path.join(textAssetRoot, 'basehandbookroledata.lua.bytes'),
  handbookRoleDetail: path.join(textAssetRoot, 'basehandbookroledetaildata.lua.bytes'),
};

const bubbleFieldLabels = {
  unlock_bubble_ids: 'unlock',
  loterry_bubble_ids: 'lottery',
  login_bubble_ids: 'login',
  bubble_ids: 'idle',
  levelUp_bubble_ids: 'levelUp',
  qualityUp_bubble_ids: 'qualityUp',
  starUp_bubble_ids: 'starUp',
  touch_bubble_ids: 'touch',
  arrayup_bubble_ids: 'arrayUp',
  attack_bubble_ids: 'attack',
  hit_bubble_ids: 'hit',
  death_bubble_ids: 'death',
  skill_bubble_ids: 'skill',
  uniqueskill_bubble_ids: 'uniqueSkill',
  win_bubble_ids: 'win',
  lose_bubble_ids: 'lose',
  familyArray_bubble_ids: 'homeEntry',
  family_bubble_ids: 'homeTalk',
};

function readText(file) {
  return fs.readFileSync(file, 'utf8');
}

function decodeLuaString(value) {
  return value
    .replace(/\\r/g, '\r')
    .replace(/\\n/g, '\n')
    .replace(/\\t/g, '\t')
    .replace(/\\"/g, '"')
    .replace(/\\\\/g, '\\');
}

function parseRows(file) {
  const text = readText(file);
  const rows = new Map();
  const rowPattern = /\[(\d+)\]\s*=\s*\{([\s\S]*?)\};/g;
  let rowMatch;
  while ((rowMatch = rowPattern.exec(text)) !== null) {
    const id = Number(rowMatch[1]);
    rows.set(id, parseFields(rowMatch[2]));
  }
  return rows;
}

function parseFields(rowText) {
  const fields = {};
  const fieldPattern = /([A-Za-z_]\w*)\s*=\s*(PUtil\.get\((\d+)\)|"((?:\\.|[^"\\])*)"|-?\d+(?:\.\d+)?)/g;
  let fieldMatch;
  while ((fieldMatch = fieldPattern.exec(rowText)) !== null) {
    const key = fieldMatch[1];
    if (fieldMatch[3]) {
      fields[key] = {
        textId: Number(fieldMatch[3]),
      };
    } else if (fieldMatch[4] !== undefined) {
      fields[key] = decodeLuaString(fieldMatch[4]);
    } else {
      const numeric = Number(fieldMatch[2]);
      fields[key] = Number.isInteger(numeric) ? numeric : numeric;
    }
  }
  return fields;
}

function parseWordFiles() {
  const wordFiles = fs
    .readdirSync(textAssetRoot)
    .filter((file) => /^base.*word.*\.lua\.bytes$/i.test(file))
    .sort();
  const words = new Map();
  const wordsCn = new Map();

  for (const fileName of wordFiles) {
    const file = path.join(textAssetRoot, fileName);
    const rows = parseRows(file);
    for (const [id, row] of rows) {
      if (typeof row.name === 'string') {
        words.set(id, row.name);
      }
      if (typeof row.name_cn === 'string') {
        wordsCn.set(id, row.name_cn);
      }
    }
  }

  return {words, wordsCn, wordFiles};
}

function loadTranslationOverrides() {
  const translations = {
    byTextId: {},
    byText: {},
    replacements: [],
  };
  if (fs.existsSync(translationOverridesPath)) {
    const overrides = JSON.parse(readText(translationOverridesPath));
    Object.assign(translations.byTextId, overrides.byTextId || {});
    Object.assign(translations.byText, overrides.byText || {});
    translations.replacements = overrides.replacements || [];
  }
  if (fs.existsSync(translationCachePath)) {
    const cache = JSON.parse(readText(translationCachePath));
    Object.assign(translations.byText, cache.byText || {});
  }
  return translations;
}

function compactValue(value, words) {
  if (!value || typeof value !== 'object' || value.textId === undefined) {
    return value;
  }
  return words.get(value.textId) || null;
}

function compactValueCn(value, words, wordsCn, translations) {
  const text = compactValue(value, words);
  if (!value || typeof value !== 'object' || value.textId === undefined) {
    return translateText(value, translations);
  }
  return translateTextById(value.textId, text, wordsCn, translations);
}

function translateTextById(textId, text, wordsCn, translations) {
  const override = translations.byTextId && translations.byTextId[String(textId)];
  if (override) {
    return override;
  }
  const official = wordsCn.get(textId);
  if (official) {
    return official;
  }
  return translateText(text, translations);
}

function translateText(text, translations) {
  if (typeof text !== 'string' || text.length === 0) {
    return null;
  }

  if (translations.byText && translations.byText[text]) {
    return translations.byText[text];
  }

  const nameTranslation = translateNameLikeText(text, translations);
  if (nameTranslation) {
    return nameTranslation;
  }

  let translated = text;
  for (const [from, to] of translations.replacements || []) {
    translated = translated.split(from).join(to);
  }
  translated = normalizeJapaneseMarkup(translated);
  translated = convertCommonJapaneseKanji(translated);
  translated = translateKnownNameSubstrings(translated, translations);

  return translated;
}

function translateNameLikeText(text, translations) {
  const match = text.match(/^(.+?)\((.+?)\)$/);
  if (match) {
    const base = translateText(match[1], translations);
    const suffix = translateText(match[2], translations);
    if (base && suffix && base !== match[1] && suffix !== match[2]) {
      return `${base}(${suffix})`;
    }
  }

  if (/^[ァ-ヴー・]+$/.test(text)) {
    return transliterateKatakanaName(text);
  }

  return null;
}

function translateKnownNameSubstrings(text, translations) {
  let translated = text;
  const entries = Object.entries(translations.byText || {}).sort((a, b) => b[0].length - a[0].length);
  for (const [from, to] of entries) {
    translated = translated.split(from).join(to);
  }
  return translated;
}

function normalizeJapaneseMarkup(text) {
  return text
    .replace(/（/g, '(')
    .replace(/）/g, ')')
    .replace(/、/g, '，')
    .replace(/。/g, '。')
    .replace(/！/g, '！')
    .replace(/？/g, '？')
    .replace(/　/g, ' ');
}

function convertCommonJapaneseKanji(text) {
  const pairs = [
    ['動物', '动物'],
    ['遺伝子', '遗传基因'],
    ['能力', '能力'],
    ['危険', '危险'],
    ['対', '对'],
    ['場所', '地点'],
    ['貧', '贫'],
    ['強', '强'],
    ['髪', '发'],
    ['真白', '雪白'],
    ['友好的', '友好'],
    ['嫌', '讨厌'],
    ['好き', '喜欢'],
    ['可愛い', '可爱'],
    ['異世界', '异世界'],
    ['新編', '新编'],
    ['募集', '招募'],
    ['お茶会', '茶会'],
    ['手伝', '帮忙'],
    ['素敵', '很棒'],
    ['愛', '爱'],
    ['女神', '女神'],
    ['冬', '冬天'],
    ['夏', '夏天'],
    ['春', '春天'],
    ['普通', '普通'],
  ];
  let converted = text;
  for (const [from, to] of pairs) {
    converted = converted.split(from).join(to);
  }
  return converted;
}

function transliterateKatakanaName(text) {
  const tokens = [
    ['ヴァ', '瓦'],
    ['ヴィ', '维'],
    ['ヴェ', '薇'],
    ['ヴォ', '沃'],
    ['ヴ', '芙'],
    ['キャ', '卡'],
    ['キュ', '丘'],
    ['キョ', '乔'],
    ['シャ', '夏'],
    ['シュ', '修'],
    ['ショ', '肖'],
    ['チャ', '恰'],
    ['チュ', '丘'],
    ['チョ', '乔'],
    ['ニャ', '妮娅'],
    ['ニュ', '纽'],
    ['ニョ', '妮奥'],
    ['ヒャ', '希娅'],
    ['ヒュ', '休'],
    ['ヒョ', '晓'],
    ['ミャ', '米娅'],
    ['ミュ', '缪'],
    ['ミョ', '妙'],
    ['リャ', '莉娅'],
    ['リュ', '琉'],
    ['リョ', '辽'],
    ['ギャ', '迦'],
    ['ギュ', '久'],
    ['ギョ', '乔'],
    ['ジャ', '加'],
    ['ジュ', '朱'],
    ['ジョ', '乔'],
    ['ビャ', '比娅'],
    ['ビュ', '比尤'],
    ['ビョ', '比奥'],
    ['ピャ', '皮娅'],
    ['ピュ', '皮尤'],
    ['ピョ', '皮奥'],
    ['ファ', '法'],
    ['フィ', '菲'],
    ['フェ', '菲'],
    ['フォ', '弗'],
    ['ティ', '蒂'],
    ['ディ', '迪'],
    ['トゥ', '图'],
    ['ドゥ', '杜'],
    ['ア', '阿'],
    ['イ', '伊'],
    ['ウ', '乌'],
    ['エ', '艾'],
    ['オ', '奥'],
    ['カ', '卡'],
    ['キ', '琪'],
    ['ク', '库'],
    ['ケ', '凯'],
    ['コ', '柯'],
    ['サ', '莎'],
    ['シ', '希'],
    ['ス', '丝'],
    ['セ', '塞'],
    ['ソ', '索'],
    ['タ', '塔'],
    ['チ', '琪'],
    ['ツ', '兹'],
    ['テ', '特'],
    ['ト', '托'],
    ['ナ', '娜'],
    ['ニ', '妮'],
    ['ヌ', '努'],
    ['ネ', '奈'],
    ['ノ', '诺'],
    ['ハ', '哈'],
    ['ヒ', '希'],
    ['フ', '芙'],
    ['ヘ', '赫'],
    ['ホ', '霍'],
    ['マ', '玛'],
    ['ミ', '米'],
    ['ム', '姆'],
    ['メ', '梅'],
    ['モ', '莫'],
    ['ヤ', '雅'],
    ['ユ', '尤'],
    ['ヨ', '约'],
    ['ラ', '拉'],
    ['リ', '莉'],
    ['ル', '露'],
    ['レ', '蕾'],
    ['ロ', '洛'],
    ['ワ', '瓦'],
    ['ン', '恩'],
    ['ガ', '迦'],
    ['ギ', '基'],
    ['グ', '古'],
    ['ゲ', '盖'],
    ['ゴ', '戈'],
    ['ザ', '扎'],
    ['ジ', '吉'],
    ['ズ', '兹'],
    ['ゼ', '泽'],
    ['ゾ', '佐'],
    ['ダ', '达'],
    ['ヂ', '吉'],
    ['ヅ', '兹'],
    ['デ', '德'],
    ['ド', '多'],
    ['バ', '巴'],
    ['ビ', '比'],
    ['ブ', '布'],
    ['ベ', '贝'],
    ['ボ', '波'],
    ['パ', '帕'],
    ['ピ', '皮'],
    ['プ', '普'],
    ['ペ', '佩'],
    ['ポ', '波'],
    ['ー', ''],
    ['・', '·'],
  ];

  let remaining = text;
  let result = '';
  while (remaining.length > 0) {
    const token = tokens.find(([from]) => remaining.startsWith(from));
    if (token) {
      result += token[1];
      remaining = remaining.slice(token[0].length);
    } else {
      result += remaining[0];
      remaining = remaining.slice(1);
    }
  }
  return result;
}

function numberList(value, separator = ':') {
  if (!value || typeof value !== 'string') {
    return [];
  }
  return value
    .split(separator)
    .map((item) => item.trim())
    .filter(Boolean)
    .map(Number)
    .filter((item) => Number.isFinite(item) && item !== 0);
}

function parseTripletList(value) {
  if (!value || typeof value !== 'string') {
    return [];
  }
  return value
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean)
    .map((item) => {
      const parts = item.split(':').map((part) => Number(part));
      return {
        id: parts[0],
        conditionType: Number.isFinite(parts[1]) ? parts[1] : null,
        conditionValue: Number.isFinite(parts[2]) ? parts[2] : null,
      };
    });
}

function parseVoiceUnlockList(value) {
  if (!value || typeof value !== 'string') {
    return [];
  }
  return value
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean)
    .map((item) => {
      const parts = item.split(':').map((part) => Number(part));
      return {
        from: Number.isFinite(parts[0]) ? parts[0] : null,
        to: Number.isFinite(parts[1]) ? parts[1] : null,
        voiceId: Number.isFinite(parts[2]) ? parts[2] : null,
      };
    });
}

function parseBirthday(value) {
  if (!value || typeof value !== 'string') {
    return null;
  }
  const parts = value.split(':').map((part) => Number(part));
  if (parts.length < 2 || !Number.isFinite(parts[0]) || !Number.isFinite(parts[1])) {
    return null;
  }

  return {
    month: parts[0],
    day: parts[1],
  };
}

function resolveDetail(id, detailRows, words, wordsCn, translations) {
  const row = detailRows.get(id);
  if (!row) {
    return null;
  }

  return removeNulls({
    id,
    nameTextId: row.name && row.name.textId,
    name: compactValue(row.name, words) || (typeof row.name === 'number' ? row.name : null),
    nameCn: compactValueCn(row.name, words, wordsCn, translations),
    textId: row.remark && row.remark.textId,
    text: compactValue(row.remark, words),
    textCn: compactValueCn(row.remark, words, wordsCn, translations),
    type: row.type || null,
    voicePath: row.voice_path || null,
    sort: row.sort || null,
    bubbleId: row.bubble_id || null,
  });
}

function resolveBubble(id, bubbleRows, words, wordsCn, translations) {
  const row = bubbleRows.get(id);
  if (!row) {
    return null;
  }

  return removeNulls({
    id,
    textId: row.bubble_text && row.bubble_text.textId,
    text: compactValue(row.bubble_text, words),
    textCn: compactValueCn(row.bubble_text, words, wordsCn, translations),
    expression: row.expression || null,
    bottomFrame: row.bottom_frame || null,
    position: row.position || null,
    direction: row.direction || null,
    voicePath: row.voice_path || null,
    topPosition: row.top_position || null,
  });
}

function resolveBubbleIds(value, bubbleRows, words, wordsCn, translations) {
  return numberList(value).map((id) => resolveBubble(id, bubbleRows, words, wordsCn, translations) || {id});
}

function buildBubbleGroups(fashion, bubbleRows, words, wordsCn, translations) {
  const groups = {};
  for (const [field, label] of Object.entries(bubbleFieldLabels)) {
    const items = resolveBubbleIds(fashion[field], bubbleRows, words, wordsCn, translations);
    if (items.length > 0) {
      groups[label] = items;
    }
  }
  return groups;
}

function normalizeAssetName(value) {
  return String(value || '')
    .replace(/^CardShowSpine_/i, '')
    .toLowerCase();
}

function getFolderCardId(folder) {
  const match = folder.match(/^(\d{8})(.*)$/);
  if (!match) {
    return null;
  }
  return {
    cardId: Number(match[1]),
    variantSuffix: match[2] || null,
  };
}

function getFolderSpineNames(files) {
  const names = new Set();
  for (const item of files || []) {
    if (item.type !== 'spine') {
      continue;
    }
    const itemPath = item.file || item.duplicateOf || item.source;
    if (!itemPath) {
      continue;
    }
    const baseName = path.basename(itemPath).replace(/\.(atlas|skel)\.prefab$/i, '');
    if (baseName) {
      names.add(normalizeAssetName(baseName));
    }
  }
  return names;
}

function buildFashionInfo(fashion, bubbleRows, words, wordsCn, translations) {
  return removeNulls({
    id: fashion.id,
    type: fashion.type || null,
    setNum: fashion.setNum || null,
    cardId: fashion.card_id || null,
    nameTextId: fashion.name && fashion.name.textId,
    name: compactValue(fashion.name, words),
    nameCn: compactValueCn(fashion.name, words, wordsCn, translations),
    remarkTextId: fashion.remark && fashion.remark.textId,
    remark: compactValue(fashion.remark, words),
    remarkCn: compactValueCn(fashion.remark, words, wordsCn, translations),
    unlockRemarkTextId: fashion.unlock_remark && fashion.unlock_remark.textId,
    unlockRemark: compactValue(fashion.unlock_remark, words),
    unlockRemarkCn: compactValueCn(fashion.unlock_remark, words, wordsCn, translations),
    unlockQuality: fashion.unlock_quality || null,
    showSpine: fashion.show_spine || null,
    showSpineType: fashion.show_spine_type || null,
    showSpineScale: fashion.show_spine_scale || null,
    showSpinePosition: fashion.show_spine_position || null,
    showSpineFinal: fashion.show_spine_Final || null,
    showTexture: fashion.show_texture || null,
    showTextureScale: fashion.show_texture_scale || null,
    showTexturePosition: fashion.show_texture_position || null,
    showTextureSize: fashion.show_texture_size || null,
    showCg: fashion.show_cg || null,
    bubbleGroups: buildBubbleGroups(fashion, bubbleRows, words, wordsCn, translations),
  });
}

function removeNulls(value) {
  if (Array.isArray(value)) {
    return value;
  }
  const result = {};
  for (const [key, item] of Object.entries(value)) {
    if (item === null || item === undefined) {
      continue;
    }
    if (typeof item === 'object' && !Array.isArray(item) && Object.keys(item).length === 0) {
      continue;
    }
    result[key] = item;
  }
  return result;
}

function compareNumericStrings(a, b) {
  const numberA = Number(a);
  const numberB = Number(b);
  if (Number.isFinite(numberA) && Number.isFinite(numberB) && numberA !== numberB) {
    return numberA - numberB;
  }
  return String(a).localeCompare(String(b));
}

function main() {
  const assetManifest = JSON.parse(readText(assetManifestPath));
  const folderEntries = assetManifest.folders || {};
  const {words, wordsCn, wordFiles} = parseWordFiles();
  const translations = loadTranslationOverrides();
  const cardRows = parseRows(sourceFiles.card);
  const fashionRows = parseRows(sourceFiles.fashion);
  const bubbleRows = parseRows(sourceFiles.fashionBubble);
  const handbookRoleRows = parseRows(sourceFiles.handbookRole);
  const detailRows = parseRows(sourceFiles.handbookRoleDetail);

  const fashionsByCardId = new Map();
  for (const fashion of fashionRows.values()) {
    if (!fashion.card_id) {
      continue;
    }
    if (!fashionsByCardId.has(fashion.card_id)) {
      fashionsByCardId.set(fashion.card_id, []);
    }
    fashionsByCardId.get(fashion.card_id).push(fashion);
  }
  for (const list of fashionsByCardId.values()) {
    list.sort((a, b) => (a.id || 0) - (b.id || 0));
  }

  const cards = {};
  const folders = {};
  const missing = {
    cards: [],
    handbookRoles: [],
  };

  const cardIds = new Set();
  for (const folder of Object.keys(folderEntries)) {
    const parsed = getFolderCardId(folder);
    if (parsed) {
      cardIds.add(parsed.cardId);
    }
  }

  for (const cardId of [...cardIds].sort((a, b) => a - b)) {
    const card = cardRows.get(cardId);
    const handbook = handbookRoleRows.get(cardId);
    const fashions = fashionsByCardId.get(cardId) || [];

    if (!card) {
      missing.cards.push(cardId);
    }
    if (!handbook) {
      missing.handbookRoles.push(cardId);
    }

    const storyRefs = parseTripletList(handbook && handbook.story);
    const voiceRefs = parseTripletList(handbook && handbook.voice);
    const voiceUnlockRefs = parseVoiceUnlockList(handbook && handbook.voice_id);

    cards[String(cardId)] = removeNulls({
      id: cardId,
      nameTextId: card && card.name && card.name.textId,
      name: card ? compactValue(card.name, words) : null,
      nameCn: card ? compactValueCn(card.name, words, wordsCn, translations) : null,
      cvNameTextId: card && card.cv_name && card.cv_name.textId,
      cvName: card ? compactValue(card.cv_name, words) : null,
      cvNameCn: card ? compactValueCn(card.cv_name, words, wordsCn, translations) : null,
      lotteryWordTextId: card && card.lotteryWord && card.lotteryWord.textId,
      lotteryWord: card ? compactValue(card.lotteryWord, words) : null,
      lotteryWordCn: card ? compactValueCn(card.lotteryWord, words, wordsCn, translations) : null,
      voicePath: card && card.voice_path,
      lotteryShow: card && card.lottery_show,
      lotteryPic: card && card.lottery_pic,
      rarity: card && card.intelligence,
      fashionIds: card ? numberList(card.fashion_ids) : [],
      profile: handbook
        ? removeNulls({
            remarkTextId: handbook.remark && handbook.remark.textId,
            remark: compactValue(handbook.remark, words),
            remarkCn: compactValueCn(handbook.remark, words, wordsCn, translations),
            mapPath: handbook.map_path || null,
            mapNameTextId: handbook.map_name && handbook.map_name.textId,
            mapName: compactValue(handbook.map_name, words),
            mapNameCn: compactValueCn(handbook.map_name, words, wordsCn, translations),
            birthday: parseBirthday(handbook.birthday),
          })
        : null,
      stories: storyRefs.map((ref) => ({
        ...ref,
        detail: resolveDetail(ref.id, detailRows, words, wordsCn, translations),
      })),
      voiceLines: voiceRefs.map((ref) => ({
        ...ref,
        detail: resolveDetail(ref.id, detailRows, words, wordsCn, translations),
      })),
      voiceUnlocks: voiceUnlockRefs,
      fashions: fashions.map((fashion) => buildFashionInfo(fashion, bubbleRows, words, wordsCn, translations)),
    });
  }

  for (const folder of Object.keys(folderEntries).sort(compareNumericStrings)) {
    const parsed = getFolderCardId(folder);
    if (!parsed) {
      continue;
    }

    const spineNames = getFolderSpineNames(folderEntries[folder].files);
    const fashionInfos = cards[String(parsed.cardId)]?.fashions || [];
    const candidateFashionIds = fashionInfos.map((fashion) => fashion.id);
    const matchedFashionIds = fashionInfos
      .filter((fashion) => {
        if (!fashion.showSpine) {
          return false;
        }
        return spineNames.has(normalizeAssetName(fashion.showSpine));
      })
      .map((fashion) => fashion.id);
    const variantFashionIds =
      matchedFashionIds.length > 0
        ? matchedFashionIds
        : fashionInfos
            .filter((fashion) => parsed.variantSuffix && parsed.variantSuffix.startsWith(`_${fashion.type}`))
            .map((fashion) => fashion.id);

    folders[folder] = removeNulls({
      folder,
      cardId: parsed.cardId,
      variantSuffix: parsed.variantSuffix,
      name: cards[String(parsed.cardId)] && cards[String(parsed.cardId)].name,
      nameCn: cards[String(parsed.cardId)] && cards[String(parsed.cardId)].nameCn,
      infoFile: `assets/file/${folder}/character_info.json`,
      candidateFashionIds,
      matchedFashionIds,
      inferredFashionIds: variantFashionIds,
      assetCounts: folderEntries[folder].counts || {},
    });
  }

  const output = {
    generatedAt: new Date().toISOString(),
    sourceRoot,
    destinationRoot,
    sources: {
      textAssetRoot,
      dataTables: sourceFiles,
      wordTables: wordFiles.map((fileName) => path.join(textAssetRoot, fileName)),
      assetManifest: assetManifestPath,
      translationOverrides: translationOverridesPath,
      translationCache: translationCachePath,
    },
    notes: [
      'folders is keyed by assets/file folder name; cards is keyed by the base 8-digit role id.',
      'Dialog text comes from BaseFashionData bubble id groups resolved through BaseFashionBubbleData and word tables.',
      'homeTalk corresponds to the home/family click talk ids; touch corresponds to touch feedback ids.',
      'Voice and story text comes from BaseHandbookRoleData plus BaseHandbookRoleDetailData.',
      'Chinese fields use source name_cn when available, then tool/character_translation_overrides.json, then a lightweight local fallback.',
    ],
    totals: {
      folders: Object.keys(folders).length,
      cards: Object.keys(cards).length,
      words: words.size,
      translatedWords: wordsCn.size,
      missingCards: missing.cards.length,
      missingHandbookRoles: missing.handbookRoles.length,
    },
    missing,
    folders,
    cards,
  };

  writePerFolderInfoFiles(folders, cards, folderEntries, output.generatedAt);
  fs.writeFileSync(outputPath, `${JSON.stringify(output, null, 2)}\n`);

  console.log(`Wrote ${outputPath}`);
  console.log(`folders=${output.totals.folders} cards=${output.totals.cards} words=${output.totals.words}`);
  console.log(`missingCards=${output.totals.missingCards} missingHandbookRoles=${output.totals.missingHandbookRoles}`);
}

function writePerFolderInfoFiles(folders, cards, folderEntries, generatedAt) {
  for (const [folder, folderInfo] of Object.entries(folders)) {
    const card = cards[String(folderInfo.cardId)] || null;
    const selectedFashionIds =
      folderInfo.inferredFashionIds && folderInfo.inferredFashionIds.length > 0
        ? folderInfo.inferredFashionIds
        : folderInfo.matchedFashionIds && folderInfo.matchedFashionIds.length > 0
          ? folderInfo.matchedFashionIds
          : folderInfo.candidateFashionIds || [];
    const cardWithoutFashions = card ? {...card} : null;
    const fashions = cardWithoutFashions ? cardWithoutFashions.fashions || [] : [];
    if (cardWithoutFashions) {
      delete cardWithoutFashions.fashions;
    }

    const selectedFashions =
      selectedFashionIds.length > 0
        ? fashions.filter((fashion) => selectedFashionIds.includes(fashion.id))
        : fashions;
    const folderOutput = {
      generatedAt,
      sourceManifest: 'assets/file/character_info_manifest.json',
      folder: folderInfo.folder,
      cardId: folderInfo.cardId,
      variantSuffix: folderInfo.variantSuffix || null,
      name: folderInfo.name || null,
      nameCn: folderInfo.nameCn || null,
      assetRoot: `assets/file/${folderInfo.folder}`,
      assetCounts: folderInfo.assetCounts || {},
      assets: normalizeAssetReferences((folderEntries[folder] && folderEntries[folder].files) || []),
      selectedFashionIds,
      role: cardWithoutFashions,
      fashions: selectedFashions,
    };

    fs.writeFileSync(
      path.join(destinationRoot, folder, 'character_info.json'),
      `${JSON.stringify(folderOutput, null, 2)}\n`,
    );
  }
}

function normalizeAssetReferences(files) {
  return files.map((file) => {
    const item = {...file};
    if (item.file) {
      item.file = normalizeAssetPath(item.file);
    }
    if (item.duplicateOf) {
      item.duplicateOf = normalizeAssetPath(item.duplicateOf);
    }
    return item;
  });
}

function normalizeAssetPath(file) {
  if (typeof file !== 'string' || file.startsWith('assets/file/')) {
    return file;
  }
  return `assets/file/${file}`;
}

main();
