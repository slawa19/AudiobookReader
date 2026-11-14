#!/usr/bin/env python3
"""Готовит подставные книги прототипа: тексты общественного достояния из Викитеки → JSON модели книги (А§3).

Только для прототипа интерфейса. Это НЕ разборщик приложения: он знает разметку Викитеки и пару конкретных
страниц, чего настоящему разбору делать нельзя. Запускается вручную, результат лежит в assets/demo/ и
коммитится; сеть нужна только при запуске этого скрипта.

    python3 scripts/prototype-texts.py

Источники (лицензия текста — PD-old-70):
  А. С. Пушкин, «Капитанская дочка» (1836), главы I–III — ru.wikisource.org, редакция 1960 (СО);
  А. П. Чехов, «Ионыч» (1898) и «Дама с собачкой» (1899) — ru.wikisource.org.
Сноски: у Пушкина — три коротких примечания со страниц Викитеки как есть; у Чехова — только авторская
(«прим. автора») и одна о Верне, написанная заново своими словами; остальные примечания редакторов Викитеки
отброшены. Картинка «Степь перед бураном» нарисована этим скриптом — в книге её нет.
"""
import html
import json
import os
import re
import struct
import sys
import urllib.parse
import urllib.request
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "demo")
PARSER_VERSION = 1


def fetch(title):
    params = {"action": "query", "prop": "revisions", "titles": title, "rvprop": "ids|content",
              "rvslots": "main", "format": "json", "formatversion": "2"}
    url = "https://ru.wikisource.org/w/api.php?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": "audiobook-reader-prototype/1.0"})
    data = json.load(urllib.request.urlopen(req, timeout=60))
    page = data["query"]["pages"][0]
    rev = page["revisions"][0]
    return rev["slots"]["main"]["content"], rev["revid"]


# --- разбор шаблонов с учётом вложенности -------------------------------------------------------------

def split_templates(text):
    """Делит текст на куски: ('text', s) и ('tpl', inner) для {{…}} верхнего уровня."""
    out, i, depth, start, buf = [], 0, 0, 0, []
    while i < len(text):
        if text.startswith("{{", i):
            if depth == 0:
                out.append(("text", "".join(buf)))
                buf = []
                start = i + 2
            depth += 1
            i += 2
            continue
        if text.startswith("}}", i) and depth > 0:
            depth -= 1
            i += 2
            if depth == 0:
                out.append(("tpl", text[start:i - 2]))
            continue
        if depth == 0:
            buf.append(text[i])
        i += 1
    out.append(("text", "".join(buf)))
    return out


def split_params(inner):
    """Делит тело шаблона по | верхнего уровня (не внутри {{ }}, [[ ]], <poem>)."""
    parts, depth, buf, i = [], 0, [], 0
    while i < len(inner):
        two = inner[i:i + 2]
        if two in ("{{", "[["):
            depth += 1
            buf.append(two)
            i += 2
            continue
        if two in ("}}", "]]"):
            depth -= 1
            buf.append(two)
            i += 2
            continue
        if inner[i] == "|" and depth == 0:
            parts.append("".join(buf))
            buf = []
            i += 1
            continue
        buf.append(inner[i])
        i += 1
    parts.append("".join(buf))
    return parts


def positional(params):
    return [p for p in params[1:] if not re.match(r"^\s*[\w-]+\s*=", p)]


class Builder:
    def __init__(self, book_id, title, author):
        self.book = {"id": book_id, "title": title, "author": author, "language": "ru",
                     "parserVersion": PARSER_VERSION, "chapters": [], "blocks": [], "notes": []}
        self.note_no = 0
        self.only_author_notes = False

    # inline: '' '' ''' [[..]] <ref> &nbsp; <br>
    def inline(self, raw, keep_ref=True, note_override=None):
        text, spans = [], []
        italic_start, bold_start = None, None
        pos = 0

        def cur():
            return sum(len(t) for t in text)

        raw = raw.replace("<br />", "\n").replace("<br/>", "\n").replace("<br>", "\n")
        # шаблоны внутри строки
        pieces = []
        for kind, s in split_templates(raw):
            if kind == "text":
                pieces.append(s)
            else:
                params = split_params(s)
                name = params[0].strip().lower()
                pos_ = positional(params)
                if name in ("lang",) and len(pos_) >= 2:
                    pieces.append(pos_[1])
                elif name.startswith("lang-") and pos_:
                    pieces.append(pos_[0])
                elif name == "примечание вт":
                    body = pos_[0] if pos_ else ""
                    if note_override and note_override[0] in body:
                        pieces.append("<ref keep>" + note_override[1] + "</ref>")
                elif name in ("right", "center") and pos_:
                    pieces.append(pos_[-1])
                elif name == "ext" and pos_:
                    pieces.append(pos_[-1])
                # прочие шаблоны в строке отбрасываются
        raw = "".join(pieces)

        i = 0
        while i < len(raw):
            if raw.startswith("<ref", i):
                end_open = raw.index(">", i)
                close = raw.index("</ref>", end_open)
                body = raw[end_open + 1:close]
                forced = "keep" in raw[i:end_open + 1]
                i = close + len("</ref>")
                if not keep_ref or (self.only_author_notes and "прим. автора" not in body and not forced):
                    continue
                self.note_no += 1
                note_id = f"n{self.note_no}"
                ntext, nspans = self.inline(body, keep_ref=False)
                self.book["notes"].append({"id": note_id, "blocks": [
                    {"kind": "paragraph", "text": ntext.strip(), "spans": nspans}]})
                marker = str(self.note_no)
                start = cur()
                text.append(marker)
                spans.append({"start": start, "end": start + len(marker), "style": "noteRef", "noteId": note_id})
                continue
            if raw.startswith("'''", i):
                if bold_start is None:
                    bold_start = cur()
                else:
                    if cur() > bold_start:
                        spans.append({"start": bold_start, "end": cur(), "style": "bold"})
                    bold_start = None
                i += 3
                continue
            if raw.startswith("''", i):
                if italic_start is None:
                    italic_start = cur()
                else:
                    if cur() > italic_start:
                        spans.append({"start": italic_start, "end": cur(), "style": "italic"})
                    italic_start = None
                i += 2
                continue
            if raw.startswith("[[", i):
                close = raw.index("]]", i)
                inner = raw[i + 2:close]
                text.append(html.unescape(inner.split("|")[-1]))
                i = close + 2
                continue
            if raw[i] == "&":
                m = re.match(r"&[#\w]+;", raw[i:])
                if m:
                    text.append(html.unescape(m.group(0)))
                    i += len(m.group(0))
                    continue
            text.append(raw[i])
            i += 1
        if italic_start is not None and cur() > italic_start:
            spans.append({"start": italic_start, "end": cur(), "style": "italic"})
        s = "".join(text)
        # лишние пробелы по краям — с поправкой диапазонов
        lead = len(s) - len(s.lstrip(" "))
        s2 = s.strip(" ")
        spans = [{**sp, "start": max(0, sp["start"] - lead), "end": min(len(s2), sp["end"] - lead)}
                 for sp in spans if sp["end"] - lead > 0]
        return s2, spans

    def add_block(self, kind, raw, image_id=None, note_override=None):
        text, spans = self.inline(raw, note_override=note_override)
        if not text and kind != "image":
            return
        block = {"kind": kind, "text": text, "spans": spans}
        if image_id:
            block["imageId"] = image_id
        self.book["blocks"].append(block)

    def chapter(self, title, level):
        self.book["chapters"].append({"title": title, "level": level, "firstBlock": len(self.book["blocks"])})

    def add_poem(self, body, kind="verse"):
        body = re.sub(r"</?poem>", "", body).strip("\n")
        for stanza in re.split(r"\n\s*\n", body):
            lines = [re.sub(r"^:+", "", ln).rstrip() for ln in stanza.split("\n") if ln.strip()]
            if lines:
                self.add_block(kind, "\n".join(lines))

    def finish(self):
        blocks = self.book["blocks"]
        for i, b in enumerate(blocks):
            b["index"] = i
        chapters = self.book["chapters"]
        for i, ch in enumerate(chapters):
            nxt = chapters[i + 1]["firstBlock"] if i + 1 < len(chapters) else len(blocks)
            ch["blockCount"] = nxt - ch["firstBlock"]
        self.book["totalChars"] = sum(len(b["text"]) for b in blocks)
        return self.book


def body_of(wiki):
    """Текст произведения без шапки {{Отексте}}, примечаний и категорий."""
    parts = split_templates(wiki)
    out = []
    for kind, s in parts:
        if kind == "tpl" and s.strip().lower().startswith("отексте"):
            continue
        out.append(s if kind == "text" else "{{" + s + "}}")
    text = "".join(out)
    text = re.split(r"\n==\s*Примечания\s*==", text)[0]
    text = re.sub(r"__\w+__", "", text)
    text = re.sub(r"</?div[^>]*>", "", text)
    text = re.sub(r"\[\[(Категория|[a-z]{2,3}):[^\]]*\]\]", "", text)
    return text


def convert_chapterized(b, wiki, level, note_override=None, image_after=None):
    """Главы по == I ==; абзацы по пустым строкам; <poem> — стихи."""
    text = body_of(wiki)
    chunks = re.split(r"\n(?===\s*[IVX]+\s*==)", "\n" + text)
    for chunk in chunks:
        m = re.match(r"\s*==\s*([IVX]+)\s*==\s*\n", chunk)
        if not m:
            continue
        roman = m.group(1)
        b.chapter(roman, level)
        b.add_block("heading", roman)
        rest = chunk[m.end():]
        for para in re.split(r"\n\s*\n", rest):
            para = para.strip()
            if not para:
                continue
            if para.startswith("<poem>"):
                b.add_poem(para)
                continue
            if "<poem>" in para:
                before, poem = para.split("<poem>", 1)
                if before.strip():
                    b.add_block("paragraph", before.strip().replace("\n", " "), note_override=note_override)
                poem, after = poem.split("</poem>", 1)
                b.add_poem(poem)
                if after.strip():
                    b.add_block("paragraph", after.strip().replace("\n", " "), note_override=note_override)
                continue
            b.add_block("paragraph", para.replace("\n", " "), note_override=note_override)


def convert_pushkin_chapter(b, wiki, image=None):
    text = body_of(wiki)
    paragraphs_seen = 0
    for kind, s in split_templates(text):
        if kind == "tpl":
            params = split_params(s)
            name = params[0].strip().lower()
            pos = positional(params)
            if name == "h":
                label, sub = pos[-2].strip(), pos[-1].strip()
                b.chapter(f"{label}. {sub}", 1)
                b.add_block("heading", f"{label}\n{sub}")
            elif name == "эпиграф2":
                body = pos[0]
                if "<poem>" in body:
                    b.add_poem(body)
                else:
                    b.add_block("cite", body.strip())
                if len(pos) > 1 and pos[1].strip():
                    b.add_block("cite", pos[1].strip())
            elif name in ("right", "center") and pos:
                b.add_block("paragraph", pos[-1].strip())
            continue
        for para in re.split(r"\n\s*\n", s):
            para = para.strip()
            if not para or para.startswith("=="):
                continue
            b.add_block("paragraph", para.replace("\n", " "))
            paragraphs_seen += 1
            if image and paragraphs_seen == image[0]:
                b.book["blocks"].append({"kind": "image", "text": image[2], "spans": [], "imageId": image[1]})


# --- картинка-заглушка: нарисована здесь, а не взята из книги ------------------------------------------

def write_png(path, w, h, pixel):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw.extend(pixel(x, y))
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


def steppe_picture(path):
    """Зимняя степь перед бураном: небо, холмы, снег, кибитка. Детерминированно."""
    import math
    import random
    w, h = 960, 600
    rnd = random.Random(7)
    flakes = {(rnd.randrange(w), rnd.randrange(int(h * 0.85))) for _ in range(900)}
    big = set()
    for (fx, fy) in list(flakes)[:250]:
        big.update({(fx + 1, fy), (fx, fy + 1), (fx + 1, fy + 1)})

    def mix(a, b, t):
        return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

    sky_top, sky_bottom = (92, 101, 112), (196, 199, 200)
    hill_far, hill_near = (150, 156, 160), (214, 214, 210)
    snow_a, snow_b = (232, 231, 226), (246, 245, 241)

    def far(x):
        return h * 0.58 - 26 * math.sin(x / 140.0) - 14 * math.sin(x / 53.0 + 1.3)

    def near(x):
        return h * 0.70 - 18 * math.sin(x / 210.0 + 2.0) - 6 * math.sin(x / 37.0)

    def kibitka(x, y):
        cx, base = 610, near(610) + 4
        if cx - 46 <= x <= cx + 46 and base - 22 <= y <= base:
            return True
        if (x - cx) ** 2 / 46.0 ** 2 + (y - (base - 22)) ** 2 / 26.0 ** 2 <= 1 and y <= base - 22:
            return True
        for wx in (cx - 30, cx + 30):
            if (x - wx) ** 2 + (y - base - 4) ** 2 <= 49:
                return True
        if cx + 46 <= x <= cx + 120 and base - 3 <= y <= base - 1:
            return True
        return False

    def pixel(x, y):
        if (x, y) in flakes or (x, y) in big:
            return (250, 250, 250)
        if kibitka(x, y):
            return (58, 52, 48)
        if y < far(x):
            return mix(sky_top, sky_bottom, y / (h * 0.6))
        if y < near(x):
            return mix(hill_far, sky_bottom, (y - far(x)) / 60.0) if y - far(x) < 60 else hill_far
        return mix(hill_near, snow_b, min(1.0, (y - near(x)) / (h * 0.3)))

    write_png(path, w, h, pixel)


def cover(path, base, motif):
    """Обложка-заглушка 240×360: тёмный фон, светлый мотив. Без текста."""
    import math
    w, h = 240, 360
    light = tuple(min(255, int(c + (255 - c) * 0.55)) for c in base)
    mid = tuple(min(255, int(c + (255 - c) * 0.25)) for c in base)

    def pixel(x, y):
        t = y / h
        bg = tuple(int(c * (1.0 - 0.18 * t)) for c in base)
        if x < 10:
            return tuple(int(c * 0.8) for c in base)
        if motif == "sun" and (x - 150) ** 2 + (y - 120) ** 2 < 48 ** 2:
            return light
        if motif == "sun" and y > 250 + 12 * math.sin(x / 30.0):
            return mid
        if motif == "waves" and int((y + 10 * math.sin(x / 22.0)) / 18) % 2 == 0 and 170 < y < 330:
            return mid
        if motif == "arch" and 60 < x < 200 and 90 < y < 300 and ((x - 130) ** 2 / 70.0 ** 2 + (y - 160) ** 2 / 70.0 ** 2 < 1 or y > 160):
            return mid if not (95 < x < 165 and y > 150) else bg
        if motif == "stars" and ((x * 7 + y * 13) % 97 == 0 or (x * 11 + y * 5) % 131 == 0):
            return light
        if motif == "rule" and (40 < y < 46 or 314 < y < 320) and 30 < x < 210:
            return light
        return bg

    write_png(path, w, h, pixel)


def covers():
    d = os.path.join(OUT, "covers")
    os.makedirs(d, exist_ok=True)
    for name, base, motif in (("kapitanskaya", (122, 59, 46), "sun"), ("dama", (61, 90, 76), "waves"),
                              ("voyna", (64, 80, 107), "rule"), ("dushi", (107, 90, 58), "arch"),
                              ("geroy", (91, 63, 94), "stars")):
        cover(os.path.join(d, name + ".png"), base, motif)


def main():
    os.makedirs(os.path.join(OUT, "images"), exist_ok=True)
    covers()
    sources = []

    b = Builder("kapitanskaya", "Капитанская дочка", "Александр Пушкин")
    for i, roman in enumerate(["I", "II", "III"]):
        wiki, rev = fetch(f"Капитанская дочка (Пушкин)/1960 (СО)/Глава {roman}")
        sources.append(f"Капитанская дочка (Пушкин)/1960 (СО)/Глава {roman} @ {rev}")
        image = (5, "steppe", "Степь перед бураном") if roman == "II" else None
        convert_pushkin_chapter(b, wiki, image=image)
    book = b.finish()
    book["sources"] = sources
    json.dump(book, open(os.path.join(OUT, "kapitanskaya.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)

    sources = []
    b = Builder("dama", "Дама с собачкой. Рассказы", "Антон Чехов")
    b.only_author_notes = True
    wiki, rev = fetch("Ионыч (Чехов)")
    sources.append(f"Ионыч (Чехов) @ {rev}")
    b.chapter("Ионыч", 1)
    b.add_block("heading", "Ионыч")
    convert_chapterized(b, wiki, 2)
    wiki, rev = fetch("Дама с собачкой (Чехов)")
    sources.append(f"Дама с собачкой (Чехов) @ {rev}")
    b.chapter("Дама с собачкой", 1)
    b.add_block("heading", "Дама с собачкой")
    convert_chapterized(b, wiki, 2, note_override=(
        "Верне", "Кондитерская на ялтинской набережной; её первым владельцем был француз Эдмунд Верне."))
    book = b.finish()
    book["sources"] = sources
    json.dump(book, open(os.path.join(OUT, "dama.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)

    steppe_picture(os.path.join(OUT, "images", "steppe.png"))
    for name in ("kapitanskaya.json", "dama.json"):
        d = json.load(open(os.path.join(OUT, name), encoding="utf-8"))
        kinds = {}
        for blk in d["blocks"]:
            kinds[blk["kind"]] = kinds.get(blk["kind"], 0) + 1
        print(name, "chars", d["totalChars"], "blocks", len(d["blocks"]), kinds, "notes", len(d["notes"]),
              "chapters", [(c["title"], c["level"], c["blockCount"]) for c in d["chapters"]])
    return 0


if __name__ == "__main__":
    sys.exit(main())
