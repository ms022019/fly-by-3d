"""Zenn 記事の Markdown から PDF を作る。

    python tools/make_article_pdf.py

出力: docs/FlyBy3D_article_ja.pdf

記事 (zenn/articles/fly-by-3d.md) を唯一の出典にしている。記事を直して
これを実行し直せば PDF も追従する。両方を手で書くと必ず片方が古くなる。

体裁・配色・日本語フォントの準備は開発レポート (tools/make_report.py) から流用。
記事中の画像は GitHub Pages の URL を指しているが、PDF では取りに行かず
zenn/images/ のローカルファイルを使う (ファイル名で対応付ける)。
"""

from __future__ import annotations

import re
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib.utils import ImageReader
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    Image,
    KeepTogether,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

from make_report import (
    CONTENT_W,
    FONT,
    FONT_B,
    INK,
    LINE,
    MARGIN,
    MUTED,
    NAVY,
    PAGE_H,
    PAGE_W,
    PANEL,
    PINK,
    S,
    ensure_font,
    heading,
    p,
    styles,
    sub,
)

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "zenn" / "articles" / "fly-by-3d.md"
IMG_DIR = ROOT / "zenn" / "images"
OUT = ROOT / "docs" / "FlyBy3D_article_ja.pdf"

LINK_COLOR = "#1D5FBF"
CODE_COLOR = "#8E2438"


# --------------------------------------------------------------------------- markdown


def inline(text: str) -> str:
    """Markdown の行内記法を reportlab のタグへ。"""
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", rf'<link href="\2" color="{LINK_COLOR}">\1</link>', text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    # 等幅フォントは日本語グリフを持たないので、色を変えて区別する
    text = re.sub(r"`([^`]+)`", rf'<font color="{CODE_COLOR}">\1</font>', text)
    return text


def parse(md: str) -> list[tuple]:
    """記事を (種類, 中身) の並びにほどく。"""
    body = md
    if body.startswith("---"):
        body = body.split("---", 2)[2]

    blocks: list[tuple] = []
    lines = body.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if not stripped:
            i += 1
        elif stripped.startswith("```"):
            i += 1
            code: list[str] = []
            while i < len(lines) and not lines[i].strip().startswith("```"):
                code.append(lines[i])
                i += 1
            i += 1
            blocks.append(("code", "\n".join(code)))
        elif stripped.startswith("!["):
            match = re.search(r"\(([^)]+)\)", stripped)
            if match:
                blocks.append(("img", Path(match.group(1)).name))
            i += 1
        elif stripped.startswith("|"):
            rows: list[list[str]] = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                # 区切り行 (|---|---|) は捨てる
                if not all(set(c) <= set("-: ") for c in cells):
                    rows.append(cells)
                i += 1
            blocks.append(("table", rows))
        elif stripped.startswith("###"):
            blocks.append(("h3", stripped.lstrip("#").strip()))
            i += 1
        elif stripped.startswith("##"):
            blocks.append(("h2", stripped.lstrip("#").strip()))
            i += 1
        elif stripped.startswith("#"):
            blocks.append(("h1", stripped.lstrip("#").strip()))
            i += 1
        elif stripped in ("---", "***"):
            blocks.append(("hr", ""))
            i += 1
        elif stripped.startswith("- "):
            items: list[str] = []
            while i < len(lines) and lines[i].strip().startswith("- "):
                items.append(lines[i].strip()[2:])
                i += 1
            blocks.append(("ul", items))
        else:
            para: list[str] = []
            while i < len(lines) and lines[i].strip() and not re.match(
                r"^\s*(#|\||```|!\[|- |---$)", lines[i]
            ):
                para.append(lines[i].strip())
                i += 1
            blocks.append(("p", "".join(para)))
    return blocks


# --------------------------------------------------------------------------- flowables


def code_escape(line: str) -> str:
    """コード片はそのまま出す。行内記法は解釈せず、空白の並びも保つ。"""
    line = line.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    # Paragraph は連続する空白を 1 つに詰めてしまうので、桁を保つために置き換える
    return re.sub(r"  +", lambda m: "&nbsp;" * len(m.group(0)), line)


def code_block(text: str) -> Table:
    style = S["code"]
    rows = [[Paragraph(code_escape(line) or "&nbsp;", style)] for line in text.split("\n")]
    t = Table(rows, colWidths=[CONTENT_W])
    t.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), PANEL),
                ("LEFTPADDING", (0, 0), (-1, -1), 12),
                ("RIGHTPADDING", (0, 0), (-1, -1), 12),
                ("TOPPADDING", (0, 0), (-1, -1), 1),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
                ("TOPPADDING", (0, 0), (-1, 0), 8),
                ("BOTTOMPADDING", (0, -1), (-1, -1), 8),
            ]
        )
    )
    return t


def md_table(rows: list[list[str]]) -> Table:
    columns = max(len(r) for r in rows)
    rows = [r + [""] * (columns - len(r)) for r in rows]
    # 文字数の比率で幅を割り振る (最低幅は確保する)
    weights = [max(max(len(r[c]) for r in rows), 4) for c in range(columns)]
    total = float(sum(weights))
    widths = [max(CONTENT_W * w / total, 16 * mm) for w in weights]
    widths = [w * CONTENT_W / sum(widths) for w in widths]

    data = []
    for r, row in enumerate(rows):
        data.append([Paragraph(inline(c), S["th"] if r == 0 else S["cell"]) for c in row])
    t = Table(data, colWidths=widths, repeatRows=1)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), NAVY),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 4.5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4.5),
        ("LEFTPADDING", (0, 0), (-1, -1), 7),
        ("RIGHTPADDING", (0, 0), (-1, -1), 7),
        ("LINEBELOW", (0, 1), (-1, -1), 0.4, LINE),
    ]
    for r in range(2, len(rows), 2):
        style.append(("BACKGROUND", (0, r), (-1, r), PANEL))
    t.setStyle(TableStyle(style))
    return t


def picture(name: str) -> list:
    path = IMG_DIR / name
    if not path.exists():
        return []
    width, height = ImageReader(str(path)).getSize()
    draw_w = CONTENT_W
    draw_h = draw_w * height / width
    # 縦長の図で 1 ページを食い潰さないよう上限を設ける
    if draw_h > 150 * mm:
        draw_h = 150 * mm
        draw_w = draw_h * width / height
    return [Spacer(1, 4), Image(str(path), width=draw_w, height=draw_h), Spacer(1, 10)]


def bullets(items: list[str]) -> list:
    out = []
    for item in items:
        row = Table(
            [[p('<font color="#F0526B">•</font>', "body"), p(inline(item))]],
            colWidths=[6 * mm, CONTENT_W - 6 * mm],
        )
        row.setStyle(
            TableStyle(
                [
                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                    ("LEFTPADDING", (0, 0), (-1, -1), 0),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                    ("TOPPADDING", (0, 0), (-1, -1), 1),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
                ]
            )
        )
        out.append(row)
    return out


# --------------------------------------------------------------------------- page


def decorate(canvas, doc) -> None:
    canvas.saveState()
    canvas.setFont(FONT, 7.6)
    canvas.setFillColor(MUTED)
    canvas.drawString(MARGIN, 11 * mm, "Fly By 3D — 記事")
    canvas.drawRightString(PAGE_W - MARGIN, 11 * mm, str(doc.page))
    canvas.setStrokeColor(LINE)
    canvas.setLineWidth(0.5)
    canvas.line(MARGIN, 14 * mm, PAGE_W - MARGIN, 14 * mm)
    canvas.restoreState()


def story(md: str) -> list:
    title = re.search(r'^title:\s*"(.*)"', md, re.M)
    f: list = [
        p('<font color="#F0526B">記事</font>', "subtitle"),
        Spacer(1, 2),
        p(title.group(1) if title else "Fly By 3D", "title"),
        Spacer(1, 4),
        p(
            "Godot 4.4 ＋ PPO ／ 2026 年 8 月 19 日<br/>"
            '<link href="https://ms022019.github.io/fly-by-3d/touch/" color="%s">'
            "https://ms022019.github.io/fly-by-3d/touch/</link>" % LINK_COLOR,
            "subtitle",
        ),
        Spacer(1, 12),
    ]

    blocks = parse(md)
    skip = -1
    for index, (kind, value) in enumerate(blocks):
        if index == skip:
            continue
        # 見出しの直後の図は、見出しだけが前ページに取り残されないよう一緒に送る
        if kind == "h3" and index + 1 < len(blocks) and blocks[index + 1][0] == "img":
            group = [sub(inline(value)), Spacer(1, 6)] + picture(blocks[index + 1][1])
            f.append(Spacer(1, 8))
            f.append(KeepTogether(group))
            skip = index + 1
            continue
        if kind == "h1":
            continue  # 表紙で使うので本文には出さない
        if kind == "h2":
            match = re.match(r"^(\d+)\.\s*(.*)$", value)
            f.append(Spacer(1, 10))
            f.append(heading(match.group(1), match.group(2)) if match else heading("", value))
            f.append(Spacer(1, 9))
        elif kind == "h3":
            f.append(Spacer(1, 8))
            f.append(sub(inline(value)))
            f.append(Spacer(1, 6))
        elif kind == "p":
            f.append(p(inline(value)))
            f.append(Spacer(1, 7))
        elif kind == "ul":
            f.extend(bullets(value))
            f.append(Spacer(1, 7))
        elif kind == "table":
            f.append(md_table(value))
            f.append(Spacer(1, 9))
        elif kind == "code":
            f.append(KeepTogether(code_block(value)))
            f.append(Spacer(1, 9))
        elif kind == "img":
            f.extend(picture(value))
    return f


def build() -> None:
    doc = BaseDocTemplate(
        str(OUT),
        pagesize=A4,
        leftMargin=MARGIN,
        rightMargin=MARGIN,
        topMargin=MARGIN,
        bottomMargin=20 * mm,
        title="Fly By 3D 記事",
        author="Fly By 3D",
    )
    frame = Frame(MARGIN, 20 * mm, CONTENT_W, PAGE_H - MARGIN - 20 * mm, id="body")
    doc.addPageTemplates([PageTemplate(id="main", frames=[frame], onPage=decorate)])
    doc.build(story(SRC.read_text(encoding="utf-8")))


if __name__ == "__main__":
    ensure_font()
    S.update(styles())
    # 記事はコード片が多いので、専用のスタイルを足す
    from reportlab.lib.styles import ParagraphStyle

    S["code"] = ParagraphStyle(
        "code", fontName=FONT, textColor=INK, fontSize=8.6, leading=13.5, wordWrap="CJK"
    )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    build()
    print(f"wrote {OUT}")
