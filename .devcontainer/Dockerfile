FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Godot 4.4 stable（Linux標準バイナリ＋--headlessフラグでサーバー運用）
# ※ Godot 4.x では server/headless 専用バイナリは廃止され、全バイナリが --headless で動く
ARG GODOT_VERSION=4.4-stable
# libxkbcommon: ウィンドウ実行時のキーボード入力に必須 (無いと入力を取りこぼす)
# libdbus-1-3 : 起動時のエラーログを消すため
# xvfb        : X11 転送を介さないローカル描画 (ベンチや録画用)
RUN apt-get update && apt-get install -y --no-install-recommends \
      wget unzip ca-certificates \
      libgl1 libxrandr2 libxinerama1 libxcursor1 libxi6 libasound2t64 \
      libxkbcommon0 libxkbcommon-x11-0 libdbus-1-3 xvfb \
    && wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" -O /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /tmp/godot \
    && mv "/tmp/godot/Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm -rf /tmp/godot* /var/lib/apt/lists/*