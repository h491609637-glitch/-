#!/usr/bin/env python3
"""
新托福词库数据处理管线

输出：
- core_toefl.json
- full_toefl.json
- stats.txt
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import subprocess
import sys
import zipfile
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple

import pandas as pd
import requests


# ----------------------------
# 基础工具
# ----------------------------

WORD_RE = re.compile(r"^[a-z][a-z'\-]{1,30}$")
START_WORD_RE = re.compile(r"^[\s\-\*\d\.)\]]*([A-Za-z][A-Za-z'\-]{1,30})\b")


@dataclass
class KajWord:
    meaning: str
    pos: str


@dataclass
class ECDictWord:
    phonetic: str
    pos: str
    coca_rank: Optional[int]
    tags: Set[str]
    meaning: str


def log(msg: str) -> None:
    print(msg, flush=True)


def normalize_word(word: str) -> str:
    return (word or "").strip().lower()


def clean_text(text: str) -> str:
    text = (text or "").replace("\r", " ").replace("\n", " ").strip()
    text = re.sub(r"\s+", " ", text)
    return text


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def run(cmd: List[str], cwd: Optional[Path] = None) -> None:
    subprocess.run(cmd, cwd=str(cwd) if cwd else None, check=True)


def request_download(url: str, path: Path, timeout: int = 60) -> None:
    ensure_parent(path)
    with requests.get(url, stream=True, timeout=timeout) as resp:
        resp.raise_for_status()
        with open(path, "wb") as f:
            for chunk in resp.iter_content(chunk_size=1024 * 1024):
                if chunk:
                    f.write(chunk)


# ----------------------------
# Step 1: 下载数据
# ----------------------------


def download_sources(data_dir: Path) -> None:
    data_dir.mkdir(parents=True, exist_ok=True)

    kajweb_dir = data_dir / "kajweb"
    xiaolai_dir = data_dir / "xiaolai"
    ecdict_path = data_dir / "ecdict.csv"
    awl_path = data_dir / "awl.txt"

    log("[Step 1] 准备数据源目录...")

    if not kajweb_dir.exists():
        log("[Step 1] Cloning kajweb/dict...")
        run(["git", "clone", "--depth", "1", "https://github.com/kajweb/dict", str(kajweb_dir)])
    else:
        log("[Step 1] kajweb 已存在，跳过 clone")

    if not xiaolai_dir.exists():
        log("[Step 1] Cloning xiaolai/toefl-ibt-vocabulary-in-context...")
        run([
            "git",
            "clone",
            "--depth",
            "1",
            "https://github.com/xiaolai/toefl-ibt-vocabulary-in-context",
            str(xiaolai_dir),
        ])
    else:
        log("[Step 1] xiaolai 已存在，跳过 clone")

    if not ecdict_path.exists():
        log("[Step 1] 下载 ECDICT CSV...")
        ecdict_urls = [
            "https://raw.githubusercontent.com/skywind3000/ECDICT/master/ecdict.csv",
            "https://raw.githubusercontent.com/skywind3000/ECDICT/master/stardict.csv",
        ]
        ok = False
        for url in ecdict_urls:
            try:
                log(f"[Step 1] 尝试: {url}")
                request_download(url, ecdict_path)
                ok = True
                break
            except Exception as exc:  # noqa: BLE001
                log(f"[Step 1] 下载失败: {exc}")
        if not ok:
            raise RuntimeError("无法下载 ECDICT，请手动放置 data/ecdict.csv")
    else:
        log("[Step 1] ecdict.csv 已存在，跳过下载")

    if not awl_path.exists():
        log("[Step 1] 下载 AWL 列表...")
        # 使用 machine_readable_wordlists 的 AWL.json（master 分支）
        awl_json_url = "https://raw.githubusercontent.com/lpmi-13/machine_readable_wordlists/master/Academic/AWL/AWL.json"
        tmp_awl_json = data_dir / "_awl_tmp.json"
        request_download(awl_json_url, tmp_awl_json)
        with open(tmp_awl_json, "r", encoding="utf-8") as f:
            awl_obj = json.load(f)

        awl_words: List[str] = []
        if isinstance(awl_obj, dict):
            for _, sublist in awl_obj.items():
                if isinstance(sublist, dict):
                    awl_words.extend([normalize_word(k) for k in sublist.keys()])

        awl_words = sorted({w for w in awl_words if WORD_RE.match(w)})
        if not awl_words:
            raise RuntimeError("AWL 下载成功但未解析出词条，请手动提供 data/awl.txt")

        ensure_parent(awl_path)
        awl_path.write_text("\n".join(awl_words) + "\n", encoding="utf-8")
        tmp_awl_json.unlink(missing_ok=True)
        log(f"[Step 1] AWL 词条写入: {len(awl_words)}")
    else:
        log("[Step 1] awl.txt 已存在，跳过下载")


# ----------------------------
# Step 2: 加载与标准化
# ----------------------------


def iter_kaj_json_objects(json_path: Path) -> Iterable[Dict[str, Any]]:
    # kajweb 的 JSON 常见格式为 JSON Lines
    with open(json_path, "r", encoding="utf-8", errors="ignore") as f:
        head = f.read(1)
        f.seek(0)
        if head == "[":
            obj = json.load(f)
            if isinstance(obj, list):
                for item in obj:
                    if isinstance(item, dict):
                        yield item
        else:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(obj, dict):
                    yield obj


def parse_kaj_entry(obj: Dict[str, Any]) -> Optional[Tuple[str, KajWord]]:
    word = normalize_word(str(obj.get("headWord") or ""))
    if not WORD_RE.match(word):
        return None

    content = (
        obj.get("content", {})
        .get("word", {})
        .get("content", {})
    )

    trans = content.get("trans", [])
    meanings: List[str] = []
    pos = ""

    if isinstance(trans, list):
        for item in trans:
            if not isinstance(item, dict):
                continue
            tran_cn = clean_text(str(item.get("tranCn") or ""))
            tran_cn = re.sub(r"\[[^\]]*\]", "", tran_cn)
            tran_cn = clean_text(tran_cn)
            if tran_cn:
                meanings.append(tran_cn)
            if not pos:
                pos = clean_text(str(item.get("pos") or ""))

    if not meanings:
        synos = content.get("syno", {}).get("synos", [])
        if isinstance(synos, list) and synos:
            first = synos[0] if isinstance(synos[0], dict) else {}
            tran = clean_text(str(first.get("tran") or ""))
            if tran:
                meanings.append(tran)
            if not pos:
                pos = clean_text(str(first.get("pos") or ""))

    meaning = "；".join(dict.fromkeys(m for m in meanings if m))
    meaning = clean_text(meaning)
    if len(meaning) > 80:
        meaning = meaning[:80].rstrip("；;，, ")

    return word, KajWord(meaning=meaning, pos=pos)


def merge_kaj_word(old: KajWord, new: KajWord) -> KajWord:
    meaning = old.meaning if len(old.meaning) >= len(new.meaning) else new.meaning
    pos = old.pos or new.pos
    return KajWord(meaning=meaning, pos=pos)


def load_kajweb_toefl(kajweb_dir: Path) -> Dict[str, KajWord]:
    book_dir = kajweb_dir / "book"
    if not book_dir.exists():
        raise FileNotFoundError(f"未找到 kajweb 目录: {book_dir}")

    candidates = sorted(
        p for p in book_dir.rglob("*")
        if p.is_file() and "toefl" in p.name.lower() and p.suffix.lower() in {".zip", ".json"}
    )

    if not candidates:
        raise FileNotFoundError("未找到 kajweb TOEFL 文件")

    kaj_map: Dict[str, KajWord] = {}
    total_objects = 0

    for path in candidates:
        if path.suffix.lower() == ".zip":
            with zipfile.ZipFile(path, "r") as zf:
                for name in zf.namelist():
                    if not name.lower().endswith(".json"):
                        continue
                    with zf.open(name, "r") as fp:
                        for raw in fp:
                            line = raw.decode("utf-8", errors="ignore").strip()
                            if not line:
                                continue
                            try:
                                obj = json.loads(line)
                            except json.JSONDecodeError:
                                continue
                            total_objects += 1
                            parsed = parse_kaj_entry(obj)
                            if not parsed:
                                continue
                            w, info = parsed
                            if w in kaj_map:
                                kaj_map[w] = merge_kaj_word(kaj_map[w], info)
                            else:
                                kaj_map[w] = info
        else:
            for obj in iter_kaj_json_objects(path):
                total_objects += 1
                parsed = parse_kaj_entry(obj)
                if not parsed:
                    continue
                w, info = parsed
                if w in kaj_map:
                    kaj_map[w] = merge_kaj_word(kaj_map[w], info)
                else:
                    kaj_map[w] = info

    log(f"[Step 2] Loading kajweb TOEFL... {len(kaj_map):,} unique words from {total_objects:,} records")
    return kaj_map


def normalize_phonetic(phonetic: str) -> str:
    phonetic = clean_text(phonetic)
    if not phonetic:
        return ""
    if phonetic.startswith("/") and phonetic.endswith("/"):
        return phonetic
    return f"/{phonetic}/"


def normalize_pos(pos: str) -> str:
    pos = clean_text(pos)
    if not pos:
        return ""

    # 常见：n, v, adj, adv ...
    token = re.split(r"[\s/;,，]+", pos)[0].strip(".")
    if not token:
        return ""
    return f"{token}."


def parse_ecdict_tags(tag_text: str) -> Set[str]:
    tag_text = clean_text(tag_text).lower()
    if not tag_text:
        return set()
    return {t for t in re.split(r"[\s,;/|]+", tag_text) if t}


def parse_coca_rank(value: Any) -> Optional[int]:
    if value is None:
        return None
    s = str(value).strip()
    if not s:
        return None
    try:
        n = int(float(s))
    except ValueError:
        return None
    return n if n > 0 else None


def clean_ecdict_translation(text: str) -> str:
    text = clean_text(text)
    text = re.sub(r"\[[^\]]*\]", "", text)
    text = clean_text(text)
    if not text:
        return ""
    # 截断，避免过长
    parts = re.split(r"[；;]", text)
    parts = [clean_text(p) for p in parts if clean_text(p)]
    if not parts:
        return ""
    return "；".join(parts[:3])


def load_ecdict(ecdict_path: Path) -> Dict[str, ECDictWord]:
    if not ecdict_path.exists():
        raise FileNotFoundError(f"未找到 ECDICT 文件: {ecdict_path}")

    usecols = ["word", "phonetic", "translation", "pos", "tag", "frq"]
    df = pd.read_csv(
        ecdict_path,
        usecols=lambda c: c in set(usecols),
        dtype=str,
        keep_default_na=False,
        na_filter=False,
        quoting=csv.QUOTE_MINIMAL,
        low_memory=False,
    )

    if "word" not in df.columns:
        raise RuntimeError("ECDICT 文件缺少 word 列")

    ecdict_map: Dict[str, ECDictWord] = {}

    for row in df.to_dict(orient="records"):
        word = normalize_word(str(row.get("word", "")))
        if not WORD_RE.match(word):
            continue

        info = ECDictWord(
            phonetic=normalize_phonetic(str(row.get("phonetic", ""))),
            pos=normalize_pos(str(row.get("pos", ""))),
            coca_rank=parse_coca_rank(row.get("frq")),
            tags=parse_ecdict_tags(str(row.get("tag", ""))),
            meaning=clean_ecdict_translation(str(row.get("translation", ""))),
        )

        old = ecdict_map.get(word)
        if old is None:
            ecdict_map[word] = info
            continue

        # 合并规则：保留更完整/更高质量字段
        if not old.phonetic and info.phonetic:
            old.phonetic = info.phonetic
        if not old.pos and info.pos:
            old.pos = info.pos
        if old.coca_rank is None and info.coca_rank is not None:
            old.coca_rank = info.coca_rank
        if not old.meaning and info.meaning:
            old.meaning = info.meaning
        old.tags |= info.tags

    log(f"[Step 2] Loading ECDICT... {len(ecdict_map):,} entries loaded")
    return ecdict_map


SUBJECT_KEYWORDS = {
    "astronomy": "天文",
    "geo": "地质",
    "geology": "地质",
    "ecology": "生态",
    "environment": "环境",
    "biology": "生物",
    "chemistry": "化学",
    "physics": "物理",
    "medicine": "医学",
    "history": "历史",
    "anthropology": "人类学",
    "archaeology": "考古",
    "sociology": "社会学",
    "psychology": "心理学",
    "economics": "经济",
    "politics": "政治",
    "law": "法律",
    "education": "教育",
    "linguistics": "语言学",
    "ocean": "海洋",
    "geography": "地理",
    "agriculture": "农业",
    "humanities": "人文",
}


def infer_subject_from_path(path: Path) -> str:
    key = f"{path.parent.name} {path.stem}".lower()
    for k, v in SUBJECT_KEYWORDS.items():
        if k in key:
            return v
    return "学术专题"


def load_xiaolai_subject_tags(xiaolai_dir: Path) -> Dict[str, Set[str]]:
    if not xiaolai_dir.exists():
        log("[Step 2] xiaolai 数据缺失，学科标签为空")
        return {}

    files = [
        p
        for p in xiaolai_dir.rglob("*")
        if p.is_file() and p.suffix.lower() in {".txt", ".md", ".csv", ".tsv", ".json"}
    ]

    # 仓库当前可能只有 README（官方仓库通常是网盘链接）
    useful_files = [p for p in files if p.name.lower() != "readme.md"]
    if not useful_files:
        log("[Step 2] xiaolai 仓库未发现可解析词表文件，学科标签为空")
        return {}

    tags_map: Dict[str, Set[str]] = defaultdict(set)

    for path in useful_files:
        subject = infer_subject_from_path(path)
        try:
            content = path.read_text(encoding="utf-8", errors="ignore")
        except Exception:  # noqa: BLE001
            continue

        for line in content.splitlines():
            line = line.strip()
            if not line or line.startswith("#") or line.startswith(">"):
                continue
            m = START_WORD_RE.match(line)
            if not m:
                continue
            word = normalize_word(m.group(1))
            if WORD_RE.match(word):
                tags_map[word].add(subject)

    log(f"[Step 2] Loading xiaolai... {len(tags_map):,} words with subject tags")
    return dict(tags_map)


def load_awl_words(awl_path: Path) -> Set[str]:
    if not awl_path.exists():
        raise FileNotFoundError(f"未找到 AWL 文件: {awl_path}")

    words: Set[str] = set()
    for line in awl_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        for token in re.findall(r"[A-Za-z][A-Za-z'\-]{1,30}", line):
            word = normalize_word(token)
            if WORD_RE.match(word):
                words.add(word)

    log(f"[Step 2] Loading AWL... {len(words):,} words")
    return words


# ----------------------------
# Step 3/4: 分层构建
# ----------------------------


def rank_of(word: str, ecdict: Dict[str, ECDictWord]) -> Optional[int]:
    info = ecdict.get(word)
    return info.coca_rank if info else None


def sort_words_by_rank(words: Iterable[str], ecdict: Dict[str, ECDictWord]) -> List[str]:
    def key(w: str) -> Tuple[int, int, str]:
        rank = rank_of(w, ecdict)
        if rank is None:
            return (1, 10**9, w)
        return (0, rank, w)

    return sorted(set(words), key=key)


def build_layers(
    kaj_map: Dict[str, KajWord],
    ecdict_map: Dict[str, ECDictWord],
    xiaolai_tags: Dict[str, Set[str]],
    awl_words: Set[str],
    core_coca_max: int,
    full_coca_max: int,
) -> Dict[str, Set[str]]:
    kaj_words = set(kaj_map.keys())

    layer_a: Set[str] = set()
    for w in kaj_words:
        r = rank_of(w, ecdict_map)
        if r is not None and r <= core_coca_max:
            layer_a.add(w)

    layer_b = kaj_words & awl_words
    core = layer_a | layer_b

    layer_c: Set[str] = set()
    for w in kaj_words:
        r = rank_of(w, ecdict_map)
        if r is None:
            continue
        if core_coca_max < r <= full_coca_max and w not in core:
            layer_c.add(w)

    layer_d = set(xiaolai_tags.keys()) - core - layer_c

    layer_e: Set[str] = set()
    occupied = core | layer_c | layer_d
    for w, info in ecdict_map.items():
        if w in occupied:
            continue
        if "toefl" in info.tags:
            layer_e.add(w)

    full = core | layer_c | layer_d | layer_e

    return {
        "layer_a": layer_a,
        "layer_b": layer_b,
        "core": core,
        "layer_c": layer_c,
        "layer_d": layer_d,
        "layer_e": layer_e,
        "full": full,
    }


# ----------------------------
# Step 5/6: 字段补全、排序、输出
# ----------------------------


def choose_meaning(word: str, kaj_map: Dict[str, KajWord], ecdict_map: Dict[str, ECDictWord]) -> str:
    kaj = kaj_map.get(word)
    if kaj and kaj.meaning:
        return kaj.meaning
    ecd = ecdict_map.get(word)
    if ecd and ecd.meaning:
        return ecd.meaning
    return ""


def choose_pos(word: str, kaj_map: Dict[str, KajWord], ecdict_map: Dict[str, ECDictWord]) -> str:
    ecd = ecdict_map.get(word)
    if ecd and ecd.pos:
        return ecd.pos
    kaj = kaj_map.get(word)
    if kaj and kaj.pos:
        return normalize_pos(kaj.pos)
    return ""


def build_tags(
    word: str,
    awl_words: Set[str],
    xiaolai_tags: Dict[str, Set[str]],
    ecdict_map: Dict[str, ECDictWord],
) -> List[str]:
    tags: List[str] = []

    if word in awl_words:
        tags.append("AWL")
        tags.append("学术通用")

    for t in sorted(xiaolai_tags.get(word, set())):
        if t not in tags:
            tags.append(t)

    ecd = ecdict_map.get(word)
    if ecd:
        if "cet4" in ecd.tags:
            tags.append("CET4")
        if "cet6" in ecd.tags:
            tags.append("CET6")

    # 去重保序
    dedup: List[str] = []
    seen: Set[str] = set()
    for t in tags:
        if t not in seen:
            dedup.append(t)
            seen.add(t)
    return dedup


def make_entries(
    words_ordered: List[str],
    tier_by_word: Dict[str, str],
    kaj_map: Dict[str, KajWord],
    ecdict_map: Dict[str, ECDictWord],
    awl_words: Set[str],
    xiaolai_tags: Dict[str, Set[str]],
) -> List[Dict[str, Any]]:
    width = max(4, len(str(len(words_ordered))))
    entries: List[Dict[str, Any]] = []

    for idx, w in enumerate(words_ordered, start=1):
        ecd = ecdict_map.get(w)
        entries.append(
            {
                "id": f"toefl_{idx:0{width}d}",
                "word": w,
                "phonetic": ecd.phonetic if ecd else "",
                "meaning": choose_meaning(w, kaj_map, ecdict_map),
                "pos": choose_pos(w, kaj_map, ecdict_map),
                "coca_rank": ecd.coca_rank if ecd else None,
                "tier": tier_by_word[w],
                "tags": build_tags(w, awl_words, xiaolai_tags, ecdict_map),
                "example": "",
            }
        )

    return entries


def write_json(path: Path, data: List[Dict[str, Any]]) -> None:
    ensure_parent(path)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def calc_ratio(numerator: int, denominator: int) -> float:
    if denominator <= 0:
        return 0.0
    return numerator / denominator


def write_stats(
    stats_path: Path,
    layers: Dict[str, Set[str]],
    core_entries: List[Dict[str, Any]],
    full_entries: List[Dict[str, Any]],
    xiaolai_tags: Dict[str, Set[str]],
    awl_words: Set[str],
) -> None:
    core_count = len(core_entries)
    full_count = len(full_entries)

    core_with_phonetic = sum(1 for e in core_entries if e.get("phonetic"))
    core_with_rank = sum(1 for e in core_entries if e.get("coca_rank") is not None)

    full_with_phonetic = sum(1 for e in full_entries if e.get("phonetic"))
    full_with_rank = sum(1 for e in full_entries if e.get("coca_rank") is not None)

    awl_overlap_core = len(layers["core"] & awl_words)
    awl_overlap_full = len(layers["full"] & awl_words)

    subject_counter: Counter[str] = Counter()
    for word in layers["full"]:
        for tag in xiaolai_tags.get(word, set()):
            subject_counter[tag] += 1

    lines = [
        "[Stats] Core",
        f"core_total={core_count}",
        f"layer_a={len(layers['layer_a'])}",
        f"layer_b={len(layers['layer_b'])}",
        "",
        "[Stats] Full",
        f"full_total={full_count}",
        f"layer_c={len(layers['layer_c'])}",
        f"layer_d={len(layers['layer_d'])}",
        f"layer_e={len(layers['layer_e'])}",
        "",
        "[Coverage] Core",
        f"phonetic_coverage={core_with_phonetic}/{core_count} ({calc_ratio(core_with_phonetic, core_count):.2%})",
        f"coca_coverage={core_with_rank}/{core_count} ({calc_ratio(core_with_rank, core_count):.2%})",
        f"awl_overlap={awl_overlap_core}",
        "",
        "[Coverage] Full",
        f"phonetic_coverage={full_with_phonetic}/{full_count} ({calc_ratio(full_with_phonetic, full_count):.2%})",
        f"coca_coverage={full_with_rank}/{full_count} ({calc_ratio(full_with_rank, full_count):.2%})",
        f"awl_overlap={awl_overlap_full}",
        "",
        "[Subject Distribution]",
    ]

    if subject_counter:
        for k, v in subject_counter.most_common():
            lines.append(f"{k}={v}")
    else:
        lines.append("(empty)")

    ensure_parent(stats_path)
    stats_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


# ----------------------------
# 主流程
# ----------------------------


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="构建 WordFlow 新托福词库 JSON")
    parser.add_argument("--download", action="store_true", help="执行数据下载步骤")
    parser.add_argument("--core-coca-max", type=int, default=5000, help="核心版 COCA 上限")
    parser.add_argument("--full-coca-max", type=int, default=15000, help="完整版 COCA 上限")
    parser.add_argument("--output-dir", default="./output", help="输出目录")
    return parser.parse_args()


def resolve_data_paths(root: Path) -> Dict[str, Path]:
    return {
        "data_dir": root / "data",
        "kajweb_dir": root / "data" / "kajweb",
        "ecdict_csv": root / "data" / "ecdict.csv",
        "xiaolai_dir": root / "data" / "xiaolai",
        "awl_txt": root / "data" / "awl.txt",
    }


def assert_sources_exist(paths: Dict[str, Path]) -> None:
    missing = []
    if not paths["kajweb_dir"].exists():
        missing.append(str(paths["kajweb_dir"]))
    if not paths["ecdict_csv"].exists():
        missing.append(str(paths["ecdict_csv"]))
    if not paths["xiaolai_dir"].exists():
        missing.append(str(paths["xiaolai_dir"]))
    if not paths["awl_txt"].exists():
        missing.append(str(paths["awl_txt"]))

    if missing:
        joined = "\n  - " + "\n  - ".join(missing)
        raise FileNotFoundError(
            "缺少数据源文件，请先运行 --download 或手动准备:\n" + joined
        )


def main() -> int:
    args = parse_args()
    project_root = Path.cwd()

    if args.core_coca_max <= 0 or args.full_coca_max <= 0:
        raise ValueError("COCA 阈值必须为正整数")
    if args.full_coca_max < args.core_coca_max:
        raise ValueError("full-coca-max 必须 >= core-coca-max")

    paths = resolve_data_paths(project_root)

    if args.download:
        download_sources(paths["data_dir"])

    assert_sources_exist(paths)

    log("[Step 2] 开始加载数据...")
    kaj_map = load_kajweb_toefl(paths["kajweb_dir"])
    ecdict_map = load_ecdict(paths["ecdict_csv"])
    xiaolai_tags = load_xiaolai_subject_tags(paths["xiaolai_dir"])
    awl_words = load_awl_words(paths["awl_txt"])

    log("[Step 3] 构建核心层...")
    layers = build_layers(
        kaj_map,
        ecdict_map,
        xiaolai_tags,
        awl_words,
        core_coca_max=args.core_coca_max,
        full_coca_max=args.full_coca_max,
    )

    log("[Step 4] 构建完整版层...")
    tier_full: Dict[str, str] = {}
    for w in layers["core"]:
        tier_full[w] = "core"
    for w in layers["layer_c"]:
        tier_full.setdefault(w, "extended")
    for w in layers["layer_d"]:
        tier_full.setdefault(w, "subject")
    for w in layers["layer_e"]:
        tier_full.setdefault(w, "supplementary")

    tier_core = {w: "core" for w in layers["core"]}

    core_order = sort_words_by_rank(layers["core"], ecdict_map)

    full_order: List[str] = []
    full_order.extend(core_order)
    full_order.extend(sort_words_by_rank(layers["layer_c"], ecdict_map))
    full_order.extend(sort_words_by_rank(layers["layer_d"], ecdict_map))
    full_order.extend(sort_words_by_rank(layers["layer_e"], ecdict_map))

    # 去重保序
    seen: Set[str] = set()
    full_order = [w for w in full_order if not (w in seen or seen.add(w))]

    log("[Step 5] 补全字段并生成词条...")
    core_entries = make_entries(core_order, tier_core, kaj_map, ecdict_map, awl_words, xiaolai_tags)
    full_entries = make_entries(full_order, tier_full, kaj_map, ecdict_map, awl_words, xiaolai_tags)

    output_dir = Path(args.output_dir)
    core_path = output_dir / "core_toefl.json"
    full_path = output_dir / "full_toefl.json"
    stats_path = output_dir / "stats.txt"

    log("[Step 6] 写出 JSON 与统计...")
    write_json(core_path, core_entries)
    write_json(full_path, full_entries)
    write_stats(stats_path, layers, core_entries, full_entries, xiaolai_tags, awl_words)

    log(f"[Done] core={len(core_entries):,}, full={len(full_entries):,}")
    log(f"[Done] 输出目录: {output_dir.resolve()}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\n中断", file=sys.stderr)
        raise SystemExit(130)
