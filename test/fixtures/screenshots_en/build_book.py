#!/usr/bin/env python3
"""Builds alice.json (book-model JSON, A§3) from the Project Gutenberg plain text of "Alice's Adventures in Wonderland".

Test fixture for the README screenshots (test/readme_screenshots_test.dart). Not the app's parser: it knows the
layout of this one Gutenberg file (chapters "CHAPTER I." + title line, _italic_ markers, four-space indented verse).

How to regenerate (the network is needed only for the download):

    curl -sSL -o /tmp/pg11.txt https://gutenberg.pglaf.org/1/11/11-0.txt
    python3 -I test/fixtures/screenshots_en/build_book.py /tmp/pg11.txt test/fixtures/screenshots_en/alice.json

The Project Gutenberg start/end markers and the licence text are not copied: only chapters I-VI of the work are kept
(see SOURCES.txt next to this file).
"""
import json
import re
import sys

CHAPTERS = 6  # the opening chapters are enough for the reading pages and a believable table of contents
ROMAN = re.compile(r"^CHAPTER ([IVXL]+)\.$")


def inline(raw):
    """Text with _italic_ markers -> (plain text, italic spans)."""
    text, spans, pos = [], [], 0
    for m in re.finditer(r"_(.+?)_", raw, re.S):
        text.append(raw[pos:m.start()])
        start = sum(len(t) for t in text)
        text.append(m.group(1))
        spans.append({"start": start, "end": start + len(m.group(1)), "style": "italic"})
        pos = m.end()
    text.append(raw[pos:])
    return "".join(text), spans


def indent(line):
    return len(line) - len(line.lstrip(" "))


def main(src, dst):
    lines = open(src, encoding="utf-8").read().split("\n")
    # real chapter starts (the table of contents at the top has "CHAPTER I.     Title" on one line, so it is skipped)
    starts = [i for i, ln in enumerate(lines) if ROMAN.match(ln)]
    assert len(starts) >= CHAPTERS + 1
    blocks, chapters = [], []

    def add(kind, raw, flat=True):
        raw = " ".join(s.strip() for s in raw.split("\n")) if flat else "\n".join(s.strip() for s in raw.split("\n"))
        text, spans = inline(raw)
        blocks.append({"index": len(blocks), "kind": kind, "text": text, "spans": spans})

    for n in range(CHAPTERS):
        first, last = starts[n], starts[n + 1]
        label = ROMAN.match(lines[first]).group(1)
        title = lines[first + 1].strip()
        chapters.append({"title": f"Chapter {label}. {title}", "level": 1, "firstBlock": len(blocks)})
        add("heading", f"Chapter {label}\n{title}", flat=False)
        body = "\n".join(lines[first + 2:last])
        for group in re.split(r"\n\s*\n", body):
            rows = [r.rstrip() for r in group.split("\n") if r.strip()]
            if not rows:
                continue
            if all(re.fullmatch(r"[\s*]+", r) for r in rows):
                blocks.append({"index": len(blocks), "kind": "separator", "text": "", "spans": []})
                continue
            indents = [indent(r) for r in rows]
            if min(indents) >= 5:
                add("cite", "\n".join(rows))
            elif min(indents) == 4 or max(indents) >= 4:
                add("verse", "\n".join(rows), flat=False)
            else:
                add("paragraph", "\n".join(rows))

    for i, ch in enumerate(chapters):
        nxt = chapters[i + 1]["firstBlock"] if i + 1 < len(chapters) else len(blocks)
        ch["blockCount"] = nxt - ch["firstBlock"]
    book = {
        "id": "alice",
        "title": "Alice’s Adventures in Wonderland",
        "author": "Lewis Carroll",
        "language": "en",
        "parserVersion": 1,
        "totalChars": sum(len(b["text"]) for b in blocks),
        "chapters": chapters,
        "blocks": blocks,
        "notes": [],
    }
    with open(dst, "w", encoding="utf-8", newline="\n") as f:
        json.dump(book, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(len(blocks), "blocks,", book["totalChars"], "chars,", len(chapters), "chapters")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
