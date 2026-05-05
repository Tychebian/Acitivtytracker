#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  build_release.sh — 构建 ActivityTracker macOS 发布包
#  产出：dist/ActivityTracker-vX.X.X.dmg
# ─────────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── 读取版本号 ──────────────────────────────────────────────
PYTHON_BIN="$(which python3)"
VERSION=$("$PYTHON_BIN" -c \
  "import sys; sys.path.insert(0,'$SCRIPT_DIR'); from config import __version__; print(__version__)")
echo "==> 版本：v${VERSION}"

APP_NAME="ActivityTracker"
BUNDLE_NAME="${APP_NAME}.app"
RELEASE_NAME="${APP_NAME}-v${VERSION}"
DIST_DIR="$SCRIPT_DIR/dist"
STAGE_DIR="$DIST_DIR/${RELEASE_NAME}"
DMG_PATH="$DIST_DIR/${RELEASE_NAME}.dmg"

# ── 清理旧产物 ──────────────────────────────────────────────
echo "==> 清理旧产物..."
rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"

# ── 构建 App Bundle ─────────────────────────────────────────
echo "==> 构建 App Bundle..."
APP_DIR="$STAGE_DIR/$BUNDLE_NAME"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

mkdir -p "$MACOS_DIR" "$RES_DIR"

# Info.plist（含版本号）
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>             <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>      <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>       <string>com.tychebian.activitytracker</string>
  <key>CFBundleVersion</key>          <string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleIconFile</key>         <string>AppIcon</string>
  <key>CFBundlePackageType</key>      <string>APPL</string>
  <key>CFBundleSignature</key>        <string>????</string>
  <key>LSMinimumSystemVersion</key>   <string>12.0</string>
  <key>NSHighResolutionCapable</key>  <true/>
  <key>LSUIElement</key>              <true/>
</dict>
</plist>
PLIST

# 图标
if [ -f "$SCRIPT_DIR/ActivityTracker.app/Contents/Resources/AppIcon.icns" ]; then
  cp "$SCRIPT_DIR/ActivityTracker.app/Contents/Resources/AppIcon.icns" "$RES_DIR/"
fi

# Python 源码 → Resources
for f in tracker.py main_app.py dashboard.py db.py config.py \
          dialog_helper.py native_dialog.py requirements.txt; do
  [ -f "$SCRIPT_DIR/$f" ] && cp "$SCRIPT_DIR/$f" "$RES_DIR/"
done
cp -r "$SCRIPT_DIR/templates" "$RES_DIR/"

# Launcher 脚本（Contents/MacOS/ActivityTracker）
cat > "$MACOS_DIR/$APP_NAME" << 'LAUNCHER'
#!/bin/bash
# ActivityTracker launcher — 从 app bundle 内 Resources 启动
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RESOURCES="$SCRIPT_DIR/../Resources"

# 探测含有 rumps / flask 的 Python
PYTHON=""
for _py in \
    "/opt/anaconda3/bin/python3" \
    "/opt/homebrew/bin/python3" \
    "/usr/local/bin/python3" \
    "$(which python3 2>/dev/null)"; do
  [ -z "$_py" ] || [ ! -f "$_py" ] && continue
  if "$_py" -c "import rumps, flask" 2>/dev/null; then
    PYTHON="$_py"; break
  fi
done

if [ -z "$PYTHON" ]; then
  osascript -e 'display dialog "未找到已安装 rumps / flask 的 Python 环境。\n\n请先运行 DMG 中的「安装 ActivityTracker.command」来自动配置环境。" buttons {"好的"} default button "好的" with icon stop'
  exit 1
fi

exec "$PYTHON" "$RESOURCES/main_app.py"
LAUNCHER

chmod +x "$MACOS_DIR/$APP_NAME"
echo "   App Bundle 构建完成：$APP_DIR"

# ── 安装脚本（双击可运行的 .command）──────────────────────
echo "==> 生成安装脚本..."
cat > "$STAGE_DIR/安装 ActivityTracker.command" << INSTALL_SCRIPT
#!/bin/bash
# ────────────────────────────────────────────────────────────
#  ActivityTracker 一键安装脚本
#  双击运行，Terminal 会自动打开并完成安装
# ────────────────────────────────────────────────────────────
set -e

DMG_DIR="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" && pwd )"
APP_SOURCE="\$DMG_DIR/ActivityTracker.app"
INSTALL_DIR="\$HOME/Applications"
APP_DEST="\$INSTALL_DIR/ActivityTracker.app"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║    ActivityTracker v${VERSION} 安装程序     ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── 1. 找 Python ────────────────────────────────────────────
echo "▶ 检查 Python 环境..."
PYTHON=""
for _py in \
    "/opt/anaconda3/bin/python3" \
    "/opt/homebrew/bin/python3" \
    "/usr/local/bin/python3" \
    "\$(which python3 2>/dev/null)"; do
  [ -z "\$_py" ] || [ ! -f "\$_py" ] && continue
  if "\$_py" -c "import sys; assert sys.version_info >= (3,10)" 2>/dev/null; then
    PYTHON="\$_py"; break
  fi
done

if [ -z "\$PYTHON" ]; then
  echo "✗ 未找到 Python 3.10+。"
  echo "  请从 https://www.python.org 下载安装后重试。"
  osascript -e 'display dialog "未找到 Python 3.10+。\n请先安装 Python，再重新运行此脚本。" buttons {"好的"} default button "好的" with icon stop' 2>/dev/null || true
  exit 1
fi
echo "  使用 Python：\$PYTHON"

# ── 2. 安装依赖 ─────────────────────────────────────────────
echo ""
echo "▶ 安装 Python 依赖包（首次约需 1-2 分钟）..."
"\$PYTHON" -m pip install --quiet --upgrade pip
"\$PYTHON" -m pip install --quiet rumps flask pyobjc-framework-WebKit
echo "  依赖安装完成 ✓"

# ── 3. 复制 App ─────────────────────────────────────────────
echo ""
echo "▶ 安装 ActivityTracker.app 到 ~/Applications..."
mkdir -p "\$INSTALL_DIR"
rm -rf "\$APP_DEST"
cp -r "\$APP_SOURCE" "\$INSTALL_DIR/"
echo "  App 已安装 ✓"

# ── 4. 注册开机自启（LaunchAgent）──────────────────────────
echo ""
echo "▶ 配置开机自启..."
RESOURCES="\$APP_DEST/Contents/Resources"
PLIST="\$HOME/Library/LaunchAgents/com.activitytracker.tracker.plist"
LOG_DIR="\$HOME/.activity_tracker"
mkdir -p "\$LOG_DIR" "\$HOME/Library/LaunchAgents"

cat > "\$PLIST" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key>
  <string>com.activitytracker.tracker</string>
  <key>ProgramArguments</key>
  <array>
    <string>\$PYTHON</string>
    <string>\$RESOURCES/tracker.py</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key>
  <string>\$LOG_DIR/error.log</string>
  <key>StandardOutPath</key>
  <string>\$LOG_DIR/output.log</string>
</dict></plist>
PLIST_EOF

launchctl unload "\$PLIST" 2>/dev/null || true
launchctl load "\$PLIST"
echo "  开机自启已配置 ✓"

# ── 5. 首次启动 ─────────────────────────────────────────────
echo ""
echo "▶ 启动 ActivityTracker..."
open "\$APP_DEST"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  安装完成！                                          ║"
echo "║                                                      ║"
echo "║  • 菜单栏右上角出现 ⏱ 图标即表示运行正常            ║"
echo "║  • 每次登录 Mac 后自动启动                          ║"
echo "║  • 如需卸载，运行：                                  ║"
echo "║    launchctl unload ~/Library/LaunchAgents/          ║"
echo "║               com.activitytracker.tracker.plist      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

osascript -e 'display dialog "ActivityTracker 安装完成！\n\n菜单栏右上角出现 ⏱ 图标即表示运行正常。\n每次登录后将自动启动。" buttons {"好的"} default button "好的"' 2>/dev/null || true

INSTALL_SCRIPT

chmod +x "$STAGE_DIR/安装 ActivityTracker.command"
echo "   安装脚本生成完成"


# ── 构建 DMG ────────────────────────────────────────────────
echo "==> 构建 DMG..."

hdiutil create \
  -volname "${APP_NAME} v${VERSION}" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" \
  -quiet

# ── 完成 ────────────────────────────────────────────────────
DMG_SIZE=$(du -sh "$DMG_PATH" | awk '{print $1}')
echo ""
echo "╔══════════════════════════════════════════════════════╗"
printf  "║  ✓ 打包完成                                          ║\n"
printf  "║    文件：%-43s║\n" "dist/${RELEASE_NAME}.dmg"
printf  "║    大小：%-43s║\n" "${DMG_SIZE}"
echo "║                                                      ║"
echo "║  上传步骤：                                          ║"
echo "║  1. 打开 GitHub → Releases → Create new release      ║"
echo "║  2. 选择 Tag: v${VERSION}                                ║"
echo "║  3. 将 .dmg 文件拖入上传区域                         ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
