#!/bin/zsh

set -u
set -o pipefail

REPOSITORY_ARCHIVE="https://codeload.github.com/miroshantoshan/materialTun/tar.gz/refs/heads/main"
REPOSITORY_ARCHIVE_FALLBACK="https://github.com/miroshantoshan/materialTun/archive/refs/heads/main.tar.gz"
SING_BOX_LATEST_RELEASE="https://github.com/SagerNet/sing-box/releases/latest"
GEO_RELEASE_BASE="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download"
GEO_MIRROR_BASE="https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release"
USER_APPS_DIR="$HOME/Applications"
TARGET_APP="$USER_APPS_DIR/materialTun.app"
WORK_DIR="$(mktemp -d -t materialtun-installer)"
LOG_FILE="$WORK_DIR/installer.log"
ARCHIVE_PATH="$WORK_DIR/materialTun.tar.gz"
PROJECT_DIR="$WORK_DIR/materialTun-main"
SOURCE_APP="$WORK_DIR/materialTun.app"
RUNTIME_DIR="$WORK_DIR/runtime"

if [[ -d /Applications/Xcode.app/Contents/Developer ]] && \
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --find swiftc >/dev/null 2>&1; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

export CLANG_MODULE_CACHE_PATH="$WORK_DIR/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$WORK_DIR/swift-module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"

RESET=$'\e[0m'
BOLD=$'\e[1m'
DIM=$'\e[2m'
LIGHT_PURPLE=$'\e[38;5;183m'
CYAN=$'\e[38;5;117m'
GREEN=$'\e[38;5;114m'
RED=$'\e[38;5;203m'
GRAY=$'\e[38;5;245m'
BANNER_WIDTH=48

cleanup() {
    if [[ -d "$WORK_DIR" && "${WORK_DIR:t}" == materialtun-installer.* ]]; then
        rm -rf -- "$WORK_DIR"
    fi
}

trap cleanup EXIT

fail() {
    print ""
    print -- "${RED}${BOLD}  ✕ Installation failed${RESET}"
    print -- "${RED}  $1${RESET}"

    if [[ -s "$LOG_FILE" ]]; then
        print ""
        print -- "${LIGHT_PURPLE}  Last messages:${RESET}"
        tail -n 12 "$LOG_FILE" | sed 's/^/    /'
    fi

    print ""
    print -n -- "${GRAY}Press Enter to close this window...${RESET}"
    read -r
    exit 1
}

banner_border() {
    local left_corner="$1"
    local right_corner="$2"
    local rule
    printf -v rule '%*s' "$BANNER_WIDTH" ''
    rule="${rule// /─}"
    print -- "${LIGHT_PURPLE}${left_corner}${rule}${right_corner}${RESET}"
}

banner_line() {
    local text="${1:-}"
    local color="${2:-$RESET}"
    (( ${#text} <= BANNER_WIDTH )) || text="${text[1,$BANNER_WIDTH]}"
    local text_width=${#text}
    local left_padding=$(( (BANNER_WIDTH - text_width) / 2 ))
    local right_padding=$(( BANNER_WIDTH - text_width - left_padding ))

    print -n -- "${LIGHT_PURPLE}│${RESET}"
    printf '%*s' "$left_padding" ''
    print -n -- "${color}${text}${RESET}"
    printf '%*s' "$right_padding" ''
    print -- "${LIGHT_PURPLE}│${RESET}"
}

header() {
    if [[ -t 1 ]]; then
        print -n -- $'\e]0;materialTun Installer\a'
        if [[ "${TERM_PROGRAM:-}" == "Apple_Terminal" ]]; then
            print -n -- $'\e[8;31;58t'
            sleep 0.15
        fi
        clear
    fi
    banner_border "╭" "╮"
    banner_line
    banner_line "materialTun Installer" "${CYAN}${BOLD}"
    banner_line "Secure connectivity for macOS" "$GREEN"
    banner_line
    banner_border "╰" "╯"
    print ""
}

step() {
    print -- "${CYAN}${BOLD}  $1${RESET} ${LIGHT_PURPLE}${BOLD}$2${RESET}"
    print -- "${GRAY}      $3${RESET}"
}

run_with_spinner() {
    local label="$1"
    local minimum_seconds="$2"
    shift 2

    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local frame=1
    local started=$SECONDS

    : >"$LOG_FILE"
    "$@" >"$LOG_FILE" 2>&1 &
    local task_pid=$!

    while kill -0 "$task_pid" 2>/dev/null || (( SECONDS - started < minimum_seconds )); do
        print -n -- "\r\e[K${LIGHT_PURPLE}      ${frames[$frame]} $label · $((SECONDS - started))s${RESET}"
        frame=$((frame % ${#frames[@]} + 1))
        sleep 0.12
    done

    if wait "$task_pid"; then
        print -- "\r\e[K${GREEN}      ✓ $label${RESET}"
        return 0
    fi

    print -- "\r\e[K${RED}      ✕ $label${RESET}"
    return 1
}

animate_progress() {
    local start="$1"
    local finish="$2"
    local index empty bar part

    for ((index = start; index <= finish; index++)); do
        empty=$((20 - index))
        bar=""
        for ((part = 0; part < index; part++)); do bar+="█"; done
        for ((part = 0; part < empty; part++)); do bar+="░"; done
        print -n -- "\r${CYAN}      [${LIGHT_PURPLE}$bar${CYAN}]${RESET}  $((index * 5))%"
        sleep 0.08
    done
    print ""
}

ensure_swift() {
    if command -v swift >/dev/null 2>&1 && swift --version >/dev/null 2>&1; then
        return 0
    fi

    step "SETUP" "Developer Tools" "Installing Apple's free Swift compiler"
    xcode-select --install >/dev/null 2>&1 || true

    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local frame=1
    local started=$SECONDS

    while ! swift --version >/dev/null 2>&1; do
        (( SECONDS - started < 1200 )) || fail "Developer Tools installation timed out."
        print -n -- "\r${LIGHT_PURPLE}      ${frames[$frame]} Waiting for Developer Tools...${RESET}   "
        frame=$((frame % ${#frames[@]} + 1))
        sleep 2
    done

    print -- "\r${GREEN}      ✓ Developer Tools are ready${RESET}             "
    print ""
}

download_file() {
    local label="$1"
    local url="$2"
    local destination="$3"
    local fallback="${4:-}"

    print -- "Downloading $label..."
    if curl --fail --location --silent --show-error \
        --user-agent "materialTun-Installer/2.0" \
        --header "Accept: application/octet-stream" \
        --connect-timeout 15 --max-time 300 \
        --retry 3 --retry-delay 2 --retry-all-errors \
        "$url" --output "$destination"; then
        return 0
    fi

    [[ -n "$fallback" ]] || return 1
    print -- "Primary source failed. Trying the mirror for $label..."
    curl --fail --location --silent --show-error \
        --user-agent "materialTun-Installer/2.0" \
        --connect-timeout 15 --max-time 300 \
        --retry 3 --retry-delay 2 --retry-all-errors \
        "$fallback" --output "$destination"
}

download_source() {
    print -- "Downloading materialTun source from GitHub codeload..."
    if curl --fail --location --silent --show-error \
        --user-agent "materialTun-Installer/2.0" \
        --connect-timeout 8 --max-time 45 \
        --retry 1 --retry-delay 1 \
        "$REPOSITORY_ARCHIVE" --output "$ARCHIVE_PATH"; then
        return 0
    fi

    print -- "The direct source endpoint failed. Trying the GitHub archive URL..."
    curl --fail --location --silent --show-error \
        --user-agent "materialTun-Installer/2.0" \
        --connect-timeout 10 --max-time 60 \
        --retry 1 --retry-delay 1 \
        "$REPOSITORY_ARCHIVE_FALLBACK" --output "$ARCHIVE_PATH"
}

download_runtime() {
    local machine xray_asset sing_arch latest_release_url sing_tag sing_version sing_asset
    machine="$(uname -m)"
    case "$machine" in
        arm64)
            xray_asset="Xray-macos-arm64-v8a.zip"
            sing_arch="arm64"
            ;;
        x86_64)
            xray_asset="Xray-macos-64.zip"
            sing_arch="amd64"
            ;;
        *)
            print -u2 -- "Unsupported Mac architecture: $machine"
            return 1
            ;;
    esac

    mkdir -p "$RUNTIME_DIR/xray" "$RUNTIME_DIR/sing-box"

    download_file "Xray" \
        "https://github.com/XTLS/Xray-core/releases/latest/download/$xray_asset" \
        "$WORK_DIR/xray.zip" || return 1
    ditto -x -k "$WORK_DIR/xray.zip" "$RUNTIME_DIR/xray" || return 1
    [[ -x "$RUNTIME_DIR/xray/xray" ]] || chmod +x "$RUNTIME_DIR/xray/xray" || return 1

    print -- "Resolving the latest sing-box version..."
    latest_release_url="$(curl --fail --location --silent --show-error \
        --user-agent "materialTun-Installer/2.0" \
        --connect-timeout 15 --max-time 60 --retry 3 --retry-delay 2 \
        --output /dev/null --write-out '%{url_effective}' \
        "$SING_BOX_LATEST_RELEASE")" || return 1
    sing_tag="${latest_release_url:t}"
    [[ "$sing_tag" == v<->.* ]] || return 1
    sing_version="${sing_tag#v}"
    sing_asset="sing-box-${sing_version}-darwin-${sing_arch}.tar.gz"
    download_file "sing-box $sing_version" \
        "https://github.com/SagerNet/sing-box/releases/download/$sing_tag/$sing_asset" \
        "$WORK_DIR/sing-box.tar.gz" || return 1
    tar -xzf "$WORK_DIR/sing-box.tar.gz" -C "$RUNTIME_DIR/sing-box" || return 1
    find "$RUNTIME_DIR/sing-box" -type f -name sing-box -perm +111 -print -quit >"$WORK_DIR/sing-box-path"
    [[ -s "$WORK_DIR/sing-box-path" ]] || return 1

    download_file "GeoIP rules" \
        "$GEO_RELEASE_BASE/geoip.dat" "$RUNTIME_DIR/geoip.dat" \
        "$GEO_MIRROR_BASE/geoip.dat" || return 1
    download_file "GeoSite rules" \
        "$GEO_RELEASE_BASE/geosite.dat" "$RUNTIME_DIR/geosite.dat" \
        "$GEO_MIRROR_BASE/geosite.dat" || return 1
}

build_application() {
    cd "$PROJECT_DIR" || return 1
    swift build -c release || return 1

    local bin_dir contents macos resources helpers iconset sing_box
    bin_dir="$(swift build -c release --show-bin-path)" || return 1
    contents="$SOURCE_APP/Contents"
    macos="$contents/MacOS"
    resources="$contents/Resources"
    helpers="$contents/Library/HelperTools"
    iconset="$WORK_DIR/AppIcon.iconset"
    sing_box="$(<"$WORK_DIR/sing-box-path")"

    mkdir -p "$macos" "$resources" "$helpers" "$iconset" || return 1
    ditto "$bin_dir/materialTun" "$macos/materialTun" || return 1
    ditto "$bin_dir/materialTunHelper" "$helpers/materialTunHelper" || return 1
    ditto "$PROJECT_DIR/App/Info.plist" "$contents/Info.plist" || return 1
    ditto "$RUNTIME_DIR/xray/xray" "$resources/xray" || return 1
    ditto "$sing_box" "$resources/sing-box" || return 1
    ditto "$RUNTIME_DIR/geoip.dat" "$resources/geoip.dat" || return 1
    ditto "$RUNTIME_DIR/geosite.dat" "$resources/geosite.dat" || return 1
    chmod +x "$macos/materialTun" "$helpers/materialTunHelper" "$resources/xray" "$resources/sing-box" || return 1

    sips -s format png "$PROJECT_DIR/Resources/AppIcon.png" --out "$WORK_DIR/AppIcon-source.png" >/dev/null || return 1
    sips -z 1024 1024 "$WORK_DIR/AppIcon-source.png" --out "$WORK_DIR/AppIcon-1024.png" >/dev/null || return 1
    local size double
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$WORK_DIR/AppIcon-1024.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null || return 1
        double=$((size * 2))
        sips -z "$double" "$double" "$WORK_DIR/AppIcon-1024.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null || return 1
    done
    iconutil -c icns "$iconset" -o "$resources/AppIcon.icns" || return 1

    xattr -cr "$SOURCE_APP" || return 1
    codesign --force --deep --sign - "$SOURCE_APP" || return 1
    xattr -cr "$SOURCE_APP" || return 1
}

close_terminal_window() {
    if [[ "${TERM_PROGRAM:-}" == "Apple_Terminal" ]]; then
        nohup /usr/bin/osascript \
            -e 'delay 0.5' \
            -e 'tell application "Terminal" to close front window' \
            >/dev/null 2>&1 &
    fi
}

header

for dependency in curl tar ditto sips iconutil codesign; do
    command -v "$dependency" >/dev/null 2>&1 || fail "Required command not found: $dependency"
done
ensure_swift

step "1/5" "Download materialTun" "Fetching the latest source code from GitHub"
if ! run_with_spinner "Downloading source code..." 2 download_source; then
    fail "Could not download materialTun. Check your internet connection or VPN."
fi

tar -xzf "$ARCHIVE_PATH" -C "$WORK_DIR" >"$LOG_FILE" 2>&1 \
    || fail "The downloaded source archive could not be unpacked."
[[ -f "$PROJECT_DIR/Package.swift" ]] || fail "The downloaded project is incomplete or has an unexpected structure."
print ""

step "2/5" "Connection components" "Downloading Xray, sing-box, and current Geo rules"
run_with_spinner "Preparing connection components..." 4 download_runtime \
    || fail "Could not download the connection components."
print ""

step "3/5" "Build application" "Creating an optimized materialTun build for this Mac"
run_with_spinner "Compiling Swift and packaging the app..." 5 build_application \
    || fail "Could not build materialTun."
[[ -d "$SOURCE_APP" ]] || fail "The application bundle was not created."
print ""

step "4/5" "Install application" "Copying materialTun to your Applications folder"
animate_progress 0 12
mkdir -p "$USER_APPS_DIR" || fail "Could not create $USER_APPS_DIR."

if [[ -e "$TARGET_APP" ]]; then
    [[ "$TARGET_APP" == "$HOME/Applications/materialTun.app" ]] || fail "Unsafe installation path."
    rm -rf -- "$TARGET_APP" || fail "Could not replace the previous installation."
fi

ditto "$SOURCE_APP" "$TARGET_APP" || fail "Could not copy the application."
animate_progress 13 20
print -- "${GREEN}      ✓ Installed in ~/Applications${RESET}"
print ""

step "5/5" "Launch" "Starting materialTun"
sleep 1
open "$TARGET_APP" || fail "The application was installed but could not be opened."
print -- "${GREEN}      ✓ materialTun is ready${RESET}"
print ""
banner_border "╭" "╮"
banner_line "Installation completed successfully" "${GREEN}${BOLD}"
banner_border "╰" "╯"
print ""
print -- "${DIM}  Temporary installation files will now be removed.${RESET}"
sleep 1

cleanup
trap - EXIT
close_terminal_window
exit 0
