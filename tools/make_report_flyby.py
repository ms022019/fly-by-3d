"""Fly By 3D の開発レポート (日本語 PDF) を生成する。

    python tools/make_report_flyby.py

出力: docs/FlyBy3D_report_ja.pdf

体裁・配色・日本語フォントの準備は Ball Collector 版 (tools/make_report.py) から
そのまま流用している。図とデータだけがこのファイル固有。
"""

from __future__ import annotations

from pathlib import Path

from reportlab.graphics.shapes import Circle, Drawing, Ellipse, Line, PolyLine
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    Image,
    KeepTogether,
    PageBreak,
    PageTemplate,
    Spacer,
)

from make_report import (
    CONTENT_W,
    FONT,
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
    arrow,
    box,
    callout as _callout,
    ensure_font,
    heading,
    p,
    styles,
    sub,
    table,
    txt,
)

def callout(title: str, text: str):
    """ページ境界で見出しと本文が分かれないように包む。"""
    return KeepTogether(_callout(title, text))


ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "FlyBy3D_report_ja.pdf"
SHOT = ROOT / "docs" / "assets" / "flyby_screenshot.png"
SHOT_PASS = ROOT / "docs" / "assets" / "flyby_pass.png"

BLUE = colors.HexColor("#4A7FC1")
BLUE_D = colors.HexColor("#1D3F73")
GOLD = colors.HexColor("#D79A16")

# tools/train.py の実測ログ (steps, 1 エピソードあたりのゲート通過数)
# 段階 1 = 行動 2 次元 (ピッチ・ヨーのみ、速度一定)
STAGE1 = [
    (0, 0.0), (10_032, 0.00), (20_016, 0.00), (30_000, 0.40), (40_032, 0.40),
    (50_016, 1.83), (60_000, 1.83), (70_032, 5.57), (80_016, 5.57),
    (90_000, 11.35), (100_032, 11.35), (110_016, 17.54), (120_000, 17.54),
    (130_032, 22.78), (140_016, 22.78), (150_000, 22.78), (160_032, 26.07),
    (170_016, 26.07), (180_000, 28.12), (190_032, 28.12), (200_016, 28.79),
    (210_000, 28.79), (220_032, 28.90), (230_016, 28.90), (240_000, 29.36),
    (250_032, 29.36), (260_016, 29.82), (270_000, 29.82), (280_032, 29.82),
    (290_016, 29.86), (300_000, 29.86),
]
# 段階 2 = 行動 3 次元 (スロットル追加)
STAGE2 = [
    (0, 0.0), (10_032, 0.00), (30_000, 0.27), (50_016, 1.22), (70_032, 4.23),
    (90_000, 9.65), (110_016, 17.42), (130_032, 24.65), (150_000, 24.65),
    (170_016, 29.72), (190_032, 32.98), (210_000, 34.57), (230_016, 35.40),
    (250_032, 35.83), (270_000, 36.35), (290_016, 36.80), (310_032, 37.26),
    (330_000, 37.45), (350_016, 37.61), (370_032, 37.66), (390_000, 37.31),
    (410_016, 37.31), (430_032, 37.63), (450_000, 38.20), (470_016, 38.40),
    (490_032, 38.29), (510_000, 37.78), (530_016, 37.57), (550_032, 37.86),
    (570_000, 37.94), (590_016, 37.67), (602_112, 37.67),
]
GREEDY_STAGE1 = 28.5
GREEDY_STAGE2 = 34.4


# --------------------------------------------------------------------------- figures


def rl_cycle_figure() -> Drawing:
    """強化学習の基本ループ。環境と方策が何をやり取りしているか。"""
    w, h = CONTENT_W, 178
    d = Drawing(w, h)

    cx = w / 2
    bw, bh = 152, 46
    # 上: 環境 / 下: 方策
    box(d, cx - bw / 2, h - bh - 12, bw, bh, colors.HexColor("#EFF3FB"), colors.HexColor("#C6D6EE"))
    txt(d, cx, h - 30, "環境 (Godot のゲーム)", 9.5, BLUE_D, "middle", bold=True)
    txt(d, cx, h - 44, "物理を 1 歩進めて結果を返す", 7.4, MUTED, "middle")

    box(d, cx - bw / 2, 12, bw, bh, colors.HexColor("#FDF0F2"), colors.HexColor("#F3C6CE"))
    txt(d, cx, 42, "方策 (ニューラルネット)", 9.5, colors.HexColor("#8E2438"), "middle", bold=True)
    txt(d, cx, 28, "観測を入れると行動が出る", 7.4, MUTED, "middle")

    # 左回り: 環境 -> 観測と報酬 -> 方策
    lx = cx - bw / 2 - 96
    arrow(d, cx - bw / 2 - 6, h - 35, lx + 12, h - 35, BLUE, 1.2)
    d.add(Line(lx + 12, h - 35, lx + 12, 35, strokeColor=BLUE, strokeWidth=1.2))
    arrow(d, lx + 12, 35, cx - bw / 2 - 6, 35, BLUE, 1.2)
    txt(d, lx + 18, h / 2 + 12, "観測 17 個の数値", 8, BLUE_D)
    txt(d, lx + 18, h / 2 - 2, "報酬 1 個の数値", 8, BLUE_D)

    # 右回り: 方策 -> 行動 -> 環境
    rx = cx + bw / 2 + 96
    arrow(d, cx + bw / 2 + 6, 35, rx - 12, 35, PINK, 1.2)
    d.add(Line(rx - 12, 35, rx - 12, h - 35, strokeColor=PINK, strokeWidth=1.2))
    arrow(d, rx - 12, h - 35, cx + bw / 2 + 6, h - 35, PINK, 1.2)
    txt(d, rx - 18, h / 2 + 5, "行動 3 個の数値", 8, colors.HexColor("#8E2438"), "end")

    txt(d, cx, h / 2 + 6, "この往復を", 8.4, INK, "middle")
    txt(d, cx, h / 2 - 7, "60 万回くり返す", 8.4, INK, "middle", bold=True)
    return d


def obs_figure() -> Drawing:
    """機体ローカル座標系で何を観測しているか。"""
    w, h = CONTENT_W, 192
    d = Drawing(w, h)

    dx, dy = 74, 66  # 機体
    g1x, g1y = 268, 128  # 次のゲート
    g2x, g2y = 418, 84  # その次のゲート

    # 機体 (右を向いた三角)
    d.add(
        PolyLine(
            [dx - 16, dy - 11, dx + 17, dy + 1, dx - 16, dy + 13, dx - 16, dy - 11],
            strokeColor=colors.HexColor("#E2761B"),
            strokeWidth=2.0,
        )
    )
    txt(d, dx - 2, dy - 26, "自機", 8, INK, "middle", bold=True)

    # 相対位置ベクトル (先に引いて、ゲートを上に重ねる)
    arrow(d, dx + 22, dy + 4, g1x - 14, g1y - 6, INK, 1.4)
    txt(d, 118, 126, "相対位置 3 ＋ 距離 1", 8, INK)
    arrow(d, dx + 22, dy - 2, g2x - 14, g2y - 8, colors.HexColor("#9AA2B4"), 1.1)
    txt(d, 250, 56, "相対位置 3", 8, colors.HexColor("#7C8496"))

    for gx, gy, label, color in [
        (g1x, g1y, "次のゲート", GOLD),
        (g2x, g2y, "その次", BLUE),
    ]:
        d.add(Ellipse(gx, gy, 9, 22, fillColor=None, strokeColor=color, strokeWidth=2.2))
        txt(d, gx, gy + 30, label, 8, color, "middle", bold=True)
    arrow(d, g1x + 6, g1y + 4, g1x + 48, g1y + 20, GOLD, 1.3)
    txt(d, g1x + 52, g1y + 22, "法線 3", 7.6, GOLD)

    # 速度と上方向
    arrow(d, dx, dy + 26, dx, dy + 54, PINK, 1.3)
    txt(d, dx - 6, dy + 46, "ワールド上方向 3", 7.6, PINK, "end")
    arrow(d, dx - 34, dy - 16, dx - 6, dy - 4, colors.HexColor("#2E9E6B"), 1.3)
    txt(d, dx - 38, dy - 24, "速度 3", 7.6, colors.HexColor("#2E9E6B"), "end")

    box(d, w - 138, 8, 134, 42, PANEL, LINE)
    txt(d, w - 71, 34, "＋ 残り時間 1", 8.4, INK, "middle", bold=True)
    txt(d, w - 71, 20, "合計 17 次元", 8, MUTED, "middle")

    txt(d, 4, h - 12, "すべて機体から見た向きに直してから渡す", 8.4, INK, bold=True)
    return d


def ppo_figure() -> Drawing:
    """PPO の 1 回の更新でやっていること。"""
    w, h = CONTENT_W, 128
    d = Drawing(w, h)
    bw = (w - 24) / 3
    titles = [
        ("1  経験を集める", ["48 体を 64 ステップ動かし", "3,072 件の (観測・行動・報酬)", "を貯める"]),
        ("2  良し悪しを測る", ["各行動が平均よりどれだけ", "得だったかを計算する", "(GAE / 割引率 0.99)"]),
        ("3  方策を少し動かす", ["得だった行動の確率を上げる", "1 回の変化量は 20% までに", "制限し、10 周かけて更新"]),
    ]
    for i, (title, lines) in enumerate(titles):
        x = i * (bw + 12)
        box(d, x, 26, bw, 84, PANEL, LINE)
        txt(d, x + 12, 92, title, 9, PINK if i == 2 else INK, bold=True)
        for j, line in enumerate(lines):
            txt(d, x + 12, 74 - j * 13, line, 7.6, MUTED)
        if i < 2:
            arrow(d, x + bw + 1, 68, x + bw + 10, 68, INK, 1.2)

    d.add(Line(w - bw / 2, 26, w - bw / 2, 12, strokeColor=MUTED, strokeWidth=1.0))
    d.add(Line(w - bw / 2, 12, bw / 2, 12, strokeColor=MUTED, strokeWidth=1.0))
    arrow(d, bw / 2, 12, bw / 2, 24, MUTED, 1.0)
    txt(d, w / 2, 3, "これを 1 セットとして約 200 回くり返すと 60 万ステップ", 7.6, MUTED, "middle")
    return d


def loop_figure() -> Drawing:
    """Godot と Python の噛み合い。"""
    w, h = CONTENT_W, 118
    d = Drawing(w, h)
    bw = 172
    lx, rx = 4, w - bw - 4

    box(d, lx, 12, bw, 82, colors.HexColor("#EFF3FB"), colors.HexColor("#C6D6EE"))
    txt(d, lx + 14, 76, "Godot 4.4 (ヘッドレス × 3)", 9.6, BLUE_D, bold=True)
    txt(d, lx + 14, 60, "1 プロセスにコース 16 面", 7.6, MUTED)
    txt(d, lx + 14, 46, "物理を 40 倍速で回す", 7.6, MUTED)
    txt(d, lx + 14, 32, "観測と報酬を組み立てて送る", 7.6, MUTED)
    txt(d, lx + 14, 18, "合計 48 体が同時に飛ぶ", 7.6, MUTED)

    box(d, rx, 12, bw, 82, colors.HexColor("#FDF0F2"), colors.HexColor("#F3C6CE"))
    txt(d, rx + 14, 76, "Python (PPO)", 9.6, colors.HexColor("#8E2438"), bold=True)
    txt(d, rx + 14, 60, "Stable-Baselines3", 7.6, MUTED)
    txt(d, rx + 14, 46, "方策ネットワーク 64 × 64", 7.6, MUTED)
    txt(d, rx + 14, 32, "48 体ぶんをまとめて更新", 7.6, MUTED)
    txt(d, rx + 14, 18, "CPU のみ (GPU 無し)", 7.6, MUTED)

    ml, mr = lx + bw, rx
    arrow(d, ml + 10, 68, mr - 10, 68, BLUE)
    txt(d, (ml + mr) / 2, 74, "観測 17 ＋ 報酬", 8, BLUE_D, "middle")
    arrow(d, mr - 10, 34, ml + 10, 34, PINK)
    txt(d, (ml + mr) / 2, 40, "行動 3", 8, colors.HexColor("#8E2438"), "middle")
    txt(d, (ml + mr) / 2, 20, "TCP ソケット", 7, MUTED, "middle")
    return d


def branch_figure() -> Drawing:
    """人間入力と AI 行動が同じ物理コードへ合流することを示す図。"""
    w, h = CONTENT_W, 112
    d = Drawing(w, h)

    box(d, 4, 64, 136, 27, colors.HexColor("#EFF3FB"), colors.HexColor("#C6D6EE"))
    txt(d, 72, 74, "キーボード入力 (WASD ＋ Shift)", 7.4, BLUE_D, "middle")
    box(d, 4, 18, 136, 27, colors.HexColor("#FDF0F2"), colors.HexColor("#F3C6CE"))
    txt(d, 72, 28, "PPO が出した行動", 8, colors.HexColor("#8E2438"), "middle")

    box(d, 192, 41, 152, 27, NAVY)
    txt(d, 268, 51, "drone.gd  姿勢と速度の更新", 8.2, colors.white, "middle", bold=True)

    box(d, 374, 41, 115, 27, PANEL, LINE)
    txt(d, 431, 51, "同じ物理・同じルール", 8, INK, "middle")

    arrow(d, 144, 77, 186, 61, BLUE, 1.2)
    arrow(d, 144, 31, 186, 47, PINK, 1.2)
    arrow(d, 348, 54, 370, 54, INK, 1.2)

    txt(d, 166, 92, 'heuristic == "human"', 7, MUTED, "middle")
    txt(d, 166, 8, "それ以外", 7, MUTED, "middle")
    return d


def curve_figure() -> Drawing:
    """段階 1 と段階 2 の実測学習カーブ。"""
    w, h = CONTENT_W, 212
    d = Drawing(w, h)
    ox, oy = 34, 44
    pw, ph = w - ox - 14, h - oy - 24
    xmax = 610_000
    ymax = 45.0

    box(d, ox, oy, pw, ph, colors.HexColor("#FAFBFD"), colors.HexColor("#FAFBFD"), radius=0)
    for i in range(10):
        y = oy + ph * i / 9
        d.add(Line(ox, y, ox + pw, y, strokeColor=LINE, strokeWidth=0.35))
        txt(d, ox - 6, y - 3, f"{ymax * i / 9:.0f}", 7, MUTED, "end")
    for tick in range(0, 600_001, 100_000):
        x = ox + pw * tick / xmax
        d.add(Line(x, oy - 3, x, oy, strokeColor=MUTED, strokeWidth=0.6))
        txt(d, x, oy - 13, f"{tick // 1000}k", 7, MUTED, "middle")

    def hline(value: float, label: str, color) -> None:
        y = oy + ph * value / ymax
        d.add(Line(ox, y, ox + pw, y, strokeColor=color, strokeWidth=0.9, strokeDashArray=[3, 3]))
        txt(d, ox + 6, y + 5, label, 7.2, color)

    hline(GREEDY_STAGE2, "手書きの貪欲方策 (スロットルあり) 34.4", colors.HexColor("#7C8496"))
    hline(GREEDY_STAGE1, "手書きの貪欲方策 (速度一定) 28.5", colors.HexColor("#AAB1C0"))

    def plot(points, color, width):
        pts: list[float] = []
        for x, y in points:
            pts += [ox + pw * x / xmax, oy + ph * min(y, ymax) / ymax]
        d.add(PolyLine(pts, strokeColor=color, strokeWidth=width))
        d.add(Circle(pts[-2], pts[-1], 3.0, fillColor=color, strokeColor=colors.white,
                     strokeWidth=1.2))
        return pts

    p1 = plot(STAGE1, BLUE, 1.6)
    txt(d, p1[-2] + 6, p1[-1] - 3, "段階 1  行動 2 次元", 7.6, BLUE_D, bold=True)
    p2 = plot(STAGE2, PINK, 2.0)
    txt(d, p2[-2] - 6, p2[-1] + 8, "段階 2  行動 3 次元  37.7", 8, PINK, "end", bold=True)

    d.add(Line(ox, oy, ox + pw, oy, strokeColor=MUTED, strokeWidth=0.7))
    d.add(Line(ox, oy, ox, oy + ph, strokeColor=MUTED, strokeWidth=0.7))
    txt(d, ox, h - 11, "1 エピソード (60 秒) あたりのゲート通過数", 8, INK, bold=True)
    txt(d, ox + pw, oy - 28, "学習ステップ数", 7.5, MUTED, "end")
    return d


# --------------------------------------------------------------------------- page


def decorate(canvas, doc) -> None:
    canvas.saveState()
    canvas.setFont(FONT, 7.6)
    canvas.setFillColor(MUTED)
    canvas.drawString(MARGIN, 11 * mm, "Fly By 3D — 開発レポート")
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
    f.append(p("Fly By 3D", "title"))
    f.append(gap(4))
    f.append(
        p(
            "空中のリングを連続でくぐる 3D ゲーム — 人間も遊べて、AI も強化学習で上達する<br/>"
            "Godot 4.4 ＋ godot-rl ＋ Stable-Baselines3 ／ 2026 年 8 月 19 日",
            "subtitle",
        )
    )
    f.append(gap(12))

    if SHOT.exists():
        f.append(Image(str(SHOT), width=CONTENT_W, height=CONTENT_W * 648 / 1152))
        f.append(gap(5))
        f.append(
            p(
                "黄色いリングが次の目標、青がその先。左上の GATES が得点、SPD が現在の速度。"
                "この場面では曲がりきるために減速している (10.7 m/s)。",
                "caption",
            )
        )
    f.append(gap(12))

    f.append(
        table(
            [
                ["プレイヤー", "通過数 / 60 秒", "中身"],
                ["学習前の AI (ランダム)", "0.0", "何も学習していない初期方策。ただ墜落する"],
                ["手書きの貪欲方策", "34.4", "次のリングへ機首を向け、逸れたら減速するだけ"],
                ["PPO で 60 万ステップ学習した AI", "39.6", "本レポートで作った方策"],
            ],
            [56 * mm, 30 * mm, CONTENT_W - 86 * mm],
            center=[1],
        )
    )
    f.append(gap(7))
    f.append(
        p(
            "前作 Ball Collector 3D (球を転がして的を集めるゲーム) の骨組みを流用して作った 2 本目。"
            "同じリポジトリに両方が入っていて、起動時の引数だけで切り替わる。",
            "small",
        )
    )

    f.append(PageBreak())

    # ---------------------------------------------------------------- 1
    f.append(heading("1", "作ったもの"))
    f.append(gap(9))
    f.append(
        p(
            "機体を操縦して、60 秒で空中のリングを何個くぐれるかを競う 3D ゲーム。"
            "機体は<b>常に前進していて止まれない</b>。操作できるのは機首の向き (上下・左右) と速度だけで、"
            "リングは 1 個くぐるたびに次が前方に生成されるので、コースは事実上無限に続く。"
        )
    )
    f.append(gap(9))
    f.append(
        table(
            [
                ["要素", "内容"],
                ["ルール", "60 秒タイムアタック。リングをくぐると +1 点"],
                ["コース", "リングは常に 6 個先まで見える。くぐった端から前方へ置き直して使い回す"],
                ["操作", "W / S で機首上下、A / D で左右旋回、Shift でブレーキ"],
                ["速度", "8 〜 18 m/s。既定は全開で、Shift を押している間だけ減速する"],
                ["失敗", "地面に激突するかコース外へ出るとコースが作り直され、スタートに戻る"],
                ["カメラ", "機体を後方から追う。機首の向きに合わせて回る"],
                ["遊び方", "ブラウザ (Web ビルド) ／ Windows ネイティブ ／ コンテナ内で直接実行"],
            ],
            [28 * mm, CONTENT_W - 28 * mm],
        )
    )
    f.append(gap(11))
    f.append(
        callout(
            "このゲームの駆け引き",
            "旋回の角速度は飛行速度によらず一定にしてある。つまり<b>遅く飛ぶほど小回りが利く</b>。"
            "全開のまま急なカーブに入ると曲がりきれずにリングを外し、"
            "かといって減速しっぱなしでは数が稼げない。"
            "「どこで減速するか」がそのまま上手さになる、という 1 点に絞ったゲーム設計にした。",
        )
    )
    f.append(gap(13))

    f.append(sub("前作から引き継いだもの / 新しく作ったもの"))
    f.append(gap(6))
    f.append(
        table(
            [
                ["扱い", "対象"],
                [
                    "そのまま流用",
                    "学習スクリプト (train.py) ／ AI 観戦 (play_ai.py) ／ Godot 起動まわり ／ "
                    "godot-rl プラグイン。観測と行動の次元は Godot 側から渡るので、"
                    "ゲームが変わってもコードは 1 行も変えずに追従する",
                ],
                [
                    "共用できるよう手を入れた",
                    "学習シーン (train.gd) は並べるシーンをパラメータ化。"
                    "カメラ (world_view.gd) には機体追従モードを追加。"
                    "起動時の分岐 (boot.gd) は --game 引数でどちらのゲームかを選ぶ形にした",
                ],
                [
                    "新規に作成",
                    "機体 (drone) ／ リング (gate) ／ コース生成と報酬 (course) ／ "
                    "観測・行動・報酬の定義 (drone_ai_controller) ／ 人間プレイ用シーン ／ "
                    "基準値を測る手書き方策 (greedy_flyby.py)",
                ],
            ],
            [36 * mm, CONTENT_W - 36 * mm],
        )
    )
    f.append(gap(9))
    f.append(
        p(
            "前作は壊していない。ゲーム中に <b>G</b> キーを押すともう一方のゲームに切り替わり、"
            "学習も <b>--game ball</b> を付ければ前作のほうを回せる。",
            "small",
        )
    )

    f.append(PageBreak())

    # ---------------------------------------------------------------- 2
    f.append(heading("2", "設計で一番重要だった点 — 座標系"))
    f.append(gap(9))
    f.append(
        p(
            "前作と今作で決定的に違うのは、<b>何を基準に「前」と呼ぶか</b>。"
            "ここを外すと、人間が遊んでいるゲームと AI が学習しているゲームが別物になってしまう。"
        )
    )
    f.append(gap(9))
    f.append(
        table(
            [
                ["", "Ball Collector 3D (前作)", "Fly By 3D (今作)"],
                [
                    "制御の基準",
                    "ワールド座標系。W キーは常にワールドの -Z 方向へ転がす",
                    "機体ローカル座標系。W キーは「今向いている方向から見て上」",
                ],
                [
                    "カメラ",
                    "追従するが回転は固定。画面の奥が常にワールド -Z",
                    "機首の向きに合わせて回る。回さないと入力と見た目がズレる",
                ],
                [
                    "AI に渡す観測",
                    "ワールド座標のままでよい",
                    "すべて機体から見た向きに変換してから渡す",
                ],
            ],
            [22 * mm, (CONTENT_W - 22 * mm) / 2, (CONTENT_W - 22 * mm) / 2],
        )
    )
    f.append(gap(11))
    f.append(
        callout(
            "観測をローカル座標に直す理由",
            "たとえば「リングが自分の右 10m にある」という状況は、機体が北を向いていようが南を向いていようが、"
            "取るべき行動は同じ「右に曲がる」。ところがワールド座標のまま渡すと、"
            "この 2 つは (+10, 0, 0) と (-10, 0, 0) というまったく違う入力になり、"
            "AI は<b>同じ判断を機首の向きごとに別々に覚え直す</b>羽目になる。"
            "機体から見た向きに直しておけば、どちらも「右に 10m」という同一の入力になり、"
            "1 回学べば全方位で使える。学習の速さがここで大きく変わる。",
        )
    )
    f.append(gap(13))

    f.append(sub("機体の動かし方"))
    f.append(gap(6))
    f.append(
        p(
            "ピッチ角とヨー角を数値として持ち、毎フレームその 2 つから姿勢を組み立て直して、"
            "機首方向へ現在の速度で進ませている。"
            "物理エンジンに任せているのは位置の積分と当たり判定だけで、"
            "「トルクをかけて姿勢が安定するのを待つ」という作りにはしていない。"
            "そのぶん挙動が素直で、人間の操作感と AI の行動空間の意味が完全に一致する。"
        )
    )
    f.append(gap(6))
    f.append(
        p(
            "旋回時に機体が傾く (バンクする) のは<b>見た目だけ</b>で、進行方向には影響しない。"
            "オイラー角の適用順を YXZ にしてあるので、ロールは機首方向まわりの回転になり、"
            "向きを変えずに傾きだけを表現できる。",
        )
    )

    f.append(PageBreak())

    # ---------------------------------------------------------------- 3
    f.append(heading("3", "強化学習で何をしているのか"))
    f.append(gap(9))
    f.append(
        p(
            "使ったのは <b>強化学習</b>。"
            "「こう飛ぶのが正解」というお手本データは 1 件も与えていない。"
            "AI が自分で操縦してみて、点が入った動きの確率を上げ、"
            "墜落につながった動きの確率を下げる、という更新をひたすらくり返すだけ。"
        )
    )
    f.append(gap(11))
    f.append(rl_cycle_figure())
    f.append(gap(5))
    f.append(p("強化学習の基本ループ。この往復以外に情報は入ってこない。", "caption"))
    f.append(gap(13))

    f.append(sub("3-1  AI が見ているもの (観測 17 次元)"))
    f.append(gap(6))
    f.append(
        p(
            "画面は見せていない。渡しているのは下の 17 個の数値だけで、"
            "すべて機体から見た向きに直し、おおむね -1 〜 +1 の範囲に収めてある。"
        )
    )
    f.append(gap(9))
    f.append(obs_figure())
    f.append(gap(5))
    f.append(p("観測はこの 6 種類だけ。画像も、過去の記憶も渡していない。", "caption"))

    f.append(PageBreak())

    f.append(
        table(
            [
                ["観測", "次元", "なぜ必要か"],
                ["自機の速度", "3", "曲がりきれるかどうかは今の速度で決まる"],
                ["次のリングへの相対位置", "3", "どちらへ向かうべきかの主信号"],
                ["次のリングの法線", "3", "リングには表裏がある。どちら向きにくぐるべきかを示す"],
                ["その次のリングへの相対位置", "3", "次の次が見えると、手前で減速する判断ができる"],
                ["ワールド上方向 (機体から見た向き)", "3", "自分が今どれだけ傾いているかの手がかり"],
                ["次のリングまでの距離", "1", "近さそのものを明示的に渡す"],
                ["残り時間", "1", "固定長エピソードを正しく扱うために必要 (下記)"],
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
            "「まったく同じ状況なのに、あるときは続き、あるときは唐突に終わる」ものになり、"
            "『この状態はこの先どれくらい得点につながるか』という見積もり (価値関数) が"
            "正しく学習できない。"
            "残り時間を含めることで、いま見えている情報だけで先が決まる問題として"
            "きちんと閉じる (マルコフ決定過程になる)。前作で効果を確認済みだったので、今作でも最初から入れた。",
        )
    )
    f.append(gap(13))

    f.append(sub("3-2  AI が出すもの (行動 3 次元)"))
    f.append(gap(6))
    f.append(
        table(
            [
                ["行動", "範囲", "意味"],
                ["ピッチ指令", "-1 〜 +1", "+1 で機首上げ、-1 で機首下げ"],
                ["ヨー指令", "-1 〜 +1", "+1 で右旋回、-1 で左旋回"],
                ["スロットル指令", "-1 〜 +1", "-1 で 8 m/s、+1 で 18 m/s。加減速には時間がかかる"],
            ],
            [34 * mm, 26 * mm, CONTENT_W - 60 * mm],
            center=[1],
        )
    )
    f.append(gap(9))
    f.append(
        p(
            "人間がキーを押したときに作られる入力とまったく同じ形式で、同じ処理に渡される。"
            "行動を決めるのは 8 物理フレームに 1 回 (action repeat = 8) なので、"
            "1 エピソード 3,600 フレームに対して AI の意思決定は 450 回。"
            "毎フレーム決めるより学習が軽くなり、しかも意思決定の粒度としては十分だった"
            "(4 回に 1 回へ細かくしても成績は変わらなかった)。"
        )
    )
    f.append(gap(13))

    f.append(sub("3-3  報酬の設計"))
    f.append(gap(6))
    f.append(
        table(
            [
                ["事象", "報酬", "狙い"],
                ["リングをくぐった", "+1.0", "本来の目的そのもの"],
                ["墜落・コース外", "-1.0", "地面や場外へ突っ込む動きを抑える"],
                ["くぐらずに面を通り過ぎた", "-0.2", "「狙いを外した」ことを弱く伝える"],
                ["次のリングに近づいた", "近づいた距離 × 0.02", "学習の立ち上がりを速くする"],
            ],
            [42 * mm, 34 * mm, CONTENT_W - 76 * mm],
            center=[1],
        )
    )
    f.append(gap(11))
    f.append(
        callout(
            "距離シェーピングが決定的だった",
            "「くぐったら +1」だけだと、学習開始直後の AI は<b>偶然リングを通り抜けるまで何の手がかりも得られない</b>。"
            "でたらめに飛ぶ機体が直径 5m の輪を通る確率は低く、報酬がほぼ全ステップ 0 のまま時間だけが過ぎる。"
            "そこで「1 フレームで近づいた距離 × 0.02」を毎ステップ与えた。"
            "これで AI はまず『リングの方を向いて飛ぶ』を覚え、その延長として通過にたどり着く。"
            "実測でも 3 万ステップ付近から急に伸び始めており、ここが立ち上がりの起点になっている。",
        )
    )
    f.append(gap(11))
    f.append(
        callout(
            "シェーピングの落とし穴 — 目標が切り替わる瞬間",
            "リングを 1 つくぐると目標が次のリングに移るので、"
            "「目標までの距離」が 0m から 20m へ<b>一瞬で跳ね上がる</b>。"
            "何もしないと、この 1 フレームだけ『20m 遠ざかった』という巨大な罰が入り、"
            "AI は「リングをくぐると損をする」と学んでしまう。墜落してスタートに戻された瞬間も同じ。"
            "そこで通過・墜落の直後には必ず基準距離を取り直している。"
            "前作でも踏んだ罠で、今作では最初から対策を入れた。",
        )
    )

    f.append(gap(13))

    f.append(sub("3-4  学習アルゴリズム (PPO) が実際にやっていること"))
    f.append(gap(6))
    f.append(
        p(
            "アルゴリズムは <b>PPO (Proximal Policy Optimization)</b>。"
            "ニューラルネットは 64 × 64 の 2 層 MLP で、パラメータ数は数千しかない。"
            "「観測 17 個を入れると行動 3 個が出る」だけの小さな関数で、"
            "学習とはこの関数の重みを少しずつ動かしていく作業を指す。"
        )
    )
    f.append(gap(11))
    f.append(ppo_figure())
    f.append(gap(9))
    f.append(
        p(
            "ポイントは <b>3 の「少しだけ動かす」</b>。"
            "たまたま上手くいった経験に飛びついて方策を大きく書き換えると、"
            "それまでできていたことまで壊れて成績が崩壊する。"
            "PPO は 1 回の更新で行動確率が 20% 以上変わらないように制限をかけることで、"
            "この崩壊を防いでいる。名前の Proximal (近い) はこの制限のこと。"
        )
    )
    f.append(gap(13))

    f.append(sub("3-5  学習を速くするための仕掛け"))
    f.append(gap(6))
    f.append(loop_figure())
    f.append(gap(9))
    f.append(
        p(
            "強化学習は「とにかく大量に試す」ことが必要なので、"
            "試行を集める速さがそのまま学習時間になる。次の 3 つで速くしている。"
        )
    )
    f.append(gap(6))
    f.append(
        table(
            [
                ["手段", "内容", "効果"],
                [
                    "コースを並べる",
                    "1 プロセスの中に独立したコースを 16 面置き、16 体を同時に飛ばす",
                    "1 回の通信で 16 体ぶんの経験",
                ],
                [
                    "プロセスを増やす",
                    "その Godot を 3 個起動して合計 48 体",
                    "CPU コアを使い切る",
                ],
                [
                    "物理を早送り",
                    "描画しないので実時間に縛られる理由がない。物理を 40 倍速で回す",
                    "60 秒のプレイが 1.5 秒",
                ],
            ],
            [30 * mm, CONTENT_W - 68 * mm, 38 * mm],
        )
    )
    f.append(gap(9))
    f.append(
        p(
            "この構成で Godot 側は約 4,200 steps/s、PPO の勾配計算を含めた実効で約 2,950 steps/s。"
            "60 万ステップ ＝ AI が 1,300 回ぶんの 60 秒を体験する量が、CPU だけで <b>約 3.4 分</b>で終わる。",
            "small",
        )
    )
    f.append(gap(13))

    f.append(sub("3-6  学習の設定値"))
    f.append(gap(6))
    f.append(
        table(
            [
                ["項目", "値", "選んだ理由"],
                ["方策ネットワーク", "64 × 64 MLP", "観測が 17 次元しかないので、これで十分足りる"],
                ["学習率", "3e-4", "PPO の標準値。触る必要が無かった"],
                ["割引率 γ", "0.99", "60 秒先まで見通せるように長めに取る"],
                ["GAE λ", "0.95", "標準値。行動の良し悪しの見積もりを安定させる"],
                ["ロールアウト長 / バッチ", "64 / 256", "48 体ぶんを 1 回の更新にまとめる"],
                ["更新の反復", "10 epoch", "集めた経験を 10 周使ってから捨てる"],
                ["クリップ幅", "0.2", "1 回の更新で方策が 20% 以上変わらないようにする"],
                ["エントロピー係数", "0.001", "探索を少しだけ残し、序盤で動きが固まるのを防ぐ"],
                ["action repeat", "8", "60Hz の物理に対し、意思決定は 7.5Hz"],
                ["同時実行エージェント数", "48", "16 コース × 3 プロセス"],
                ["物理の倍速", "40 倍", "描画しないので実時間より速く回せる"],
            ],
            [40 * mm, 26 * mm, CONTENT_W - 66 * mm],
            center=[1],
        )
    )

    f.append(gap(15))

    # ---------------------------------------------------------------- 4
    f.append(heading("4", "実際にどう上達したか"))
    f.append(gap(9))
    f.append(
        p(
            "指示書の方針に従い、<b>いきなり全部の操作を与えず 2 段階に分けて</b>作った。"
            "段階 1 は速度一定でピッチとヨーだけ (行動 2 次元)。"
            "それが動くのを確認してから、段階 2 でスロットルを足した (行動 3 次元)。"
            "下が両方の実測カーブ。"
        )
    )
    f.append(gap(9))
    f.append(curve_figure())
    f.append(gap(5))
    f.append(p("学習中の実測ログから作成。破線は比較用に書いた手書き方策の成績。", "caption"))
    f.append(gap(13))

    f.append(sub("何を覚えていったか (段階 2 の場合)"))
    f.append(gap(6))
    f.append(
        table(
            [
                ["段階", "通過数", "見て分かる変化"],
                ["学習前", "0.0", "でたらめに機首を振り、そのまま地面か場外へ突っ込む"],
                ["1 万ステップ", "0.0", "まだ 1 個も通れない。ここで距離シェーピングが効き始める"],
                ["5 万ステップ", "1.2", "リングの方を向いて飛ぶようになる。通るのはまだ偶然"],
                ["9 万ステップ", "9.7", "狙って通り始める。速度は出しっぱなしで曲がりきれず外す"],
                ["17 万ステップ", "29.7", "手書き方策 (速度一定) に並ぶ。墜落がほぼ無くなる"],
                ["21 万ステップ", "34.6", "カーブの手前で減速するようになり、手書き方策を抜く"],
                ["45 万ステップ", "38.2", "減速の量と再加速のタイミングが洗練される。ほぼ頭打ち"],
            ],
            [28 * mm, 18 * mm, CONTENT_W - 46 * mm],
            center=[1],
        )
    )
    f.append(gap(11))
    f.append(
        p(
            "※ グラフの 37.7 は学習中 (方策からサンプリングして探索している状態) の平均。"
            "学習を止めて決定論的に動かすと <b>39.6 個</b> (最高 42 個) になる。",
            "small",
        )
    )
    f.append(gap(11))
    f.append(
        callout(
            "段階 1 と段階 2 の差が示していること",
            "段階 1 (速度一定) では AI 31.3 に対し手書き方策 28.5 で、差はわずかだった。"
            "このゲームは「次の目標へ真っ直ぐ向かう」だけでかなりのところまで行けるので、当然ではある。"
            "ところがスロットルを与えた段階 2 では、AI 39.6 に対し手書き 34.4 と差が開いた。"
            "AI が上回っているぶんの中身は、ほぼ<b>速度の使い分け</b>。"
            "「次の次のリング」を観測に入れてあるので、まだ見えていないカーブのきつさを先読みして"
            "手前から緩めておく、という単純な追尾では出てこない振る舞いが現れた。"
            "これは報酬として明示的に教えたものではなく、報酬を最大化した結果として出てきている。",
        )
    )

    f.append(gap(15))

    # ---------------------------------------------------------------- 5
    f.append(heading("5", "どう検証しながら作ったか"))
    f.append(gap(9))
    f.append(
        p(
            "強化学習を含むものは「動いていないのか、下手なだけなのか」の区別が付きにくい。"
            "そこで前作で有効だった順序をそのまま踏襲し、"
            "<b>学習を始める前に配線ミスを潰しきる</b>ことを優先した。"
        )
    )
    f.append(gap(9))
    f.append(
        table(
            [
                ["順序", "やったこと", "そこで潰せるもの"],
                ["1", "ヘッドレスで読み込み、パースエラーを消す", "構文・シーン構成の誤り"],
                ["2", "300 フレームだけ実行してエラーを消す", "実行時の型・参照の誤り"],
                [
                    "3",
                    "手書きの貪欲方策でスコアを測る",
                    "観測と行動の向き (符号) の誤り。ここが最重要",
                ],
                ["4", "2 〜 3 万ステップだけ学習してみる", "Python と Godot の接続、報酬の流れ"],
                ["5", "本番の学習を回す", "—"],
            ],
            [14 * mm, 62 * mm, CONTENT_W - 76 * mm],
            center=[0],
        )
    )
    f.append(gap(11))
    f.append(
        callout(
            "手書きの方策を先に書く理由",
            "「観測から次のリングの方向を読み、そちらへ機首を向ける」だけの十数行のコードを先に書いて回す。"
            "これが 2 つの役に立つ。<br/>"
            "1 つは<b>物差し</b>。34.4 という基準があって初めて、学習結果の 39.6 が"
            "「上手い」のか「その程度か」を判断できる。基準が無いと数字を見ても意味が分からない。<br/>"
            "2 つめは<b>符号の検査</b>。もし観測の左右や上下を取り違えていれば、"
            "この方策はリングから遠ざかる方向へ飛ぶのでスコアがほぼ 0 になる。"
            "学習を回す前に、たった数分で向きの間違いが露見する。",
        )
    )
    f.append(gap(13))

    f.append(sub("見た目の確認"))
    f.append(gap(6))
    f.append(
        p(
            "コンテナには画面が無く、X11 転送は遅いうえに操作者の画面にウィンドウが出てしまう。"
            "そこで人間プレイ用シーンを継承した使い捨てシーンを作り、"
            "貪欲方策で自動操縦しながら一定フレームごとに PNG を保存して、それを見る形にした。"
            "確認が済んだら捨てている。このレポートの写真もその方法で撮ったもの。"
        )
    )
    f.append(gap(9))
    if SHOT_PASS.exists():
        f.append(Image(str(SHOT_PASS), width=CONTENT_W * 0.82, height=CONTENT_W * 0.82 * 648 / 1152))
        f.append(gap(5))
        f.append(p("リングを通過する瞬間。当たり判定はリングの穴の部分だけに置いてある。", "caption"))

    f.append(PageBreak())

    # ---------------------------------------------------------------- 6
    f.append(heading("6", "人間と AI が同じゲームを遊んでいること"))
    f.append(gap(9))
    f.append(
        p(
            "学習した方策を別物として横に置くのではなく、"
            "<b>人間が遊ぶときとまったく同じコードを通す</b>ように作ってある。"
            "入力元を切り替えるだけで、物理・ルール・エピソード長はすべて共通の経路を通る。"
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
                    "人間の 60 秒と AI の 60 秒が同じ長さであることを、"
                    "AIController の reset_after (3,600 物理フレーム) を唯一の基準にすることで保証している。"
                    "だから「AI は 39.6 個くぐれる」が、そのまま人間の目標値になる",
                ],
                [
                    "AI のプレイを観られる",
                    "python tools/play_ai.py で、学習済みの方策が実際に飛ぶ様子をウィンドウで見られる。"
                    "上達の中身 (どこで減速しているか) を目で確認できる",
                ],
                [
                    "ゲームバランスが学習で検証された",
                    "AI が 60 秒で約 40 個くぐれる ＝ リング間隔・旋回速度・速度域の組み合わせが"
                    "「詰まらずに飛び続けられる」設定になっていることの裏付けになった",
                ],
                [
                    "設定値の二重管理が起きない",
                    "リング間隔やコースの広さといった「人間側と AI 側の両方が知る必要のある値」は"
                    "ゲーム側に 1 つだけ置き、AI は観測として受け取る。"
                    "バランスを変えても学習コードを直す必要がない",
                ],
            ],
            [38 * mm, CONTENT_W - 38 * mm],
        )
    )

    f.append(PageBreak())

    # ---------------------------------------------------------------- 7
    f.append(heading("7", "つまずいた点と、どう回避したか"))
    f.append(gap(9))
    f.append(
        table(
            [
                ["問題", "対処"],
                [
                    "目標が切り替わる瞬間に巨大な偽の報酬が出る",
                    "リング通過・墜落の直後は「目標までの距離」が不連続に跳ぶ。"
                    "そのままだと成功したのに罰が入る。"
                    "切り替えの直後に基準距離を取り直すことで解消した。"
                    "しかも墜落直後は物理サーバー上の位置がまだ更新されていないため、"
                    "機体の現在位置ではなく<b>これから戻す予定の位置</b>から計算する必要があった",
                ],
                [
                    "RigidBody3D を思ったとおりに動かせない",
                    "座標を直接代入しても物理サーバーに無視されることがある。"
                    "姿勢と速度は物理サーバーの状態を直接書き換える形にした。"
                    "また、動きが止まると物理エンジンがスリープさせてしまうため、これも無効にしている",
                ],
                [
                    "Godot 単体で学習済みモデルを動かせない",
                    "godot-rl の ONNX 推論部は C# 実装で、この環境の Godot は非 .NET ビルドだった。"
                    "そこで「Python が推論し、Godot が描画する」構成にした。"
                    "将来 .NET ビルドへ移れるよう .onnx も出力してある",
                ],
                [
                    "学習ログに「何個くぐれたか」が出せない",
                    "godot_rl 0.8.1 が、Godot から届いた付加情報を読み捨てていた。"
                    "受け取り側を差し替えて通し、報酬ではなく通過数で進捗を見られるようにした。"
                    "報酬は距離シェーピングを含むので直感的に読めず、これは重要だった",
                ],
                [
                    "複数プロセスで学習を回せない",
                    "本家のラッパーが「実行ファイルが無いなら複数プロセス不可」と決め打ちしていた。"
                    "自前で Godot を起動して接続する形にして 48 体並列を実現した",
                ],
                [
                    "コンテナ内のプレイが 25fps しか出ない",
                    "描画自体 (CPU ソフトウェア描画) は 65fps 出ており、"
                    "遅いのは X11 のフレーム転送だと実測で切り分けた。"
                    "Web ビルドを用意し、ブラウザでのプレイを推奨する形にした",
                ],
            ],
            [42 * mm, CONTENT_W - 42 * mm],
        )
    )

    f.append(PageBreak())

    # ---------------------------------------------------------------- 8
    f.append(heading("8", "実測値と動かし方"))
    f.append(gap(9))
    f.append(sub("性能 (CPU 12 コア / RAM 7GB / GPU 無し)"))
    f.append(gap(6))
    f.append(
        table(
            [
                ["項目", "実測値"],
                ["学習スループット (Godot 側のみ、16 コース × 3 プロセス、40 倍速)", "約 4,200 steps/s"],
                ["PPO の更新を含めた実効速度", "約 2,950 steps/s"],
                ["60 万ステップの学習時間 (CPU のみ)", "約 3.4 分"],
                ["メモリ (Godot ヘッドレス 1 プロセス ／ Python 側)", "85 MB ／ 672 MB"],
                ["描画 FPS (ローカル、1152 × 648)", "65.3 fps"],
                ["描画 FPS (X11 転送、1152 × 648)", "12.0 fps"],
            ],
            [CONTENT_W - 40 * mm, 40 * mm],
            center=[1],
        )
    )
    f.append(gap(9))
    f.append(
        callout(
            "学習中は CPU を数分間フルに使う",
            "Godot ヘッドレス 3 プロセス (物理 40 倍速) と PyTorch の勾配計算が同時に走るため、"
            "12 コアがほぼ 100% になり PC が熱くなる。CPU ベンチマークを回しているのと同じ負荷。"
            "温度自体は CPU 側が自動でクロックを落として守るが、"
            "負荷を下げたいときは --parallel 1 --arenas 8 --speedup 10 を付けると 1/6 程度になる"
            "(そのぶん時間はかかる)。",
        )
    )
    f.append(gap(13))

    f.append(sub("動かし方"))
    f.append(gap(6))
    f.append(
        table(
            [
                ["やりたいこと", "コマンド"],
                ["ブラウザで遊ぶ", "python tools/serve_web.py → http://localhost:8000 を開く"],
                ["AI を学習させる", "python tools/train.py --steps 600000"],
                ["AI のプレイを観る", "python tools/play_ai.py"],
                ["AI のスコアだけ測る", "python tools/play_ai.py --headless --episodes 10"],
                ["手書き方策の基準値を測る", "python tools/greedy_flyby.py --episodes 8"],
                ["前作 (Ball Collector) を動かす", "上記に --game ball を付ける"],
            ],
            [42 * mm, CONTENT_W - 42 * mm],
        )
    )
    f.append(gap(13))

    f.append(sub("次にやるとしたら"))
    f.append(gap(6))
    f.append(
        p(
            "<b>本格的な姿勢制御</b> — 今の機体はピッチとヨーを直接指定する簡易モデルで、"
            "ロールは見た目だけ。角速度ではなくトルクを指令する 4 次元の行動にすると"
            "本物の飛行機に近い操縦になるが、収束には 30 分以上かかると見込まれる。<br/>"
            "<b>障害物と周辺認識</b> — プラグイン同梱のレイキャストセンサーを観測に足せば、"
            "コース上の障害物を避ける行動まで学習できる。<br/>"
            "<b>サバイバルモード</b> — リングをくぐると残り時間が回復するルール。"
            "コース側の変更だけで済む。"
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
        title="Fly By 3D 開発レポート",
        author="Fly By 3D",
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
