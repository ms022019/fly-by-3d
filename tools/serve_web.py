"""Web ビルドを配信する簡易 HTTP サーバー。

コンテナ内では X11 転送がボトルネックになり 25fps 程度しか出ないため、
ブラウザ (ホスト側の実 GPU) で動かすのがいちばん快適に遊べる。

    python tools/serve_web.py
    -> VS Code がポートを転送するので、ホストのブラウザで http://localhost:8000 を開く
"""

from __future__ import annotations

import argparse
import functools
import http.server
import socketserver
from pathlib import Path

BUILD_DIR = Path(__file__).resolve().parent.parent / "build" / "web"


class GodotWebHandler(http.server.SimpleHTTPRequestHandler):
    """Godot の Web ビルドを配信するための最小限の調整を入れたハンドラ。"""

    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript",
    }

    def end_headers(self) -> None:
        # 今回のビルドはスレッド無効なので必須ではないが、
        # 将来 thread_support を有効にすると SharedArrayBuffer に
        # これらのヘッダが要求されるため、最初から付けておく。
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt: str, *args) -> None:
        print(f"  {self.address_string()} - {fmt % args}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--dir", type=Path, default=BUILD_DIR)
    args = parser.parse_args()

    if not (args.dir / "index.html").exists():
        raise SystemExit(
            f"web build not found in {args.dir}\n"
            'Run:  godot --headless --path game --export-release "Web" ../build/web/index.html'
        )

    handler = functools.partial(GodotWebHandler, directory=str(args.dir))
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("0.0.0.0", args.port), handler) as httpd:
        print(f"serving {args.dir} on http://localhost:{args.port}  (Ctrl+C to stop)", flush=True)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nstopped")


if __name__ == "__main__":
    main()
