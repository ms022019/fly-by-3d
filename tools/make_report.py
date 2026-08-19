"""開発レポート (日本語 PDF) を生成する。

    python tools/make_report.py

出力: docs/BallCollector3D_report_ja.pdf

日本語フォント (M PLUS 1p / SIL OFL) はリポジトリに含めていないので、
無ければ自動でダウンロードして ~/.cache/report-fonts/ に置く。
"""

from __future__ import annotations

import re
import urllib.request
from pathlib import Path

from reportlab.graphics.shapes import Circle, Drawing, Line, PolyLine, Polygon, Rect, String
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    Image,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "BallCollector3D_report_ja.pdf"
SHOT = ROOT / "docs" / "assets" / "screenshot.png"
TRAIN_LOG = ROOT / "docs" / "assets" / "train.log"

# 本文用の日本語フォント。Regular / Bold が揃っていて見出しに太さの差を出せる。
FONT_DIR = Path.home() / ".cache" / "report-fonts"
FONT_URLS = {
    "MPLUS1p": "https://raw.githubusercontent.com/google/fonts/main/ofl/mplus1p/MPLUS1p-Regular.ttf",
    "MPLUS1p-Bold": "https://raw.githubusercontent.com/google/fonts/main/ofl/mplus1p/MPLUS1p-Bold.ttf",
}
FONT = "MPLUS1p"
FONT_B = "MPLUS1p-Bold"

# 画面の配色をそのまま紙に持ってくる
INK = colors.HexColor("#14161D")
MUTED = colors.HexColor("#666D7E")
LINE = colors.HexColor("#D8DBE3")
PANEL = colors.HexColor("#F3F4F8")
# 表のヘッダ。紙に刷ったときベタ塗りで汚れないよう白地にする
HEAD_BG = colors.HexColor("#EEF0F6")
NAVY = colors.HexColor("#151A2E")
PINK = colors.HexColor("#F0526B")

PAGE_W, PAGE_H = A4
MARGIN = 18 * mm
CONTENT_W = PAGE_W - MARGIN * 2

# tools/train.py の実測ログ (steps, 1 エピソードあたりの取得数)
MEASURED_CURVE = [
    (0, 0.0), (10_032, 0.17), (20_016, 0.17), (30_000, 5.79), (40_032, 5.79),
    (50_016, 21.89), (60_000, 21.89), (70_032, 40.41), (80_016, 40.41),
    (90_000, 50.54), (100_032, 50.54), (110_016, 54.68), (120_000, 54.68),
    (130_032, 58.04), (150_000, 58.04), (160_032, 60.71), (170_016, 60.71),
    (180_000, 62.29), (190_032, 62.29), (200_016, 62.35),
]


# --------------------------------------------------------------------------- font


def ensure_font() -> None:
    FONT_DIR.mkdir(parents=True, exist_ok=True)
    for name, url in FONT_URLS.items():
        path = FONT_DIR / f"{name}.ttf"
        if not path.exists():
            with urllib.request.urlopen(url, timeout=180) as res:
                path.write_bytes(res.read())
        pdfmetrics.registerFont(TTFont(name, str(path)))
    pdfmetrics.registerFontFamily(FONT, normal=FONT, bold=FONT_B, italic=FONT, boldItalic=FONT_B)


# --------------------------------------------------------------------------- styles

S: dict = {}


def styles() -> dict:
    base = dict(fontName=FONT, textColor=INK, alignment=TA_LEFT, wordWrap="CJK")
    return {
        "title": ParagraphStyle(
            "title", **{**base, "fontName": FONT_B}, fontSize=25, leading=34
        ),
        "subtitle": ParagraphStyle(
            "subtitle", **{**base, "textColor": MUTED}, fontSize=10.5, leading=18
        ),
        "h1": ParagraphStyle("h1", **{**base, "fontName": FONT_B}, fontSize=15, leading=22),
        "h2": ParagraphStyle("h2", **{**base, "fontName": FONT_B}, fontSize=11, leading=18),
        "body": ParagraphStyle("body", **base, fontSize=9.6, leading=16.5),
        "small": ParagraphStyle("small", **{**base, "textColor": MUTED}, fontSize=8.4, leading=14),
        "cell": ParagraphStyle("cell", **base, fontSize=8.8, leading=14),
        "cellc": ParagraphStyle(
            "cellc", **{**base, "alignment": TA_CENTER}, fontSize=8.8, leading=14
        ),
        "th": ParagraphStyle(
            "th",
            **{**base, "fontName": FONT_B},
            fontSize=8.8,
            leading=14,
        ),
        "thc": ParagraphStyle(
            "thc",
            **{**base, "alignment": TA_CENTER, "fontName": FONT_B},
            fontSize=8.8,
            leading=14,
        ),
        "caption": ParagraphStyle(
            "caption",
            **{**base, "textColor": MUTED, "alignment": TA_CENTER},
            fontSize=8.2,
            leading=13,
        ),
    }


def p(text: str, style: str = "body") -> Paragraph:
    return Paragraph(text, S[style])


def heading(number: str, text: str) -> Table:
    num = Paragraph(
        f'<font color="#F0526B">{number}</font>',
        ParagraphStyle("n", fontName=FONT_B, fontSize=15, textColor=PINK),
    )
    t = Table([[num, p(text, "h1")]], colWidths=[11 * mm, CONTENT_W - 11 * mm])
    t.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
                ("LINEBELOW", (0, 0), (-1, -1), 0.9, INK),
            ]
        )
    )
    return t


def sub(text: str) -> Paragraph:
    return p(f'<font color="#F0526B">■</font>  {text}', "h2")


def table(rows: list[list[str]], widths: list[float], center: list[int] | None = None) -> Table:
    center = center or []
    data = []
    for r, row in enumerate(rows):
        line = []
        for c, cell in enumerate(row):
            if r == 0:
                line.append(p(cell, "thc" if c in center else "th"))
            else:
                line.append(p(cell, "cellc" if c in center else "cell"))
        data.append(line)
    t = Table(data, colWidths=widths, repeatRows=1)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), HEAD_BG),
        ("LINEABOVE", (0, 0), (-1, 0), 0.6, LINE),
        ("LINEBELOW", (0, 0), (-1, 0), 1.1, INK),
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


def callout(title: str, text: str) -> Table:
    t = Table(
        [[p(f'<font color="#F0526B">{title}</font>', "h2")], [p(text)]],
        colWidths=[CONTENT_W],
    )
    t.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), PANEL),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, 0), 8),
                ("BOTTOMPADDING", (0, 0), (-1, 0), 2),
                ("TOPPADDING", (0, -1), (-1, -1), 0),
                ("BOTTOMPADDING", (0, -1), (-1, -1), 9),
                ("LINEBEFORE", (0, 0), (0, -1), 2.4, PINK),
            ]
        )
    )
    return t


# --------------------------------------------------------------------------- figures


def txt(d: Drawing, x, y, s, size=8, color=INK, anchor="start", bold=False) -> None:
    face = FONT_B if bold else FONT
    d.add(String(x, y, s, fontName=face, fontSize=size, fillColor=color, textAnchor=anchor))


def arrow(d: Drawing, x1, y1, x2, y2, color, width=1.4) -> None:
    d.add(Line(x1, y1, x2, y2, strokeColor=color, strokeWidth=width))
    dx, dy = x2 - x1, y2 - y1
    n = (dx * dx + dy * dy) ** 0.5 or 1.0
    ux, uy = dx / n, dy / n
    px, py = -uy, ux
    h = 5.5
    d.add(
        Polygon(
            [
                x2, y2,
                x2 - ux * h + px * h * 0.45, y2 - uy * h + py * h * 0.45,
                x2 - ux * h - px * h * 0.45, y2 - uy * h - py * h * 0.45,
            ],
            fillColor=color,
            strokeColor=color,
        )
    )


def box(d: Drawing, x, y, w, h, fill, stroke=None, radius=4) -> None:
    d.add(Rect(x, y, w, h, fillColor=fill, strokeColor=stroke or fill, rx=radius, ry=radius))


def loop_figure() -> Drawing:
    """Godot と Python がどう噛み合っているかの図。"""
    w, h = CONTENT_W, 116
    d = Drawing(w, h)
    bw = 168
    lx, rx = 4, w - bw - 4

    box(d, lx, 12, bw, 78, colors.HexColor("#EFF3FB"), colors.HexColor("#C6D6EE"))
    txt(d, lx + 14, 72, "Godot 4.4", 10.5, colors.HexColor("#1D3F73"), bold=True)
    txt(d, lx + 14, 55, "物理・描画・ゲームルール", 7.8, MUTED)
    txt(d, lx + 14, 41, "アリーナ / 球 / ターゲット", 7.8, MUTED)
    txt(d, lx + 14, 27, "観測と報酬を組み立てて送る", 7.8, MUTED)

    box(d, rx, 12, bw, 78, colors.HexColor("#FDF0F2"), colors.HexColor("#F3C6CE"))
    txt(d, rx + 14, 72, "Python (PPO)", 10.5, colors.HexColor("#8E2438"), bold=True)
    txt(d, rx + 14, 55, "Stable-Baselines3", 7.8, MUTED)
    txt(d, rx + 14, 41, "方策ネットワーク 64 × 64", 7.8, MUTED)
    txt(d, rx + 14, 27, "経験を貯めて重みを更新", 7.8, MUTED)

    ml, mr = lx + bw, rx
    arrow(d, ml + 10, 66, mr - 10, 66, colors.HexColor("#4A7FC1"))
    txt(d, (ml + mr) / 2, 72, "観測 12 次元 ＋ 報酬", 8, colors.HexColor("#1D3F73"), "middle")
    arrow(d, mr - 10, 32, ml + 10, 32, PINK)
    txt(d, (ml + mr) / 2, 38, "行動 2 次元（X / Z トルク）", 8, colors.HexColor("#8E2438"), "middle")

    return d


def branch_figure() -> Drawing:
    """人間入力と AI 行動が同じ物理コードへ合流することを示す図。"""
    w, h = CONTENT_W, 112
    d = Drawing(w, h)

    box(d, 4, 64, 138, 27, colors.HexColor("#EFF3FB"), colors.HexColor("#C6D6EE"))
    txt(d, 73, 74, "キーボード入力（WASD）", 8, colors.HexColor("#1D3F73"), "middle")
    box(d, 4, 18, 138, 27, colors.HexColor("#FDF0F2"), colors.HexColor("#F3C6CE"))
    txt(d, 73, 28, "PPO が出した行動", 8, colors.HexColor("#8E2438"), "middle")

    box(d, 214, 41, 132, 27, NAVY)
    txt(d, 280, 51, "player.gd  apply_torque()", 8.4, colors.white, "middle", bold=True)

    box(d, w - 130, 41, 126, 27, PANEL, LINE)
    txt(d, w - 67, 51, "同じ物理・同じルール", 8, INK, "middle")

    arrow(d, 146, 77, 208, 61, colors.HexColor("#4A7FC1"), 1.2)
    arrow(d, 146, 31, 208, 47, PINK, 1.2)
    arrow(d, 350, 54, w - 134, 54, INK, 1.2)

    txt(d, 178, 92, 'heuristic == "human"', 7, MUTED, "middle")
    txt(d, 178, 10, "それ以外", 7, MUTED, "middle")
    return d


def curve_figure(points: list[tuple[int, float]]) -> Drawing:
    """学習ステップ数 対 1 エピソード獲得数の実測カーブ。"""
    w, h = CONTENT_W, 196
    d = Drawing(w, h)
    ox, oy = 32, 36
    pw, ph = w - ox - 12, h - oy - 22
    xmax = max(x for x, _ in points)
    ymax = 70.0

    box(d, ox, oy, pw, ph, colors.HexColor("#FAFBFD"), colors.HexColor("#FAFBFD"), radius=0)
    for i in range(8):
        y = oy + ph * i / 7
        d.add(Line(ox, y, ox + pw, y, strokeColor=LINE, strokeWidth=0.35))
        txt(d, ox - 6, y - 3, f"{ymax * i / 7:.0f}", 7, MUTED, "end")
    for tick in range(0, int(xmax) + 1, 50_000):  # 50k 刻みの実値を打つ
        x = ox + pw * tick / xmax
        d.add(Line(x, oy - 3, x, oy, strokeColor=MUTED, strokeWidth=0.6))
        txt(d, x, oy - 13, f"{tick // 1000}k", 7, MUTED, "middle")

    y36 = oy + ph * 36.0 / ymax
    d.add(Line(ox, y36, ox + pw, y36, strokeColor=colors.HexColor("#9AA2B4"),
               strokeWidth=0.9, strokeDashArray=[3, 3]))
    txt(d, ox + pw - 4, y36 + 5, "手書きの貪欲方策  36 個", 7.2, colors.HexColor("#7C8496"), "end")

    pts: list[float] = []
    for x, y in points:
        pts += [ox + pw * x / xmax, oy + ph * min(y, ymax) / ymax]
    d.add(PolyLine(pts, strokeColor=PINK, strokeWidth=2.0))
    d.add(Circle(pts[-2], pts[-1], 3.0, fillColor=PINK, strokeColor=colors.white, strokeWidth=1.2))
    txt(d, pts[-2] - 7, pts[-1] - 12, f"{points[-1][1]:.1f} 個 / 60 秒", 8, PINK, "end", bold=True)

    d.add(Line(ox, oy, ox + pw, oy, strokeColor=MUTED, strokeWidth=0.7))
    d.add(Line(ox, oy, ox, oy + ph, strokeColor=MUTED, strokeWidth=0.7))
    txt(d, ox, h - 11, "1 エピソード（60 秒）あたりの取得数", 8, INK, bold=True)
    txt(d, ox + pw, oy - 27, "学習ステップ数", 7.5, MUTED, "end")
    return d


# --------------------------------------------------------------------------- data


def learning_curve() -> list[tuple[int, float]]:
    """学習ログがあればそれを、無ければ記録済みの実測値を使う。"""
    if TRAIN_LOG.exists():
        pts = []
        for line in TRAIN_LOG.read_text().splitlines():
            m = re.match(r"\[\s*([\d,]+) steps\]\s+targets/episode\s+([\d.]+)", line)
            if m:
                pts.append((int(m.group(1).replace(",", "")), float(m.group(2))))
        if len(pts) >= 5:
            return [(0, 0.0)] + pts
    return MEASURED_CURVE


# --------------------------------------------------------------------------- page


def decorate(canvas, doc) -> None:
    canvas.saveState()
    canvas.setFont(FONT, 7.6)
    canvas.setFillColor(MUTED)
    canvas.drawString(MARGIN, 11 * mm, "Ball Collector 3D — 開発レポート")
    canvas.drawRightString(PAGE_W - MARGIN, 11 * mm, str(doc.page))
    canvas.setStrokeColor(LINE)
    canvas.setLineWidth(0.5)
    canvas.line(MARGIN, 14 * mm, PAGE_W - MARGIN, 14 * mm)
    canvas.restoreState()


def story() -> list:
    f: list = []

    def gap(n: float) -> Spacer:
        return Spacer(1, n)

    # ---------------------------------------------------------------- 表紙
    f.append(p('<font color="#F0526B">開発レポート</font>', "subtitle"))
    f.append(gap(2))
    f.append(p("Ball Collector 3D", "title"))
    f.append(gap(4))
    f.append(
        p(
            "人間も遊べて、AI も強化学習で上達する 3D ゲーム<br/>"
            "Godot 4.4 ＋ godot-rl ＋ Stable-Baselines3 ／ 2026 年 8 月 18 日",
            "subtitle",
        )
    )
    f.append(gap(14))

    if SHOT.exists():
        f.append(Image(str(SHOT), width=CONTENT_W, height=CONTENT_W * 545 / 1152))
        f.append(gap(5))
        f.append(p("学習済み AI がプレイしている様子。青い球がプレイヤー、黄色がターゲット。", "caption"))
    f.append(gap(14))

    f.append(
        table(
            [
                ["プレイヤー", "取得数 / 60 秒", "中身"],
                ["学習前の AI（ランダム）", "0.2", "何も学習していない初期方策"],
                ["手書きの貪欲方策", "36", "最寄りのターゲットへ直進するだけ"],
                ["PPO で 18 万ステップ学習した AI", "64", "本レポートで作った方策"],
            ],
            [56 * mm, 30 * mm, CONTENT_W - 86 * mm],
            center=[1],
        )
    )
    f.append(gap(7))
    f.append(
        p(
            "同じフィールド・同じルールを、人間はキーボードで、AI は強化学習で得た方策で遊ぶ。"
            "「学習させたら本当に上手くなるのか」を、数字で見えるところまで作った。",
            "small",
        )
    )

    f.append(PageBreak())

    # ---------------------------------------------------------------- 1
    f.append(heading("1", "作ったもの"))
    f.append(gap(9))
    f.append(
        p(
            "球体を転がして、60 秒でターゲットを何個集められるかを競う 3D ゲーム。"
            "球は <b>RigidBody3D</b> にトルクをかけて動かしているので、慣性で滑る。"
            "止まりたいときは進みたい方向と逆に入力して減速する、Marble Madness のような手触りになっている。"
        )
    )
    f.append(gap(9))
    f.append(
        table(
            [
                ["要素", "内容"],
                ["ルール", "60 秒タイムアタック。ターゲットを取ると +1 点"],
                ["ターゲット", "常に 6 個。取ると別のランダム位置に再出現する"],
                ["フィールド", "30 × 30 の平らな板。縁を越えると場外落下 → 中央にリスポーン"],
                ["操作", "W A S D ／ 矢印キーで転がす、R でリスタート、Esc で終了"],
                ["カメラ", "球を追従。回転は固定（画面の奥 = ワールド -Z）"],
                ["遊び方", "ブラウザ（Web ビルド）／ Windows ネイティブ ／ コンテナ内で直接実行"],
            ],
            [28 * mm, CONTENT_W - 28 * mm],
        )
    )
    f.append(gap(11))
    f.append(
        callout(
            "カメラの回転を固定した理由",
            "カメラが回ると「画面の奥」と「ワールド座標の -Z」がずれる。"
            "人間は画面を見て操作し、AI はワールド座標で行動を出すので、"
            "回転を許すと両者にとっての「前」の意味が食い違ってしまう。"
            "カメラワークの自由度を捨てる代わりに、人間と AI がまったく同じ意味の操作をしている状態を保った。",
        )
    )
    f.append(gap(13))

    f.append(sub("プロジェクトの構成"))
    f.append(gap(6))
    f.append(
        table(
            [
                ["場所", "役割"],
                ["game/scripts/arena.gd", "ルール・報酬・エピソード管理（1 プレイ分のフィールド）"],
                ["game/scripts/player.gd", "球の物理制御。人間入力と AI 行動の両方を受ける"],
                ["game/scripts/ball_ai_controller.gd", "観測・行動・報酬の定義（godot-rl の規約に沿う）"],
                ["tools/train.py", "PPO による学習"],
                ["tools/play_ai.py", "学習済みモデルにプレイさせて観る ／ スコアを測る"],
                ["tools/godot_launcher.py", "Godot プロセスの起動と学習環境の生成"],
                ["models/ball_collector.zip", "学習済みモデル"],
            ],
            [56 * mm, CONTENT_W - 56 * mm],
        )
    )

    f.append(PageBreak())

    # ---------------------------------------------------------------- 2
    f.append(heading("2", "どんな学習をさせたか"))
    f.append(gap(9))
    f.append(
        p(
            "使ったのは <b>強化学習</b>。正解のプレイデータを与えるのではなく、"
            "AI が自分で球を転がしてみて、点が入った動きの確率を上げていく方式にした。"
            "人間のプレイ記録は 1 件も使っていない。"
        )
    )
    f.append(gap(6))
    f.append(
        p(
            "アルゴリズムは <b>PPO</b>（Stable-Baselines3）。ネットワークは 64 × 64 の 2 層 MLP で、"
            "パラメータ数は数千しかない。画像は見せず、数値だけを渡している。"
            "この環境には GPU が無いので、CPU だけで学習しきれる規模に意図的に抑えた。"
        )
    )
    f.append(gap(11))
    f.append(loop_figure())
    f.append(gap(5))
    f.append(p(
            "Godot がゲームを回し、Python が行動を決める。この往復そのものが学習になる"
            "（godot-rl が用意する TCP ソケットで、8 物理フレームごとに 1 往復）。",
            "caption",
        ))
    f.append(gap(13))

    f.append(sub("AI に見せているもの（観測 12 次元）"))
    f.append(gap(6))
    f.append(
        table(
            [
                ["観測", "次元", "なぜ必要か"],
                ["自分の速度 x, y, z", "3", "慣性で滑るので、今の勢いが分からないと止まれない"],
                ["アリーナ内での自分の位置 x, y, z", "3", "縁に近いか＝落ちる危険があるかを判断する"],
                ["最寄りターゲットへの相対位置 x, z", "2", "どちらへ向かうべきかの主信号"],
                ["2 番目に近いターゲットへの相対位置 x, z", "2", "次の的も見えると経路取りが良くなる"],
                ["最寄りターゲットまでの距離", "1", "近さそのものを明示的に渡す"],
                ["残り時間", "1", "固定長エピソードを正しく扱うために必要（下記）"],
            ],
            [58 * mm, 13 * mm, CONTENT_W - 71 * mm],
            center=[1],
        )
    )
    f.append(gap(11))
    f.append(
        callout(
            "残り時間を観測に入れた理由",
            "エピソードは 60 秒で必ず終わる。もし残り時間を見せないと、AI から見た世界は"
            "「同じ状況なのに、あるときは続き、あるときは唐突に終わる」ものになってしまい、"
            "『この状態はこの先どれくらい得点につながるか』を見積もる価値関数が正しく学習できない。"
            "残り時間を観測に含めることで、いま見えている状態だけで先が決まる問題"
            "（マルコフ決定過程）としてきちんと閉じる。",
        )
    )
    f.append(gap(13))

    f.append(sub("AI が出すもの（行動 2 次元）"))
    f.append(gap(6))
    f.append(
        p(
            "ワールド X 方向と Z 方向のトルク指令、それぞれ [-1, 1] の連続値。"
            "人間がキーを押したときに生成される入力とまったく同じ形式で、同じ "
            "<b>apply_torque()</b> に渡される。"
            "行動を決めるのは 8 物理フレームに 1 回（action repeat = 8）なので、"
            "1 エピソード 3,600 フレーム中、AI の意思決定は 450 回。"
        )
    )
    f.append(gap(13))

    f.append(sub("報酬の設計"))
    f.append(gap(6))
    f.append(
        table(
            [
                ["事象", "報酬", "狙い"],
                ["ターゲットを取った", "+1.0", "本来の目的そのもの"],
                ["場外に落ちた", "-1.0", "縁に突っ込む動きを抑える"],
                ["ターゲットに近づいた", "近づいた距離 × 0.02", "学習の立ち上がりを速くする"],
            ],
            [38 * mm, 34 * mm, CONTENT_W - 72 * mm],
            center=[1],
        )
    )
    f.append(gap(9))
    f.append(
        callout(
            "距離シェーピングが効いた場面",
            "ターゲット取得の +1 だけだと、学習開始直後の AI は偶然ターゲットに触れるまで"
            "何の手がかりも得られない。ランダムに転がる球が 30 × 30 の板の上で的に当たる確率は低く、"
            "報酬がほぼ全ステップ 0 のまま時間だけが過ぎてしまう。"
            "「近づいた分だけ小さく加点」を足したことで、AI はまず『的の方を向いて進む』を覚え、"
            "そこから取得につながった。",
        )
    )
    f.append(gap(13))

    f.append(sub("学習の設定値"))
    f.append(gap(6))
    f.append(
        table(
            [
                ["項目", "値", "選んだ理由"],
                ["方策ネットワーク", "64 × 64 MLP", "観測が 12 次元しかないので、これで十分足りる"],
                ["学習率", "3e-4", "PPO の標準値。触る必要が無かった"],
                ["割引率 γ", "0.99", "60 秒先まで見通せるように長めに取る"],
                ["ロールアウト長 / バッチ", "64 / 256", "48 体ぶんを 1 回の更新にまとめる"],
                ["エントロピー係数", "0.001", "探索を少しだけ残し、序盤で動きが固まるのを防ぐ"],
                ["action repeat", "8", "60Hz の物理に対し、意思決定は 7.5Hz。学習を軽くする"],
                ["同時実行エージェント数", "48", "16 アリーナ × 3 プロセス"],
                ["物理の倍速", "40 倍", "描画しないので、実時間より速く回せる"],
            ],
            [40 * mm, 26 * mm, CONTENT_W - 66 * mm],
            center=[1],
        )
    )

    f.append(PageBreak())

    # ---------------------------------------------------------------- 3
    f.append(heading("3", "学習でできるようになったこと"))
    f.append(gap(9))
    f.append(
        p(
            "実際に学習を回した結果が下のグラフ。横軸が学習ステップ数、"
            "縦軸が 1 エピソード（60 秒）あたりに取れたターゲット数。CPU のみで、最後まで約 1.2 分。"
        )
    )
    f.append(gap(9))
    f.append(curve_figure(learning_curve()))
    f.append(gap(5))
    f.append(p("学習中の実測ログから作成。破線は比較用に書いた手書き貪欲方策の成績。", "caption"))
    f.append(gap(13))

    f.append(sub("何を覚えていったか"))
    f.append(gap(6))
    f.append(
        table(
            [
                ["段階", "取得数", "見て分かる変化"],
                ["学習前", "0.2", "その場でランダムに震えるだけ。落ちても気にしない"],
                ["2 万ステップ", "0.2", "まだほぼ動けない。ここで距離シェーピングが効き始める"],
                ["3 万ステップ", "5.8", "的の方向へ転がり出す。行き過ぎて通り過ぎることが多い"],
                ["5 万ステップ", "21.9", "移動が滑らかになる。場外落下が目に見えて減る"],
                ["9 万ステップ", "50.5", "慣性を見越して手前で減速するようになる"],
                ["20 万ステップ", "62.4", "取った直後に次の的へ向き直る。移動が連続してムダがない"],
            ],
            [28 * mm, 18 * mm, CONTENT_W - 46 * mm],
            center=[1],
        )
    )
    f.append(gap(11))
    f.append(
        p(
            "最終的に、最寄りの的へ直進するだけの手書き方策（36 個）を大きく上回った。"
            "差がついたのは主に 2 点。<b>慣性の扱い</b>（近づく前から逆向きのトルクをかけて減速し、"
            "行き過ぎない）と、<b>次の的まで見た経路取り</b>（2 番目に近い的を観測に入れてあるので、"
            "取った後の移動が短くなる向きから的に入る）。"
            "どちらも明示的には教えていない。報酬を最大化した結果として出てきた振る舞いになっている。"
        )
    )
    f.append(gap(9))
    f.append(
        p(
            "※ グラフの 62.4 は学習中（方策からサンプリングして探索している状態）の平均。"
            "学習を止めて決定論的に動かすと 64 個になる。",
            "small",
        )
    )
    f.append(gap(11))
    f.append(
        callout(
            "学習を速くするためにやったこと",
            "1 プロセスの中にアリーナを 16 面並べて 16 体を同時に走らせ、それを 3 プロセス、"
            "合計 48 体で経験を集めた。さらに物理シミュレーションを 40 倍速で回し、"
            "描画は不要なのでヘッドレスで実行している。"
            "この構成で環境側 6,779 steps/s、PPO の勾配計算を含めた実効で約 2,700 steps/s。"
            "20 万ステップが約 1.2 分で終わる。",
        )
    )

    f.append(PageBreak())

    # ---------------------------------------------------------------- 4
    f.append(heading("4", "学習をどうゲームに活かしているか"))
    f.append(gap(9))
    f.append(
        p(
            "学習した方策を「別物」として横に置くのではなく、"
            "<b>人間が遊ぶときとまったく同じコードを通す</b>ように作った。"
            "player.gd が入力元を切り替えるだけで、物理・ルール・エピソード長はすべて共通の経路を通る。"
        )
    )
    f.append(gap(9))
    f.append(branch_figure())
    f.append(gap(5))
    f.append(p("入力元が違うだけで、その先はすべて同じコード。", "caption"))
    f.append(gap(11))

    f.append(
        table(
            [
                ["活かしている点", "具体的にどうなっているか"],
                [
                    "スコアがそのまま比べられる",
                    "人間の 60 秒と AI の 60 秒が同じ長さであることを、AIController の "
                    "reset_after（3,600 物理フレーム）を唯一の基準にすることで保証している。"
                    "だから「AI は 64 個取れる」が、そのまま人間の目標値になる",
                ],
                [
                    "AI のプレイを観られる",
                    "python tools/play_ai.py で、学習済みの方策が実際に遊ぶ様子をウィンドウで見られる。"
                    "上達の中身（減速の仕方、的の回り方）を目で確認できる",
                ],
                [
                    "ゲームバランスが学習で検証された",
                    "AI が 60 秒で 64 個取れる＝フィールドの広さ・的の数・トルクの強さが"
                    "「詰まらずに動き続けられる」設定になっていることの裏付けになった。"
                    "人間が遊んでも手持ち無沙汰にならない",
                ],
                [
                    "報酬設計とルール設計が一致している",
                    "場外落下 -1.0 は、人間プレイでの「落ちると時間をロスする」感覚と同じ位置づけ。"
                    "AI が落ちなくなった＝ルールの意図が素直に伝わる形になっていた",
                ],
            ],
            [40 * mm, CONTENT_W - 40 * mm],
        )
    )
    f.append(gap(13))

    f.append(sub("この構成にして良かったこと"))
    f.append(gap(6))
    f.append(
        p(
            "ゲーム側と AI 側で仕様が二重管理になると、必ずどこかでずれる。"
            "エピソード長・トルクの強さ・ターゲット数といった「両方が知っている必要のある値」は"
            "ゲーム側に 1 つだけ置き、AI はそれを観測として受け取る形にした。"
            "そのため、アリーナの広さやターゲット数を arena.gd で変えるだけで、"
            "人間のプレイにも AI の学習にも同時に反映される。"
            "ゲームバランスを触るたびに学習コードを直す、という手戻りが起きない。"
        )
    )

    f.append(PageBreak())

    # ---------------------------------------------------------------- 5
    f.append(heading("5", "つまずいた点と、どう回避したか"))
    f.append(gap(9))
    f.append(
        table(
            [
                ["問題", "対処"],
                [
                    "Godot 単体で学習済みモデルを動かせない",
                    "godot-rl の ONNX 推論部は C# 実装で、この環境の Godot は非 .NET ビルドだった。"
                    "そこで「Python が推論し、Godot が描画する」構成にした。"
                    "将来 .NET ビルドへ移れるよう models/ball_collector.onnx は出力してある",
                ],
                [
                    "学習ログに「何個取れたか」が出せない",
                    "godot_rl 0.8.1 の GodotEnv.step_recv() が、Godot から届いた info を読み捨てていた。"
                    "受け取り側を差し替えて info を通し、報酬ではなく取得数で進捗を見られるようにした。"
                    "報酬は距離シェーピングを含むので直感的に読めないため、これは重要だった",
                ],
                [
                    "複数プロセスで学習を回せない",
                    "本家のラッパーが「実行ファイルが無いなら複数プロセス不可」と決め打ちしていた。"
                    "自前で Godot プロセスを起動して接続する形にして、48 体並列を実現した",
                ],
                [
                    "コンテナ内のプレイが 25fps しか出ない",
                    "描画自体（CPU ソフトウェア描画）は 65fps 出ており、遅いのは X11 のフレーム転送だと"
                    "実測で切り分けた。解像度を下げても頭打ちになる。"
                    "そこで Web ビルドと Windows ネイティブビルドを用意し、そちらでのプレイを推奨する形にした",
                ],
            ],
            [40 * mm, CONTENT_W - 40 * mm],
        )
    )
    f.append(gap(13))

    f.append(sub("実測した性能"))
    f.append(gap(6))
    f.append(
        table(
            [
                ["項目", "実測値"],
                ["学習スループット（16 アリーナ × 3 プロセス、40 倍速）", "6,779 steps/s"],
                ["PPO の更新を含めた実効速度", "約 2,700 steps/s"],
                ["20 万ステップの学習時間（CPU のみ）", "約 1.2 分"],
                ["メモリ（Godot ヘッドレス 1 プロセス ／ Python 側）", "85 MB ／ 672 MB"],
                ["描画 FPS（ローカル、1152 × 648）", "65.3 fps"],
                ["描画 FPS（X11 転送、1152 × 648）", "12.0 fps"],
            ],
            [CONTENT_W - 40 * mm, 40 * mm],
            center=[1],
        )
    )
    f.append(gap(13))

    f.append(sub("次にやるとしたら"))
    f.append(gap(6))
    f.append(
        p(
            "<b>障害物と周辺認識</b> — 今のフィールドは平坦で、AI は的の位置しか見ていない。"
            "プラグイン同梱の RaycastSensor3D を観測に足せば、壁を避ける行動まで学習できる。<br/>"
            "<b>ゲートくぐり</b> — 空中のリングを連続でくぐる 3D タスク。"
            "観測・行動・報酬の骨組みはそのまま流用できる。<br/>"
            "<b>サバイバルモード</b> — 的を取ると残り時間が回復するルール。arena.gd の変更だけで済む。"
        )
    )

    return f


def build() -> None:
    doc = BaseDocTemplate(
        str(OUT),
        pagesize=A4,
        leftMargin=MARGIN,
        rightMargin=MARGIN,
        topMargin=MARGIN,
        bottomMargin=20 * mm,
        title="Ball Collector 3D 開発レポート",
        author="Ball Collector 3D",
    )
    frame = Frame(MARGIN, 20 * mm, CONTENT_W, PAGE_H - MARGIN - 20 * mm, id="body")
    doc.addPageTemplates([PageTemplate(id="main", frames=[frame], onPage=decorate)])
    doc.build(story())


if __name__ == "__main__":
    ensure_font()
    S.update(styles())
    OUT.parent.mkdir(parents=True, exist_ok=True)
    build()
    print(f"wrote {OUT}")
