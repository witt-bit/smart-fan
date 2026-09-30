#!/usr/bin/env bash
#
# SmartFan — developer and maintenance entry point.
#
# Everything the project needs day to day lives here: build, run, test, install,
# uninstall, package, diagnose. One script, so a contributor — or the maintainer,
# who need not read Swift — has a single thing to learn.
#
#   scripts/setup.sh                 usage
#   scripts/setup.sh install         build + assemble + install + open
#   scripts/setup.sh test            unit + socket + packaging checks
#   scripts/setup.sh doctor          what is installed, and what is wrong
#
# Deliberately Bash 3.2 compatible (macOS ships 3.2 as /bin/bash): no associative
# arrays, no ${var,,}. Safe to run from any directory.

set -euo pipefail
cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"

SCRIPT_VERSION="1.0"

# Global options, set by the dispatch loop below.
VERBOSE=0
ASSUME_YES=0

APP_NAME="SmartFan"
APP_DEST="/Applications/${APP_NAME}.app"
HELPER="/Library/PrivilegedHelperTools/org.witt.smartfan.helper"
DAEMON_LABEL="org.witt.smartfan.daemon"
PLIST="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
SOCKET="/var/run/smart-fan.sock"
BUNDLED_CLI_REL="Contents/MacOS/smart-fan"
DEVELOPER_DIR_PLUGINS="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

if [ -t 1 ]; then
    C_DIM=$'\033[2m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_OFF=$'\033[0m'
else
    C_DIM=""; C_OK=""; C_WARN=""; C_ERR=""; C_OFF=""
fi

say() { printf '%s\n' "$*"; }
dim() { printf '%s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }
step() { printf '\n%s->%s %s\n' "$C_DIM" "$C_OFF" "$*"; }
ok() { printf '%s[ok]%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
die() { printf '%s[x]%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "找不到命令 '$1'。$2"
}

# SwiftPM hands the linker -F/-L paths that exist only under a full Xcode. With the
# CommandLineTools selected, ld warns once per missing path:
#   ld: warning: search path '/Library/Developer/CommandLineTools/Developer/...' not found
# That says nothing about this project, so it is dropped. Every other line passes
# through, and a real linker error is not a "search path" warning.
filter_toolchain_noise() {
    # `|| true`: grep -v exits 1 when it outputs nothing, which under `set -e` would
    # abort a successful build whose only stderr was this noise.
    grep -v -E "ld: warning: search path '.*' not found" || true
}

# Run a swift command with its stderr buffered so the linker noise can be dropped.
# stdout (build progress) still streams. Returns the command's own status.
run_swift() {
    local log status=0
    log="$(mktemp "${TMPDIR:-/tmp}/smart-fan-swift.XXXXXX")"
    if ! "$@" 2>"$log"; then status=1; fi
    filter_toolchain_noise <"$log" >&2
    rm -f "$log"
    return $status
}

# Ask before something destructive. Honours --yes.
confirm() {
    [ "$ASSUME_YES" = 1 ] && return 0
    printf '%s%s [y/N] %s' "$C_WARN" "$1" "$C_OFF"
    read -r reply || true
    case "$reply" in [yY] | [yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# The app's version, read from its single source of truth — no build required.
app_version() {
    sed -n 's/.*public static let current = "\([^"]*\)".*/\1/p' \
        "$REPO_ROOT/Sources/SmartFanCore/Version.swift" | head -1
}

bin_dir() { swift build -c "$1" --show-bin-path; }

built_app() { echo "$(bin_dir "$1")/${APP_NAME}.app"; }

is_installed() { [ -d "$APP_DEST" ] || [ -x "$HELPER" ]; }

is_app_running() { pgrep -x "${APP_NAME}App" >/dev/null 2>&1; }

# `swift test` on a CommandLineTools-only toolchain cannot find the Swift Testing
# macros unless the plugin path is passed. Xcode does not need it, so it is added
# only when that directory exists.
swift_test_args() {
    if [ -d "$DEVELOPER_DIR_PLUGINS" ]; then
        printf '%s\n' -Xswiftc -plugin-path -Xswiftc "$DEVELOPER_DIR_PLUGINS"
    fi
}

# ---------------------------------------------------------------------------
# Build steps shared by several commands
# ---------------------------------------------------------------------------

run_build() { # <debug|release>
    require_cmd swift "请先安装 Xcode 命令行工具：xcode-select --install"
    step "编译 ($1)"
    if [ "$VERBOSE" = 1 ]; then
        run_swift swift build -c "$1"
    else
        # Building here is a step on the way to something else, so stdout progress
        # is dropped too (stderr is filtered and kept).
        run_swift swift build -c "$1" >/dev/null
    fi
}

ensure_icon() {
    [ -f "$REPO_ROOT/${APP_NAME}.icns" ] && return 0
    step "生成图标"
    require_cmd iconutil "图标工具缺失，请安装 Xcode 命令行工具。"
    swift "$REPO_ROOT/scripts/generate-icon.swift"
    iconutil -c icns "$REPO_ROOT/${APP_NAME}.iconset" -o "$REPO_ROOT/${APP_NAME}.icns"
}

# Assemble + ad-hoc sign the bundle, embedding the CLI/daemon binary so the app
# installs the background service from its own copy (never a download).
assemble_app() { # <debug|release>
    local cfg="$1" bin dest
    bin="$(bin_dir "$cfg")"
    dest="$(built_app "$cfg")"
    ensure_icon
    step "组装 ${APP_NAME}.app ($cfg)"
    "$bin/smart-fan" build-app --binary "$bin/${APP_NAME}App" --cli "$bin/smart-fan" \
        --icon "$REPO_ROOT/${APP_NAME}.icns" --dest "$dest"
    # Ad-hoc signature. NOT notarised: the app asks for administrator rights to
    # install the daemon, so only a real Developer ID signature removes the local
    # privilege-escalation caveat (docs/daemon-self-management-plan.md §8).
    codesign --force --deep --sign - "$dest" >/dev/null 2>&1 || warn "临时签名失败（应用可能无法启动）"
    ok "已组装：$dest"
}

run_unit_tests() { # <debug|release>
    local cfg="$1"
    require_cmd swift "请先安装 Xcode 命令行工具：xcode-select --install。"
    step "单元测试 ($cfg)"
    # shellcheck disable=SC2046
    run_swift swift test -c "$cfg" --no-parallel $(swift_test_args)
}

run_disconnected_clients() {
    step "断连客户端回归（SIGPIPE）"
    local dir
    dir="$(mktemp -d "${TMPDIR:-/tmp}/smart-fan-disconnect.XXXXXX")"
    swiftc -O "$REPO_ROOT"/Sources/SmartFanCore/*.swift \
        "$REPO_ROOT"/Tests/ProcessFixtures/DisconnectedClients.swift -o "$dir/clients"
    "$dir/clients"
    rm -rf "$dir"
}

# Packaging validation: the assembler copies the localization bundle and the
# licence, and must refuse a bundle with missing resources.
check_localization_package() { # <bin_dir or empty>
    local bin="$1"
    [ -n "$bin" ] || bin="$(bin_dir debug)"
    step "打包资源校验"
    local bundle="${APP_NAME}_${APP_NAME}Localization.bundle"
    local dir
    dir="$(mktemp -d "${TMPDIR:-/tmp}/smart-fan-package.XXXXXX")"
    : >"$dir/icon.icns"
    "$bin/smart-fan" build-app --binary "$bin/${APP_NAME}App" --cli "$bin/smart-fan" \
        --icon "$dir/icon.icns" --dest "$dir/Check.app" >/dev/null
    local plist="$dir/Check.app/Contents/Info.plist"
    [ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$plist")" = "org.witt.smartfan.app" ] \
        || die "Info.plist 的 CFBundleIdentifier 不对"
    [ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleName' "$plist")" = "$APP_NAME" ] \
        || die "Info.plist 的 CFBundleName 不对"
    cmp -s "$REPO_ROOT/LICENSE" "$dir/Check.app/Contents/Resources/LICENSE" \
        || die "应用包里的 LICENSE 与仓库不一致"
    local resources="$dir/Check.app/Contents/Resources/$bundle"
    [ -d "$resources/Contents/Resources" ] && resources="$resources/Contents/Resources"
    local lang
    for lang in en zh-Hans zh-Hant; do
        cmp -s "$REPO_ROOT/Sources/${APP_NAME}Localization/Resources/$lang.json" "$resources/$lang.json" \
            || die "应用包里的 $lang.json 与仓库不一致"
    done
    mkdir "$dir/unbundled"
    cp "$bin/${APP_NAME}App" "$dir/unbundled/${APP_NAME}App"
    echo preserve >"$dir/Check.app/sentinel"
    if "$bin/smart-fan" build-app --binary "$dir/unbundled/${APP_NAME}App" --cli "$bin/smart-fan" \
        --icon "$dir/icon.icns" --dest "$dir/Check.app" >"$dir/rejection.log" 2>&1; then
        die "缺少语言资源时本应拒绝，但它成功了"
    fi
    [ "$(cat "$dir/Check.app/sentinel")" = preserve ] || die "拒绝路径破坏了已存在的应用包"
    rm -rf "$dir"
    ok "打包资源校验通过"
}

# ---------------------------------------------------------------------------
# Commands — build and run
# ---------------------------------------------------------------------------

cmd_build() {
    local cfg="debug"
    [ "${1:-}" = "release" ] && cfg="release"
    require_cmd swift "请先安装 Xcode 命令行工具：xcode-select --install"
    step "编译 ($cfg)"
    run_swift swift build -c "$cfg"   # compiling is the point here: show the output
    ok "编译完成（$cfg）"
}

cmd_app() {
    local cfg="release"
    [ "${1:-}" = "debug" ] && cfg="debug"
    run_build "$cfg"
    assemble_app "$cfg"
}

cmd_run() {
    # Fastest loop: run the built app binary directly. Nothing is installed and no
    # administrator prompt appears — the app will report the background service as
    # unavailable, which is expected (use `install` for real fan control).
    if [ "${1:-}" = "--bundle" ]; then
        run_build debug
        assemble_app debug
        step "打开（debug 包，不会安装到 /Applications）"
        open "$(built_app debug)"
        return
    fi
    run_build debug
    step "启动（直接运行构建产物，Ctrl-C 退出）"
    "$(bin_dir debug)/${APP_NAME}App"
}

# ---------------------------------------------------------------------------
# Commands — install / uninstall
# ---------------------------------------------------------------------------

do_install() {
    run_build release
    assemble_app release
    local bin
    bin="$(bin_dir release)"
    step "安装后台服务（需要管理员密码）"
    dim "  将执行：sudo $bin/smart-fan install"
    sudo "$bin/smart-fan" install
    step "打开应用"
    open "$APP_DEST"
    ok "已安装（应用 $(app_version)）"
}

cmd_install() {
    if is_installed; then
        say "检测到已安装："
        [ -d "$APP_DEST" ] && say "    应用：$APP_DEST"
        [ -x "$HELPER" ] && say "    后台服务：$HELPER"
        say ""
        say "不会覆盖已有安装。要强制覆盖安装，请运行："
        say "    scripts/setup.sh reinstall"
        exit 1
    fi
    do_install
}

cmd_reinstall() {
    if is_installed; then
        step "覆盖安装"
        dim "  会替换现有应用与后台服务，用户数据保留。"
    fi
    do_install
}

cmd_uninstall() {
    if ! is_installed; then
        say "未检测到安装，无需卸载。"
        return 0
    fi
    local purge=0
    case "${1:-}" in -f | --force | --purge-data) purge=1 ;; esac

    # The installed helper is the CLI; use it so this works without a build tree.
    local cli="$HELPER"
    if [ ! -x "$cli" ]; then
        cli="$(bin_dir release)/smart-fan"
        [ -x "$cli" ] || die "找不到可用的 smart-fan 二进制，无法卸载。"
    fi

    if [ "$purge" = 1 ]; then
        warn "将删除所有数据与文件：用户偏好、日志、校准数据、后台服务日志。"
        confirm "确认继续？" || die "已取消。"
        step "卸载（含数据清理）"
        sudo "$cli" uninstall --purge-data
    else
        step "卸载应用与后台服务（用户数据保留）"
        dim "  要连数据一起删除，用：scripts/setup.sh uninstall -f"
        sudo "$cli" uninstall
    fi

    if command -v brew >/dev/null 2>&1 && brew list --cask smart-fan >/dev/null 2>&1; then
        step "卸载 Homebrew cask"
        brew uninstall --cask smart-fan
    fi
    ok "已卸载"
}

cmd_open() {
    [ -d "$APP_DEST" ] || die "未找到 $APP_DEST，请先运行：scripts/setup.sh install"
    open "$APP_DEST"
    ok "已打开"
}

cmd_quit() {
    if is_app_running; then
        pkill -x "${APP_NAME}App" || true
        ok "已退出应用"
    else
        say "应用未在运行。"
    fi
}

cmd_restart() {
    cmd_quit
    sleep 1
    cmd_open
}

# ---------------------------------------------------------------------------
# Commands — verify and diagnose
# ---------------------------------------------------------------------------

cmd_test() {
    local cfg="debug"
    [ "${1:-}" = "--release" ] && cfg="release"
    run_unit_tests "$cfg"
    run_disconnected_clients
    check_localization_package "$(bin_dir "$cfg")"
    ok "全部检查通过（$cfg）"
}

cmd_check() {
    run_build debug
    cmd_test
}

cmd_doctor() {
    step "环境"
    if command -v swift >/dev/null 2>&1; then
        ok "swift：$(swift --version 2>&1 | head -1)"
    else
        warn "swift：未安装 —— 运行 xcode-select --install"
    fi
    say "   系统：$(sw_vers -productVersion 2>/dev/null || echo '?')"
    say "   机型：$(sysctl -n hw.model 2>/dev/null || echo '?') / $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo '?')"
    say "   仓库版本：$(app_version)"

    step "安装状态"
    if [ -d "$APP_DEST" ]; then
        local app_ver
        app_ver="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_DEST/Contents/Info.plist" 2>/dev/null || echo '?')"
        ok "应用：$APP_DEST（$app_ver）"
    else
        say "   应用：未安装"
    fi
    if [ -x "$HELPER" ]; then
        ok "后台服务：$HELPER"
    else
        say "   后台服务：未安装"
    fi
    [ -f "$PLIST" ] && say "   开机自启定义：$PLIST" || say "   开机自启定义：无"
    [ -S "$SOCKET" ] && say "   通信 socket：$SOCKET" || say "   通信 socket：无（后台服务未运行）"
    if launchctl print "system/${DAEMON_LABEL}" >/dev/null 2>&1; then
        ok "launchd：已注册"
    else
        say "   launchd：未注册"
    fi
    is_app_running && ok "应用进程：运行中" || say "   应用进程：未运行"

    step "日志位置"
    say "   应用日志：$HOME/Library/Logs/${APP_NAME}/"
    say "   后台日志：/var/root/Library/Logs/${APP_NAME}/   （需 sudo 查看）"

    local today="$HOME/Library/Logs/${APP_NAME}/smart-fan-$(date +%F).log"
    if [ -f "$today" ]; then
        step "今天的错误（最多 10 条）"
        if grep -q '\[ERROR\]' "$today" 2>/dev/null; then
            grep '\[ERROR\]' "$today" | tail -10
        else
            ok "无 ERROR"
        fi
    fi

    step "下一步"
    if ! command -v swift >/dev/null 2>&1; then
        say "   安装 Xcode 命令行工具：xcode-select --install"
    elif [ ! -x "$HELPER" ]; then
        if [ -d "$APP_DEST" ]; then
            say "   应用已装上，但后台服务缺失。在应用里点【更新后台服务】，或运行：scripts/setup.sh reinstall"
        else
            say "   尚未安装。运行：scripts/setup.sh install"
        fi
    elif [ ! -S "$SOCKET" ]; then
        say "   后台服务已安装但没有响应。在应用里点【修复后台服务】，或运行：scripts/setup.sh reinstall"
    else
        say "   一切就绪。查看日志：scripts/setup.sh logs -f"
    fi

    say ""
    dim "报 bug 时请附上以上输出（已隐去个人信息）。"
}

cmd_logs() {
    local app_log_dir="$HOME/Library/Logs/${APP_NAME}"
    local follow=0 daemon=0
    local arg
    for arg in "$@"; do
        case "$arg" in
        -f | --follow) follow=1 ;;
        --daemon) daemon=1 ;;
        esac
    done

    if [ "$daemon" = 1 ]; then
        step "后台服务日志（需要管理员密码）"
        local dir="/var/root/Library/Logs/${APP_NAME}"
        if [ "$follow" = 1 ]; then
            sudo tail -f "$dir"/smart-fan-*.log
        else
            sudo tail -n 100 "$dir"/smart-fan-*.log
        fi
        return
    fi

    local today="$app_log_dir/smart-fan-$(date +%F).log"
    [ -f "$today" ] || die "今天还没有日志：$today"
    if [ "$follow" = 1 ]; then
        step "跟随应用日志（Ctrl-C 退出）"
        tail -f "$today"
    else
        step "应用日志（最后 100 行）"
        dim "  加 --daemon 看后台服务日志；加 -f 持续跟随。"
        tail -n 100 "$today"
    fi
}

# ---------------------------------------------------------------------------
# Commands — packaging and maintenance
# ---------------------------------------------------------------------------

cmd_package() {
    run_build release
    assemble_app release
    local bin version arch out name stage
    bin="$(bin_dir release)"
    version="$(app_version)"
    arch="$(uname -m)"
    [ "$arch" = "arm64" ] || die "只支持 Apple Silicon（当前：$arch）"
    if [ -n "${RELEASE_TAG:-}" ] && [ "$RELEASE_TAG" != "v$version" ]; then
        die "RELEASE_TAG=$RELEASE_TAG 与版本 $version 不一致"
    fi
    out="${1:-$REPO_ROOT/dist}"
    mkdir -p "$out"
    out="$(cd "$out" && pwd)"
    stage="$(mktemp -d "${TMPDIR:-/tmp}/smart-fan-release.XXXXXX")"
    trap 'rm -rf "$stage"' EXIT
    name="${APP_NAME}-${version}-macos-${arch}"
    step "打包 $name"
    mkdir -p "$stage/$name/bin"
    cp "$bin/smart-fan" "$stage/$name/bin/smart-fan"
    cp -R "$(built_app release)" "$stage/$name/${APP_NAME}.app"
    cp "$REPO_ROOT/LICENSE" "$REPO_ROOT/NOTICE.md" "$REPO_ROOT/README.md" "$stage/$name/"
    cp -R "$REPO_ROOT/ThirdPartyNotices" "$stage/$name/"
    codesign --force --deep --sign - "$stage/$name/${APP_NAME}.app" >/dev/null 2>&1 || true
    codesign --verify --deep --strict "$stage/$name/${APP_NAME}.app"
    COPYFILE_DISABLE=1 tar -czf "$out/$name.tar.gz" -C "$stage" "$name"
    (cd "$out" && shasum -a 256 "$name.tar.gz" >SHA256SUMS)
    ok "已生成：$out/$name.tar.gz"
    say "   校验和：$out/SHA256SUMS"
}

cmd_icon() {
    step "生成图标"
    require_cmd iconutil "图标工具缺失，请安装 Xcode 命令行工具。"
    swift "$REPO_ROOT/scripts/generate-icon.swift"
    iconutil -c icns "$REPO_ROOT/${APP_NAME}.iconset" -o "$REPO_ROOT/${APP_NAME}.icns"
    ok "已生成 ${APP_NAME}.icns"
}

cmd_l10n() {
    step "从简体中文重新生成繁体中文"
    swift "$REPO_ROOT/scripts/update-traditional.swift"
    step "校验三语言键一致"
    run_swift swift test --filter LocalizationTests --no-parallel $(swift_test_args)
    ok "本地化已更新并通过校验"
}

cmd_cli() {
    [ "$#" -gt 0 ] || die "用法：scripts/setup.sh cli <smart-fan 参数…>（例如 cli status）"
    run_build debug
    "$(bin_dir debug)/smart-fan" "$@"
}

cmd_clean() {
    confirm "将删除 .build 和 dist（下次需要重新编译）。继续？" || die "已取消。"
    rm -rf "$REPO_ROOT/.build" "$REPO_ROOT/dist"
    ok "已清理"
}

# ---------------------------------------------------------------------------
# Usage / version
# ---------------------------------------------------------------------------

usage() {
    cat <<EOF
${APP_NAME} — 开发与维护脚本   (脚本版本 ${SCRIPT_VERSION}，应用版本 $(app_version))

用法：scripts/setup.sh <命令> [选项]

构建与运行
  build [debug|release]     编译（默认 debug）
  app [debug|release]       编译并组装 ${APP_NAME}.app（默认 release，不安装）
  run [--bundle]            直接运行，不动系统（--bundle 组装成 .app 再打开）
  install                   编译 → 组装 → 安装后台服务 → 装到 /Applications → 打开
                            已安装时会拒绝覆盖（用 reinstall）
  reinstall                 强制覆盖安装（用户数据保留）
  uninstall [-f]            卸载；-f 连所有数据与文件一起删除
  open / quit / restart     打开 / 退出 / 重启已安装的应用

验证与排障
  test [--release]          单元测试 + 断连客户端 + 打包资源校验
  check                     build + test（提交前跑这个）
  doctor                    环境与安装状态自检，附今天的错误
  logs [-f] [--daemon]      查看日志（-f 跟随；--daemon 看后台服务日志）

发布与维护
  package [输出目录]        生成 dist/*.tar.gz 与 SHA256SUMS（默认 dist/）
  icon                      重新生成应用图标
  l10n                      从简体中文重生成繁体中文并校验
  cli <参数…>               用构建好的 CLI（例如：cli status）
  clean                     删除 .build 与 dist

其他
  help, -h, --help          显示本帮助
  version, -v, --version    显示脚本版本与应用版本

全局选项
  --yes                     跳过确认（用于脚本/CI）
  --verbose                 显示每条命令的原始输出

示例
  scripts/setup.sh install          从源码装好并用起来
  scripts/setup.sh run              改界面时快速看效果
  scripts/setup.sh test             改完代码验证
  scripts/setup.sh doctor           出问题时先跑这个
EOF
}

cmd_version() {
    say "脚本版本：${SCRIPT_VERSION}"
    say "应用版本：$(app_version)"
    if [ -d "$APP_DEST" ]; then
        say "已安装版本：$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_DEST/Contents/Info.plist" 2>/dev/null || echo '?')"
    fi
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

CMD="${1:-help}"
[ "$#" -gt 0 ] && shift

# Global options may appear before or after the command.
ARGS=()
for arg in "$@"; do
    case "$arg" in
    --yes) ASSUME_YES=1 ;;
    --verbose) VERBOSE=1 ;;
    *) ARGS+=("$arg") ;;
    esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}

if [ "$VERBOSE" = 1 ]; then
    set -x
fi

case "$CMD" in
build) cmd_build "$@" ;;
app) cmd_app "$@" ;;
run) cmd_run "$@" ;;
install) cmd_install "$@" ;;
reinstall) cmd_reinstall "$@" ;;
uninstall) cmd_uninstall "$@" ;;
open) cmd_open "$@" ;;
quit) cmd_quit "$@" ;;
restart) cmd_restart "$@" ;;
test) cmd_test "$@" ;;
check) cmd_check "$@" ;;
doctor) cmd_doctor "$@" ;;
logs) cmd_logs "$@" ;;
package) cmd_package "$@" ;;
icon) cmd_icon "$@" ;;
l10n) cmd_l10n "$@" ;;
cli) cmd_cli "$@" ;;
clean) cmd_clean "$@" ;;
help | -h | --help) usage ;;
version | -v | --version) cmd_version ;;
*)
    warn "未知命令：$CMD"
    say "运行 scripts/setup.sh help 查看全部命令。"
    exit 1
    ;;
esac
