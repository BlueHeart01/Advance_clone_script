#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
#  BlueHeart Advance Clone Script
#  Clones the redwood trees + extras and configures the product
#  makefile for the ROM you pick. Run it from your ROM source root.
# ──────────────────────────────────────────────────────────────────

set -o pipefail
export GIT_TERMINAL_PROMPT=0   # never hang on a hidden credential prompt

# ─── Repositories ─────────────────────────────────────────────────
GH="https://github.com/BlueHeart01"

KEYS_REPO="$GH/keys.git"
POS_KEYS_REPO="$GH/POS-keys.git"

DEVICE_REPO="$GH/android_device_xiaomi_redwood.git"
VENDOR_REPO="$GH/android_vendor_xiaomi_redwood.git"

# "repo url|destination"
EXTRA_REPOS=(
    "$GH/device_xiaomi_redwood-scarlet-kernel.git|device/xiaomi/redwood-kernel"
    "$GH/vendor_xiaomi_redwood-miuicamera.git|vendor/xiaomi/redwood-miuicamera"
    "$GH/android_hardware_xiaomi.git|hardware/xiaomi"
    "$GH/vendor_bcr.git|vendor/bcr"
    "$GH/android_packages_apps_ViPER4AndroidFX.git|packages/apps/ViPER4AndroidFX"
)

# ─── Android 16 rollback ──────────────────────────────────────────
# Offered after cloning ("Make tree A16?"). Choosing Yes will:
#   • revert the A17 commits below in the device tree and camera repo
#   • delete the vendor tree and re-clone it from $A16_VENDOR_BRANCH
# Commits are always reverted newest first, whatever order they're listed in.
A16_DEVICE_PATH="device/xiaomi/redwood"
A16_DEVICE_REVERTS=(
    bf1b647c41032bf2d3fa378d3fce298b3d96e8c7
    36581bbb1551cc52d81233fa5fc37a384679efc9
    d9edd86c478fc751e82cf21e2c8b454911af9843
    cd7a9be50d7665000821d5c006999b2704469018
)

A16_CAMERA_PATH="vendor/xiaomi/redwood-miuicamera"
A16_CAMERA_REVERTS=(
    640ea9909561cc7e816ec68fb0eaa571f2f508a9
)

A16_VENDOR_PATH="vendor/xiaomi/redwood"      # re-cloned from $VENDOR_REPO
A16_VENDOR_BRANCH="sixteen-qpr2"

# ─── Pre-configured branches ──────────────────────────────────────
# If the chosen device tree branch name contains one of these words
# (case-insensitive), ROM selection and configuration are skipped,
# because those branches are already set up for their ROM.
PRECONFIGURED_KEYWORDS=(lunaris rising ascp)

# ─── Paths ────────────────────────────────────────────────────────
DEVICE=device/xiaomi/redwood
ANDROID_PRODUCTS=$DEVICE/AndroidProducts.mk
BOARD_CONFIG=$DEVICE/BoardConfig.mk
LINEAGE_MK=$DEVICE/lineage_redwood.mk
SYSTEM_PROP=$DEVICE/configs/props/system.prop

# ─── Terminal styling ─────────────────────────────────────────────
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RED=$'\033[31m';    GREEN=$'\033[32m';  YELLOW=$'\033[33m'
    BLUE=$'\033[34m';   MAGENTA=$'\033[35m'; CYAN=$'\033[36m'
    BOLD=$'\033[1m';    DIM=$'\033[2m';     NC=$'\033[0m'
else
    RED=; GREEN=; YELLOW=; BLUE=; MAGENTA=; CYAN=; BOLD=; DIM=; NC=
fi

TAB=$'\t'
BOX_W=54
printf -v RULE '%*s' "$BOX_W" ''
RULE=${RULE// /─}

START_TIME=$SECONDS
WORK_TMP=""

info() { printf '  %s●%s %s\n' "$CYAN" "$NC" "$*"; }
ok()   { printf '  %s✔%s %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '  %s▲%s %s\n' "$YELLOW" "$NC" "$*"; }
fail() { printf '  %s✘%s %s\n' "$RED" "$NC" "$*" >&2; }

row() { printf '  %s%-10s%s %s\n' "$DIM" "$1" "$NC" "$2"; }

section() {
    printf '\n  %s%s◆ %s%s\n  %s%s%s\n' "$BOLD" "$CYAN" "$1" "$NC" "$DIM" "$RULE" "$NC"
}

center() {
    local text="$1" w="$2" l r
    l=$(( (w - ${#text}) / 2 ))
    r=$(( w - ${#text} - l ))
    printf '%*s%s%*s' "$l" '' "$text" "$r" ''
}

# box COLOR line1 [line2 ...]  — first line bold, the rest dim
box() {
    local color="$1" t i=0 style; shift
    printf '\n  %s╭%s╮%s\n' "$color" "$RULE" "$NC"
    for t in "$@"; do
        if (( i == 0 )); then style=$BOLD; else style=$DIM; fi
        printf '  %s│%s%s%s%s%s│%s\n' "$color" "$NC" "$style" "$(center "$t" "$BOX_W")" "$NC" "$color" "$NC"
        i=$((i + 1))
    done
    printf '  %s╰%s╯%s\n' "$color" "$RULE" "$NC"
}

cleanup() {
    [[ -t 1 ]] && printf '\033[?25h'
    [[ -t 0 ]] && stty echo 2>/dev/null
    local pids; pids=$(jobs -p)
    [[ -n "$pids" ]] && kill $pids 2>/dev/null
    [[ -n "$WORK_TMP" ]] && rm -rf "$WORK_TMP"
}
trap cleanup EXIT
trap 'printf "\n"; fail "Cancelled."; exit 130' INT TERM

# ─── Spinner ──────────────────────────────────────────────────────
# spin "message" command args...
# Runs the command quietly; sets SPIN_RC, SPIN_SECS, SPIN_OUT, SPIN_ERR.
SPIN_RC=0; SPIN_SECS=0; SPIN_OUT=""; SPIN_ERR=""
spin() {
    local msg="$1"; shift
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) i=0 start=$SECONDS pid
    SPIN_OUT="$WORK_TMP/out"
    SPIN_ERR="$WORK_TMP/err"

    "$@" >"$SPIN_OUT" 2>"$SPIN_ERR" </dev/null &
    pid=$!

    if [[ -t 1 ]]; then
        printf '\033[?25l'
        while kill -0 "$pid" 2>/dev/null; do
            printf '\r\033[K  %s%s%s %s %s(%ss)%s' \
                "$CYAN" "${frames[i]}" "$NC" "$msg" "$DIM" "$((SECONDS - start))" "$NC"
            i=$(( (i + 1) % ${#frames[@]} ))
            sleep 0.08
        done
        printf '\r\033[K\033[?25h'
    else
        printf '  ... %s\n' "$msg"
    fi

    wait "$pid"
    SPIN_RC=$?
    SPIN_SECS=$((SECONDS - start))
}

show_spin_error() {
    local l
    while IFS= read -r l; do
        printf '      %s%s%s\n' "$DIM" "$l" "$NC" >&2
    done < <(tail -n 5 "$SPIN_ERR")
    if grep -qiE 'terminal prompts disabled|authentication failed|could not read username' "$SPIN_ERR"; then
        warn "This repo needs authentication — set up a credential helper (e.g. 'gh auth login') or use SSH."
    fi
}

# ─── Interactive prompts ──────────────────────────────────────────
MENU_INDEX=0
MENU_VALUE=""
MENU_VISIBLE=10

# menu "Title" "label[<TAB>hint]" ...   → sets MENU_INDEX / MENU_VALUE
menu() {
    local title="$1"; shift
    local -a labels=() hints=()
    local item
    for item in "$@"; do
        labels+=("${item%%"$TAB"*}")
        if [[ "$item" == *"$TAB"* ]]; then hints+=("${item#*"$TAB"}"); else hints+=(""); fi
    done

    local n=${#labels[@]} sel=0 top=0 view=$MENU_VISIBLE width=0 first=1 i idx key rest ans
    (( n < view )) && view=$n
    for item in "${labels[@]}"; do (( ${#item} > width )) && width=${#item}; done

    printf '\n  %s?%s %s%s%s\n' "$MAGENTA" "$NC" "$BOLD" "$title" "$NC"

    # Plain numbered fallback when not attached to a terminal
    if [[ ! -t 0 || ! -t 1 ]]; then
        for i in "${!labels[@]}"; do printf '    %2d) %s\n' $((i + 1)) "${labels[i]}"; done
        while true; do
            IFS= read -r -p "  Choose [1-$n]: " ans || exit 1
            if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= n )); then break; fi
            warn "Invalid selection"
        done
        MENU_INDEX=$((ans - 1))
        MENU_VALUE="${labels[MENU_INDEX]}"
        return
    fi

    printf '\033[?25l'
    while true; do
        (( first )) || printf '\033[%dA' $((view + 1))
        first=0

        for (( i = 0; i < view; i++ )); do
            idx=$((top + i))
            printf '\r\033[K'
            if (( idx == sel )); then
                printf '  %s❯ %-*s%s' "$CYAN$BOLD" "$width" "${labels[idx]}" "$NC"
            else
                printf '    %-*s' "$width" "${labels[idx]}"
            fi
            [[ -n "${hints[idx]}" ]] && printf '  %s%s%s' "$DIM" "${hints[idx]}" "$NC"
            printf '\n'
        done
        printf '\r\033[K  %s↑↓ move · enter select' "$DIM"
        (( n > view )) && printf ' · %d/%d' $((sel + 1)) "$n"
        printf '%s\n' "$NC"

        IFS= read -rsn1 key || { printf '\033[?25h'; exit 1; }
        if [[ "$key" == $'\033' ]]; then
            IFS= read -rsn2 -t 0.05 rest
            key+="$rest"
        fi
        case "$key" in
            $'\033[A'|$'\033OA'|k) sel=$(( (sel - 1 + n) % n )) ;;
            $'\033[B'|$'\033OB'|j) sel=$(( (sel + 1) % n )) ;;
            [1-9]) (( key <= n )) && sel=$((key - 1)) ;;
            '') break ;;
        esac

        if (( sel < top )); then
            top=$sel
        elif (( sel >= top + view )); then
            top=$((sel - view + 1))
        fi
    done

    MENU_INDEX=$sel
    MENU_VALUE="${labels[sel]}"

    # Collapse the menu into a single result line
    printf '\033[%dA\033[J\033[?25h' $((view + 2))
    printf '  %s✔%s %s %s›%s %s%s%s\n' "$GREEN" "$NC" "$title" "$DIM" "$NC" "$BOLD" "$MENU_VALUE" "$NC"
}

# ask "Prompt" [default]   → sets ASK_REPLY (value is required)
ASK_REPLY=""
ask() {
    local prompt="$1" default="${2:-}" reply
    while true; do
        printf '\n  %s?%s %s%s%s' "$MAGENTA" "$NC" "$BOLD" "$prompt" "$NC"
        [[ -n "$default" ]] && printf ' %s(%s)%s' "$DIM" "$default" "$NC"
        printf ' %s›%s ' "$CYAN" "$NC"
        IFS= read -r reply || exit 1
        reply="${reply:-$default}"
        [[ -n "$reply" ]] && break
        warn "A value is required"
    done
    ASK_REPLY="$reply"
}

# ─── Cloning ──────────────────────────────────────────────────────
CLONED=0
SKIPPED=0

# clone URL DEST [BRANCH]
clone() {
    local url="$1" dest="$2" branch="${3:-}" name
    name=$(basename "$url" .git)

    if [[ -d "$dest" && -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
        warn "${BOLD}$dest${NC} already exists and is not empty"
        menu "What should I do with it?" \
            "Skip${TAB}keep what's already there" \
            "Re-clone${TAB}delete $dest and clone again" \
            "Abort"
        case $MENU_INDEX in
            0) SKIPPED=$((SKIPPED + 1)); return 0 ;;
            1) rm -rf -- "$dest" ;;
            *) fail "Aborted."; exit 1 ;;
        esac
    fi

    mkdir -p "$(dirname "$dest")"
    local -a args=(clone)
    [[ -n "$branch" ]] && args+=(-b "$branch")

    spin "Cloning $name → $dest" git "${args[@]}" "$url" "$dest"
    if (( SPIN_RC != 0 )); then
        fail "Failed to clone ${BOLD}$name${NC}"
        show_spin_error
        exit 1
    fi

    CLONED=$((CLONED + 1))
    ok "$name ${DIM}→ $dest (${SPIN_SECS}s)${NC}"
}

# ─── ROM presets ──────────────────────────────────────────────────
PREFIX=""
FLAGS=""

rom_preset() {
case "$ROM" in

infinity)
PREFIX="infinity"
FLAGS='
INFINITY_BUILD_TYPE := OFFICIAL
TARGET_BOOT_ANIMATION_RES := 1080
TARGET_SUPPORTS_BLUR := true
INFINITY_MAINTAINER := BlueHeart016|Sᴀʏᴀɴシ
WITH_GAPPS := true
'
;;

avium)
PREFIX="avium"
FLAGS='
WITH_GMS := true
TARGET_GMS_TYPE := FULL
TARGET_FORCE_ENABLE_BLUR := true
AVIUM_FORCE_SET_FAKE_PROP := true
AVIUM_SETTINGS_SOC_MODEL_NAME := Snapdragon778G
AVIUM_SETTINGS_DEVICE_CODENAME := Redwood
AVIUM_MAINTAINER := BlueHeart016|Sᴀʏᴀɴシ
AVIUM_VERSION_APPEND_TIME_OF_DAY := true
'
;;

clover)
PREFIX="clover"
FLAGS='
WITH_GMS := true
TARGET_ENABLE_BLUR := true
TARGET_INCLUDE_PIXEL_LAUNCHER := true
CLOVER_MAINTAINER := BlueHeart016|Sᴀʏᴀɴシ
'
;;

axion)
PREFIX="lineage"
FLAGS='
WITH_GMS := true
WITH_GAPPS := true
TARGET_ENABLE_BLUR := true
TARGET_INCLUDES_LOS_PREBUILTS := true

# Camera information
AXION_CAMERA_REAR_INFO := 12,8,2
AXION_CAMERA_FRONT_INFO := 16

# Maintainer & Device info
AXION_MAINTAINER := Sᴀʏᴀɴシ
AXION_PROCESSOR := Snapdragon_778G
TORCH_STR_SUPPORTED := true
'
;;

pixelos)
PREFIX="custom"
FLAGS=''
;;

euclid)
PREFIX="euclid"
FLAGS='
WITH_GMS_COMMS_SUITE := true
TARGET_INCLUDE_STOCK_ARCORE := true
TARGET_INCLUDE_PIXEL_LAUNCHER := true
TARGET_PREBUILT_LAWNICONS := true
TARGET_BUILD_BCR := true
TARGET_BUILD_DOTGALLERY := true
EUCLID_MAINTAINER := BlueHeart016|Sᴀʏᴀɴシ
EUCLID_DEVICE := POCO_X5_PRO_5G
EUCLID_PROCESSOR := Snapdragon_778G_5G
'
;;

derpfest)
PREFIX="lineage"
FLAGS='
DERPFEST_MAINTAINER := BlueHeart016|Sᴀʏᴀɴシ
'
;;

ascp)
PREFIX="custom"
FLAGS='
# ASCP flags
WITH_GMS := true
ASCP_MAINTAINER := BlueHeart016|Sᴀʏᴀɴシ
WITH_BCR := true
WITH_REVANCED := true
ASCP_OFFICIAL := true

# Device props
TARGET_SUPPORTS_QUICK_TAP := true
TARGET_FACE_UNLOCK_SUPPORTED := true
TARGET_DISABLE_EPPE := true
TARGET_SUPPORTS_NEXT_GEN_ASSISTANT := true
TARGET_SUPPORTS_OMX_SERVICE := false
'
;;

esac
}

collect_custom_flags() {
    info "Enter custom flags, one per line (e.g. WITH_GMS := true)"
    printf '  %sPress Enter on an empty line when done.%s\n' "$DIM" "$NC"
    FLAGS=""
    local line
    while IFS= read -r -p "    + " line; do
        [[ -z "$line" ]] && break
        FLAGS="$FLAGS
$line"
    done
}

# ─── Steps ────────────────────────────────────────────────────────
KEYS_NAME=""; KEYS_URL=""; KEYS_DEST=""
REVERTED=0; REVERT_FAILED=0
PRECONFIGURED_MATCH=""
DEVICE_BRANCH=""
ROM=""; ROM_LABEL=""

banner() {
    box "$CYAN" "BlueHeart Advance Clone Script" "Xiaomi redwood - tree & ROM setup"
    printf '  %sWorking in %s%s\n' "$DIM" "$PWD" "$NC"
}

step_keys() {
    section "Setup"
    menu "Signing keys" \
        "Default keys${TAB}BlueHeart01/keys  →  vendor/lineage-priv/keys" \
        "POS keys${TAB}BlueHeart01/POS-keys  →  vendor/lineage-priv"
    case $MENU_INDEX in
        0) KEYS_NAME="Default keys"; KEYS_URL="$KEYS_REPO";     KEYS_DEST="vendor/lineage-priv/keys" ;;
        1) KEYS_NAME="POS keys";     KEYS_URL="$POS_KEYS_REPO"; KEYS_DEST="vendor/lineage-priv" ;;
    esac
}

step_branch() {
    local -a branches=()
    spin "Fetching branches from $(basename "$DEVICE_REPO" .git)" git ls-remote --heads "$DEVICE_REPO"
    if (( SPIN_RC != 0 )); then
        fail "Could not fetch branches"
        show_spin_error
        exit 1
    fi
    mapfile -t branches < <(awk '{sub(/^refs\/heads\//, "", $2); print $2}' "$SPIN_OUT")
    if (( ${#branches[@]} == 0 )); then
        fail "No branches found in $DEVICE_REPO"
        exit 1
    fi
    menu "Device tree branch (redwood)" "${branches[@]}"
    DEVICE_BRANCH="$MENU_VALUE"

    local lower kw
    lower=$(printf '%s' "$DEVICE_BRANCH" | tr '[:upper:]' '[:lower:]')
    for kw in "${PRECONFIGURED_KEYWORDS[@]}"; do
        if [[ "$lower" == *"$kw"* ]]; then
            PRECONFIGURED_MATCH="$kw"
            break
        fi
    done
    if [[ -n "$PRECONFIGURED_MATCH" ]]; then
        info "Branch is pre-configured for ${BOLD}$PRECONFIGURED_MATCH${NC} — ROM selection will be skipped"
    fi
}

step_rom() {
    local -a labels=(
        "Infinity" "Avium" "Clover" "Axion" "PixelOS" "EuclidOS" "Derpfest" "ASCP"
        "Other${TAB}unlisted ROM, enter prefix & flags"
        "Custom${TAB}edit the product mk file yourself"
    )
    local -a ids=(infinity avium clover axion pixelos euclid derpfest ascp other custom_manual)

    section "ROM selection"
    menu "ROM to configure" "${labels[@]}"
    ROM="${ids[MENU_INDEX]}"
    ROM_LABEL="${labels[MENU_INDEX]%%"$TAB"*}"

    case "$ROM" in
        other)
            ask "ROM name (e.g. spark, rising, voltage)"
            ROM=$(printf '%s' "$ASK_REPLY" | tr '[:upper:]' '[:lower:]')
            ROM=${ROM//[[:space:]]/}
            ROM_LABEL="$ROM"
            warn "'$ROM' is not in the preset list"
            ask "Product prefix for this ROM" "$ROM"
            PREFIX=$(printf '%s' "$ASK_REPLY" | tr '[:upper:]' '[:lower:]')
            PREFIX=${PREFIX//[[:space:]]/}
            collect_custom_flags
            ;;
        custom_manual)
            ROM_LABEL="Custom (manual edit)"
            ;;
        *)
            rom_preset
            ;;
    esac
}

step_review() {
    section "Review"
    row "Keys"    "$KEYS_NAME  →  $KEYS_DEST"
    row "Branch"  "$DEVICE_BRANCH"
    row "Trees"   "$DEVICE/, vendor/xiaomi/redwood"
    row "Extras"  "kernel, MIUI camera, hardware/xiaomi, BCR, ViPER4AndroidFX"
    if [[ -n "$PRECONFIGURED_MATCH" ]]; then
        row "ROM"  "pre-configured ($PRECONFIGURED_MATCH) — selection skipped"
    fi

    menu "Ready to clone?" "Yes, start cloning" "No, cancel"
    if (( MENU_INDEX != 0 )); then
        info "Nothing was cloned. Bye!"
        exit 0
    fi
}

step_clone() {
    local entry
    section "Cloning"
    clone "$KEYS_URL"    "$KEYS_DEST"
    clone "$DEVICE_REPO" "$DEVICE" "$DEVICE_BRANCH"
    clone "$VENDOR_REPO" vendor/xiaomi/redwood
    for entry in "${EXTRA_REPOS[@]}"; do
        clone "${entry%%|*}" "${entry#*|}"
    done

    printf '\n'
    if (( SKIPPED > 0 )); then
        ok "Cloned $CLONED repositories, skipped $SKIPPED"
    else
        ok "All $CLONED repositories cloned"
    fi
}

# revert_commits DEST SHA...  — reverts the given commits, newest first
revert_commits() {
    local dest="$1"; shift
    local sha full short subject line
    local -a wanted=() ordered=() gitid=()

    info "${BOLD}$dest${NC}"
    if ! git -C "$dest" rev-parse --git-dir >/dev/null 2>&1; then
        warn "  not a git repository — skipped"
        return
    fi

    # git revert needs an identity to commit; borrow a throwaway one if unset
    if [[ -z "$(git config user.name)" || -z "$(git config user.email)" ]]; then
        gitid=(-c user.name="clone.sh" -c user.email="clone@localhost")
    fi

    # keep only commits that really are in this checkout's history
    for sha in "$@"; do
        short="${sha:0:9}"
        if ! full=$(git -C "$dest" rev-parse --verify --quiet "$sha^{commit}"); then
            warn "  $short not found — skipped"
            continue
        fi
        if ! git -C "$dest" merge-base --is-ancestor "$full" HEAD; then
            warn "  $short is not in this branch's history — skipped"
            continue
        fi
        wanted+=("$full")
    done
    (( ${#wanted[@]} > 0 )) || return

    # newest first, regardless of the order they were listed in
    mapfile -t ordered < <(git -C "$dest" rev-list HEAD | grep -Fx -f <(printf '%s\n' "${wanted[@]}"))

    for full in "${ordered[@]}"; do
        short="${full:0:9}"
        # Re-running on an existing checkout must not revert the revert
        if [[ -n "$(git -C "$dest" log -n1 --format=%H --grep="This reverts commit $full" HEAD)" ]]; then
            ok "  $short already reverted"
            continue
        fi

        subject=$(git -C "$dest" log -n1 --format=%s "$full")
        spin "Reverting $short in $dest" git "${gitid[@]}" -C "$dest" revert --no-edit "$full"
        if (( SPIN_RC != 0 )); then
            fail "  Could not revert ${BOLD}$short${NC} ${DIM}(${subject:0:50})${NC}"
            while IFS= read -r line; do
                printf '        %s%s%s\n' "$DIM" "$line" "$NC" >&2
            done < <(grep -hE 'CONFLICT|error:' "$SPIN_OUT" "$SPIN_ERR" | head -n 4)
            git -C "$dest" revert --abort >/dev/null 2>&1
            REVERT_FAILED=$((REVERT_FAILED + 1))
            warn "  Stopped $dest here — later commits may depend on this one"
            return
        fi
        REVERTED=$((REVERTED + 1))
        ok "  Reverted $short ${DIM}(${subject:0:50})${NC}"
    done
}

step_a16() {
    section "Android version"
    row "Device"  "$A16_DEVICE_PATH  ·  revert ${#A16_DEVICE_REVERTS[@]} commits"
    row "Camera"  "$A16_CAMERA_PATH  ·  revert ${#A16_CAMERA_REVERTS[@]} commit"
    row "Vendor"  "$A16_VENDOR_PATH  ·  re-clone @ $A16_VENDOR_BRANCH"

    menu "Make tree A16?" \
        "Yes${TAB}apply the changes above" \
        "Skip${TAB}keep the trees as cloned"
    if (( MENU_INDEX != 0 )); then
        info "Skipped — trees stay as cloned"
        return 0
    fi

    # Check the vendor branch exists *before* deleting anything
    spin "Checking branch $A16_VENDOR_BRANCH" git ls-remote --exit-code --heads "$VENDOR_REPO" "$A16_VENDOR_BRANCH"
    if (( SPIN_RC != 0 )); then
        fail "Branch '$A16_VENDOR_BRANCH' not found on $(basename "$VENDOR_REPO") — nothing was changed"
        show_spin_error
        return 0
    fi

    printf '\n'
    revert_commits "$A16_DEVICE_PATH" "${A16_DEVICE_REVERTS[@]}"
    revert_commits "$A16_CAMERA_PATH" "${A16_CAMERA_REVERTS[@]}"

    info "${BOLD}$A16_VENDOR_PATH${NC}"
    [[ -n "$A16_VENDOR_PATH" ]] && rm -rf -- "$A16_VENDOR_PATH"
    clone "$VENDOR_REPO" "$A16_VENDOR_PATH" "$A16_VENDOR_BRANCH"

    printf '\n'
    if (( REVERT_FAILED > 0 )); then
        warn "Reverted $REVERTED commits, $REVERT_FAILED failed — fix those repos manually"
    else
        ok "Tree is now A16  ${DIM}($REVERTED commits reverted, vendor on $A16_VENDOR_BRANCH)${NC}"
    fi
}

manual_edit() {
    local target editor="${EDITOR:-nano}"
    section "Manual mode"
    ask "Product mk filename (e.g. lineage_redwood.mk / spark_redwood.mk)"
    target="$DEVICE/$ASK_REPLY"

    if [[ -f "$target" ]]; then
        ok "Found $target"
        menu "What next?" "Open in $editor" "Exit and edit manually"
        case $MENU_INDEX in
            0) "$editor" "$target"; ok "File edited" ;;
            *) info "File location: $target"; exit 0 ;;
        esac
    else
        warn "$target not found"
        menu "What next?" "Create and open in $editor" "Exit and create manually"
        case $MENU_INDEX in
            0) touch "$target"; "$editor" "$target"; ok "File created and edited" ;;
            *) info "Expected location: $target"; exit 0 ;;
        esac
    fi
}

apply_rom() {
    local f new_file
    section "ROM configuration"
    info "Applying changes for ${BOLD}$ROM${NC}"

    for f in "$ANDROID_PRODUCTS" "$BOARD_CONFIG" "$LINEAGE_MK"; do
        if [[ ! -f "$f" ]]; then
            fail "Missing file: $f"
            exit 1
        fi
    done

    if [[ "$ROM" == "axion" || "$ROM" == "derpfest" ]]; then
        warn "This ROM uses a Lineage base — keeping the lineage prefix"
    else
        sed -i "/device\/lineage\/sepolicy/!s/lineage/$PREFIX/g" "$ANDROID_PRODUCTS" "$BOARD_CONFIG" "$LINEAGE_MK"
        new_file="$DEVICE/${PREFIX}_redwood.mk"
        if [[ "$LINEAGE_MK" != "$new_file" ]]; then
            mv "$LINEAGE_MK" "$new_file"
            LINEAGE_MK="$new_file"
        fi
        ok "Product makefile is now ${BOLD}${PREFIX}_redwood.mk${NC}"
    fi

    if [[ -n "$FLAGS" ]]; then
        printf '%s\n' "$FLAGS" >> "$LINEAGE_MK"
        ok "Flags appended to $LINEAGE_MK"
    fi

    if [[ "$ROM" == "axion" ]]; then
        cat >> "$SYSTEM_PROP" << 'EOF'

# Axion - Scroll Optimizer
persist.sys.perf.scroll_opt=true
persist.sys.perf.scroll_opt.heavy_app=2
EOF
        ok "Axion system props added"
    fi

    if [[ "$ROM" == "infinity" ]]; then
        if grep -q 'persist.vendor.cne.feature=1' "$SYSTEM_PROP"; then
            sed -i '/persist.vendor.cne.feature=1/a\
\
# Infinity\
ro.product.marketname=Poco X5 Pro 5G\
ro.infinity.soc=Snapdragon 778G 5G\
ro.infinity.battery=5000 mAh\
ro.infinity.display=1080 x 2400, 120 Hz\
ro.infinity.camera=108MP + 8MP + 2MP' "$SYSTEM_PROP"
            ok "Infinity system props added"
        else
            warn "Anchor line 'persist.vendor.cne.feature=1' not found in $SYSTEM_PROP — Infinity props NOT added"
        fi
    fi
}

finish() {
    local elapsed=$((SECONDS - START_TIME)) status="ROM configuration completed"
    [[ -n "$PRECONFIGURED_MATCH" ]] && status="Pre-configured branch - no ROM changes needed"
    box "$GREEN" "All done!" "$status" "You can now proceed to build." \
        "Finished in $((elapsed / 60))m $((elapsed % 60))s"
    printf '\n'
}

main() {
    WORK_TMP=$(mktemp -d)
    banner
    step_keys
    step_branch
    step_review
    step_clone
    step_a16
    if [[ -n "$PRECONFIGURED_MATCH" ]]; then
        section "ROM selection"
        info "Branch ${BOLD}$DEVICE_BRANCH${NC} is already configured — skipping ROM selection"
    else
        step_rom
        if [[ "$ROM" == "custom_manual" ]]; then
            manual_edit
        else
            apply_rom
        fi
    fi
    finish
}

main "$@"
