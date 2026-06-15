#!/usr/bin/env python3

import json
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
ASSETS_ROOT = PROJECT_ROOT / "assets" / "file"
OVERRIDES_PATH = PROJECT_ROOT / "tool" / "character_translation_overrides.json"
CACHE_PATH = ASSETS_ROOT / "character_translation_cache.json"
TRANSLATION_TIMEOUT_SECONDS = int(os.environ.get("CHARACTER_TRANSLATION_TIMEOUT", "45"))
BATCH_CHAR_LIMIT = int(os.environ.get("CHARACTER_TRANSLATION_BATCH_CHARS", "1000"))

CN_FIELD_MAP = {
    "name": ("nameCn", "nameTextId"),
    "text": ("textCn", "textId"),
    "remark": ("remarkCn", "remarkTextId"),
    "mapName": ("mapNameCn", "mapNameTextId"),
    "cvName": ("cvNameCn", "cvNameTextId"),
    "lotteryWord": ("lotteryWordCn", "lotteryWordTextId"),
    "unlockRemark": ("unlockRemarkCn", "unlockRemarkTextId"),
}

JP_RE = re.compile(r"[\u3040-\u30ff]")

LATIN_NAME_REPLACEMENTS = {
    "Shannon": "夏农",
    "Shanon": "夏农",
    "Olivia": "奥利维亚",
    "April": "艾普莉尔",
    "Lily": "莉莉",
    "Francesca": "弗兰切斯卡",
    "Evelyn": "伊芙琳",
    "Sophia": "索菲娅",
    "Ritta": "莉塔",
    "Rita": "莉塔",
    "Nonno": "侬侬",
    "Sylvie": "希尔维",
    "Sierra": "希耶拉",
    "Lavie": "拉薇",
    "Lavey": "拉薇",
    "Ravi": "拉薇",
    "Yuraserena": "尤拉塞蕾娜",
    "Yura Serena": "尤拉塞蕾娜",
}

POST_REPLACEMENTS = {
    "四月": "艾普莉尔",
    "香农": "夏农",
    "奥利维亚": "奥利维亚",
    "拉维": "拉薇",
    "拉薇": "拉薇",
    "尤拉塞雷娜": "尤拉塞蕾娜",
    "尤拉塞蕾娜": "尤拉塞蕾娜",
    "Leader": "队长",
    "leader": "队长",
    "Pride": "普莱德",
    "Red": "Red",
    "Unred": "Unred",
    "quest": "任务",
    "Quest": "任务",
}


class TranslationTimeout(Exception):
    pass


def handle_translation_timeout(signum, frame):
    raise TranslationTimeout("translation request timed out")


signal.signal(signal.SIGALRM, handle_translation_timeout)


def load_json(path, default):
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def get_nested_text_id(obj, key):
    direct = CN_FIELD_MAP[key][1]
    if direct in obj:
        return str(obj[direct])
    return None


def has_japanese(text):
    return isinstance(text, str) and bool(JP_RE.search(text))


def normalize_cn(text):
    if not isinstance(text, str):
        return text
    text = text.replace(" ,", "，").replace(",", "，")
    text = text.replace(" .", "。")
    text = text.replace(" ?", "？").replace(" !", "！")
    text = text.replace("“ ", "“").replace(" ”", "”")
    text = text.replace(" :", ":")
    for source, target in LATIN_NAME_REPLACEMENTS.items():
        text = re.sub(rf"\b{re.escape(source)}\b", target, text, flags=re.IGNORECASE)
    for source, target in POST_REPLACEMENTS.items():
        text = re.sub(rf"\b{re.escape(source)}\b", target, text)
    return text.strip()


def split_long_text(text, max_len=700):
    paragraphs = re.split(r"(\n+)", text)
    chunks = []
    current = ""
    for part in paragraphs:
        if len(current) + len(part) <= max_len:
            current += part
            continue
        if current:
            chunks.append(current)
            current = ""
        if len(part) <= max_len:
            current = part
            continue
        sentences = re.split(r"([。！？!?])", part)
        sentence = ""
        for piece in sentences:
            sentence += piece
            if piece in "。！？!?":
                if len(current) + len(sentence) > max_len and current:
                    chunks.append(current)
                    current = ""
                current += sentence
                sentence = ""
        if sentence:
            if len(current) + len(sentence) > max_len and current:
                chunks.append(current)
                current = ""
            current += sentence
    if current:
        chunks.append(current)
    return chunks


def collect_objects(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from collect_objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from collect_objects(child)


def translate_text(text, translator, overrides, cache):
    if not isinstance(text, str) or not text:
        return None
    if text in overrides["byText"]:
        return overrides["byText"][text]
    if text in cache["byText"] and not has_japanese(cache["byText"].get(text, "")):
        return cache["byText"][text]

    chunks = split_long_text(text)
    translated_chunks = []
    for chunk in chunks:
        if not chunk.strip():
            translated_chunks.append(chunk)
            continue
        translated_chunks.append(translator(chunk))
    translated = normalize_cn("".join(translated_chunks))
    cache["byText"][text] = translated
    return translated


def needs_model_translation(text, overrides, cache):
    return (
        isinstance(text, str)
        and text
        and text not in overrides["byText"]
        and (text not in cache["byText"] or has_japanese(cache["byText"].get(text, "")))
    )


def should_retranslate_all():
    return os.environ.get("RETRANSLATE_ALL_CN") == "1"


def collect_needed_texts(value, overrides, cache, needed):
    if isinstance(value, dict):
        for key in CN_FIELD_MAP:
            if key in value:
                text = value[key]
                text_id = get_nested_text_id(value, key)
                if text_id and text_id in overrides["byTextId"]:
                    continue
                if needs_model_translation(text, overrides, cache):
                    needed[text] = True
        for child in value.values():
            collect_needed_texts(child, overrides, cache, needed)
    elif isinstance(value, list):
        for child in value:
            collect_needed_texts(child, overrides, cache, needed)


def translate_many(texts, translator, cache):
    short_batch = []
    for text in texts:
        if len(text) > 900:
            cache["byText"][text] = translate_text(text, translator, {"byText": {}, "byTextId": {}}, cache)
        else:
            short_batch.append(text)

    batch = []
    batch_chars = 0
    for text in short_batch:
        if batch and batch_chars + len(text) > BATCH_CHAR_LIMIT:
            translate_batch(batch, translator, cache)
            batch = []
            batch_chars = 0
        batch.append(text)
        batch_chars += len(text)
    if batch:
        translate_batch(batch, translator, cache)


def translate_batch(texts, translator, cache):
    if len(texts) == 1:
        text = texts[0]
        cache["byText"][text] = normalize_cn(translator(text))
        return

    payload_parts = []
    for index, text in enumerate(texts):
        payload_parts.append(f"<T{index}>{text}</T{index}>")
    payload = "\n".join(payload_parts)
    try:
        translated = translator(payload)
    except Exception as error:
        print(f"batch translation failed; falling back to single texts: {error}", flush=True)
        translated = ""

    parsed = {}
    if translated:
        for index in range(len(texts)):
            pattern = re.compile(rf"<\s*T\s*{index}\s*>(.*?)<\s*/\s*T\s*{index}\s*>", re.S | re.I)
            match = pattern.search(translated)
            if match:
                parsed[index] = normalize_cn(match.group(1))

    for index, text in enumerate(texts):
        if index in parsed and parsed[index]:
            cache["byText"][text] = parsed[index]
        else:
            cache["byText"][text] = normalize_cn(translator(text))


def translate_value(obj, key, translator, overrides, cache):
    if key not in obj or not isinstance(obj[key], str) or obj[key] == "":
        return
    cn_key, _ = CN_FIELD_MAP[key]
    text = obj[key]
    text_id = get_nested_text_id(obj, key)
    if text_id and text_id in overrides["byTextId"]:
        obj[cn_key] = overrides["byTextId"][text_id]
        return
    obj[cn_key] = translate_text(text, translator, overrides, cache)


def translate_document(document, translator, overrides, cache):
    needed = {}
    collect_needed_texts(document, overrides, cache, needed)
    if needed:
        translate_many(list(needed.keys()), translator, cache)
    for obj in collect_objects(document):
        for key in CN_FIELD_MAP:
            if key in obj:
                translate_value(obj, key, translator, overrides, cache)


def build_translator():
    sys.path.insert(0, "/private/tmp/eden_translate_pkgs")
    provider = os.environ.get("CHARACTER_TRANSLATOR", "google")
    if provider == "google":
        from deep_translator import GoogleTranslator

        google = GoogleTranslator(source="ja", target="zh-CN")

        def google_translator(text):
            last_error = None
            for attempt in range(1, 4):
                signal.alarm(TRANSLATION_TIMEOUT_SECONDS)
                try:
                    return google.translate(text)
                except Exception as error:
                    last_error = error
                    print(f"google translate retry {attempt}/3: {error}", flush=True)
                    time.sleep(attempt)
                finally:
                    signal.alarm(0)
            raise last_error

        return google_translator

    os.environ.setdefault("XDG_DATA_HOME", "/private/tmp/eden_argos_data")
    from argostranslate import translate

    def argos_translator(text):
        signal.alarm(TRANSLATION_TIMEOUT_SECONDS)
        try:
            return translate.translate(text, "ja", "zh")
        finally:
            signal.alarm(0)

    return argos_translator


def main():
    overrides = load_json(OVERRIDES_PATH, {})
    overrides = {
        "byTextId": {str(k): v for k, v in (overrides.get("byTextId") or {}).items()},
        "byText": overrides.get("byText") or {},
    }
    cache = load_json(CACHE_PATH, {"byText": {}})
    cache.setdefault("byText", {})
    if should_retranslate_all():
        print("RETRANSLATE_ALL_CN=1; clearing old translation cache", flush=True)
        cache["byText"] = {}

    translator = build_translator()

    files = sorted(ASSETS_ROOT.glob("*/character_info.json"))

    total = len(files)
    started_at = time.time()
    for index, file_path in enumerate(files, start=1):
        relative_path = file_path.relative_to(PROJECT_ROOT)
        print(f"translating {index}/{total}: {relative_path}", flush=True)
        document = load_json(file_path, {})
        translate_document(document, translator, overrides, cache)
        save_json(file_path, document)
        save_json(CACHE_PATH, cache)
        elapsed = max(time.time() - started_at, 0.1)
        print(
            f"done {index}/{total}; cache={len(cache['byText'])}; elapsed={elapsed:.1f}s",
            flush=True,
        )

    save_json(CACHE_PATH, cache)
    subprocess.run(["node", "tool/generate_character_info_manifest.js"], cwd=PROJECT_ROOT, check=True)


if __name__ == "__main__":
    main()
