# Zenn 記事

`articles/fly-by-3d.md` が本体。**そのままコピーして Zenn の投稿画面に貼れば公開できる。**

## 画像について

記事中の画像はすべて GitHub Pages の絶対 URL を指している。

```
https://ms022019.github.io/fly-by-3d/img/*.png
```

つまり **Zenn 側への画像アップロードは不要**。貼り付けた時点で表示される。

Zenn の画像アップローダを使いたい場合は、`images/` に同じ PNG が置いてあるので、
アップロード後に記事中の URL を差し替える。

## 公開するとき

1. `articles/fly-by-3d.md` の中身をコピー
2. Zenn の「新しい記事を作成」に貼る
3. フロントマターの `published: false` を `true` にする

zenn-cli を使う場合は、この `zenn/` の中身をそのまま Zenn 用リポジトリの
ルートに置けば `npx zenn preview` で確認できる (articles/ と images/ の構成に合わせてある)。

## PDF 版

同じ Markdown から PDF も作れる。記事を直したらこれを実行し直せば追従する。

```bash
python tools/make_article_pdf.py    # -> docs/FlyBy3D_article_ja.pdf
```

記事中の画像は GitHub Pages の URL を指しているが、PDF では取りに行かず
`images/` のローカルファイルを使う (ファイル名で対応付けている)。

**画面写真は PDF だけ明るいテーマの版に差し替わる。** 紙に刷ると黒ベタが
汚れるため。`images/light/` に同名のファイルがあればそちらが優先される。
撮り直すときは `--light` を付けて起動する。

```bash
xvfb-run -s "-screen 0 1280x720x24" godot --path game --resolution 1152x648 --light
```

## 画像を作り直すとき

図はレポート生成スクリプトの関数をそのまま呼んで書き出している。

```bash
pip install reportlab pymupdf
python - <<'PY'
import sys, io
sys.path.insert(0, "tools")
from reportlab.graphics import renderPDF
from reportlab.graphics.shapes import Drawing, Rect
from reportlab.lib import colors
import pymupdf, make_report as base, make_report_flyby as r

base.ensure_font()
base.S.update(base.styles())
for name, make in {"curve": r.curve_figure, "ghost": r.ghost_figure}.items():
    d = make()
    out = Drawing(d.width + 28, d.height + 28)
    out.add(Rect(0, 0, out.width, out.height, fillColor=colors.white, strokeColor=None))
    d.translate(14, 14)
    out.add(d)
    buf = io.BytesIO()
    renderPDF.drawToFile(out, buf, "fig")
    pymupdf.open(stream=buf.getvalue(), filetype="pdf")[0].get_pixmap(dpi=170).save(
        f"zenn/images/fig_{name}.png"
    )
PY
```

書き出したら gh-pages ブランチの `img/` にコピーして push する。
