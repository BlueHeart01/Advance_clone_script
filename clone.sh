#!/bin/bash

echo ""
echo "====================================="
echo "  Welcome to BlueHeart Clone Script  "
echo "====================================="
echo ""

# ─── Colors ───────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Helper Functions ─────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# Clone with branch selection
clone_repo_branch() {
    local REPO=$1
    local DEST=$2

    echo ""
    info "Fetching branches from: $REPO"
    echo ""

    branches=$(git ls-remote --heads "$REPO" | awk '{print $2}' | sed 's|refs/heads/||')

    select branch in $branches; do
        if [ -n "$branch" ]; then
            info "Cloning branch: $branch"
            git clone --depth=1 -b "$branch" "$REPO" "$DEST"
            success "Cloned: $DEST"
            break
        else
            error "Invalid selection, try again."
        fi
    done
}

# Clone normally (default branch)
clone_repo() {
    local REPO=$1
    local DEST=$2
    info "Cloning $REPO → $DEST"
    git clone --depth=1 "$REPO" "$DEST"
    success "Cloned: $DEST"
}

# ─── Clone Trees ──────────────────────────────────────────
clone_repo_branch https://github.com/BlueHeart01/device_xiaomi_redwood.git device/xiaomi/redwood

clone_repo https://github.com/BlueHeart01/vendor_xiaomi_redwood.git vendor/xiaomi/redwood
clone_repo https://github.com/Redwood-AOSP/android_device_xiaomi_redwood-kernel.git device/xiaomi/redwood-kernel
clone_repo https://github.com/BlueHeart01/redwood_vendor_xiaomi_redwood-miuicamera.git vendor/xiaomi/redwood-miuicamera
clone_repo https://github.com/BlueHeart01/vendor_oneplus_dolby.git vendor/oneplus/dolby
clone_repo https://github.com/BlueHeart01/hardware_xiaomi.git hardware/xiaomi
clone_repo https://github.com/BlueHeart01/vendor_bcr.git vendor/bcr

echo ""
success "All trees cloned successfully!"
echo ""

# ─── ROM Selection ────────────────────────────────────────
echo -e "${BOLD}Select ROM to configure:${NC}"
echo ""
echo "  1) Infinity"
echo "  2) Avium"
echo "  3) Clover"
echo "  4) Axion"
echo "  5) PixelOS"
echo "  6) EuclidOS"
echo "  7) Derpfest"
echo "  8) Other (unlisted ROM - enter name manually)"
echo "  9) Custom (manually edit product mk file)"
echo ""
read -p "Enter ROM name or number: " ROM_INPUT

# Normalize input
ROM=$(echo "$ROM_INPUT" | tr '[:upper:]' '[:lower:]' | xargs)

case "$ROM" in
    1|infinity)   ROM="infinity" ;;
    2|avium)      ROM="avium" ;;
    3|clover)     ROM="clover" ;;
    4|axion)      ROM="axion" ;;
    5|pixelos)    ROM="pixelos" ;;
    6|euclid*)    ROM="euclid" ;;
    7|derpfest)   ROM="derpfest" ;;
    8|other)
        echo ""
        read -p "Enter ROM name (e.g. spark, rising, voltage): " ROM
        ROM=$(echo "$ROM" | tr '[:upper:]' '[:lower:]' | xargs)
        ;;
    9|custom|manual)
        ROM="custom_manual"
        ;;
esac

echo ""
info "Selected ROM: $ROM"
echo ""

# ─── Paths ────────────────────────────────────────────────
DEVICE=device/xiaomi/redwood
ANDROID_PRODUCTS=$DEVICE/AndroidProducts.mk
BOARD_CONFIG=$DEVICE/BoardConfig.mk
LINEAGE_MK=$DEVICE/lineage_redwood.mk
SYSTEM_PROP=$DEVICE/configs/props/system.prop

# ─── ROM Flags ────────────────────────────────────────────
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
TARGET_INCLUDE_VIPERFX := true
TARGET_ENABLE_BLUR := true
TARGET_INCLUDES_LOS_PREBUILTS := true

# Camera information
AXION_CAMERA_REAR_INFO := 12,8,2
AXION_CAMERA_FRONT_INFO := 16

# Maintainer & Device info
AXION_MAINTAINER := Sᴀʏᴀɴシ
AXION_PROCESSOR := Snapdragon_778G

# Charging
BYPASS_CHARGE_SUPPORTED := true
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

custom_manual)
    echo ""
    warn "Manual mode selected."
    echo ""
    read -p "Enter your product mk filename (e.g. lineage_redwood.mk / spark_redwood.mk): " MK_NAME
    MK_TARGET=$DEVICE/$MK_NAME

    if [ -f "$MK_TARGET" ]; then
        echo ""
        info "File found: $MK_TARGET"
        echo ""
        echo "  1) Open in nano"
        echo "  2) Exit script and edit manually"
        echo ""
        read -p "Choose option: " EDIT_CHOICE
        case "$EDIT_CHOICE" in
            1)
                nano "$MK_TARGET"
                success "File edited successfully."
                ;;
            2)
                echo ""
                info "File location: $MK_TARGET"
                success "Exiting. Edit the file manually and build when ready."
                exit 0
                ;;
            *)
                error "Invalid choice. Exiting."
                exit 1
                ;;
        esac
    else
        echo ""
        warn "File $MK_TARGET not found."
        echo ""
        echo "  1) Create and open in nano"
        echo "  2) Exit script and create manually"
        echo ""
        read -p "Choose option: " CREATE_CHOICE
        case "$CREATE_CHOICE" in
            1)
                touch "$MK_TARGET"
                nano "$MK_TARGET"
                success "File created and edited."
                ;;
            2)
                echo ""
                info "Expected location: $MK_TARGET"
                success "Exiting. Create the file manually and build when ready."
                exit 0
                ;;
            *)
                error "Invalid choice. Exiting."
                exit 1
                ;;
        esac
    fi
    echo ""
    success "Manual edit done. Exiting."
    exit 0
    ;;

*)
    # Unknown ROM - ask for prefix and flags manually
    echo ""
    warn "ROM '$ROM' is not in the preset list."
    echo ""
    read -p "Enter the product prefix for this ROM (e.g. spark, voltage, rising): " PREFIX
    PREFIX=$(echo "$PREFIX" | tr '[:upper:]' '[:lower:]' | xargs)
    echo ""
    info "Enter custom flags one per line (e.g. WITH_GMS := true)."
    info "Press Enter on an empty line when done."
    echo ""
    FLAGS=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && break
        FLAGS="$FLAGS
$line"
    done
    ;;

esac

# ─── Apply ROM Changes ────────────────────────────────────
echo ""
info "Applying ROM specific changes for: $ROM"

# Axion & Derpfest keep lineage base
if [[ "$ROM" == "axion" || "$ROM" == "derpfest" ]]; then
    warn "This ROM uses Lineage base — skipping lineage prefix replacement."
else
    sed -i "s/lineage/$PREFIX/g" "$ANDROID_PRODUCTS"
    sed -i "s/lineage/$PREFIX/g" "$BOARD_CONFIG"
    sed -i "s/lineage/$PREFIX/g" "$LINEAGE_MK"

    NEW_FILE=$DEVICE/${PREFIX}_redwood.mk
    mv "$LINEAGE_MK" "$NEW_FILE"
    LINEAGE_MK=$NEW_FILE
    success "Renamed product mk to: ${PREFIX}_redwood.mk"
fi

# Append flags
if [ -n "$FLAGS" ]; then
    echo "$FLAGS" >> "$LINEAGE_MK"
    success "Flags appended to: $LINEAGE_MK"
fi

# ─── Axion system props ───────────────────────────────────
if [[ "$ROM" == "axion" ]]; then
    info "Adding Axion scroll optimizer system properties..."
    cat >> "$SYSTEM_PROP" << 'EOF'

# Axion - Scroll Optimizer
persist.sys.perf.scroll_opt=true
persist.sys.perf.scroll_opt.heavy_app=2
EOF
    success "Axion system props added."
fi

# ─── Infinity system props ────────────────────────────────
if [[ "$ROM" == "infinity" ]]; then
    info "Adding Infinity system properties..."
    sed -i '/persist.vendor.cne.feature=1/a\
\
# Infinity\
ro.product.marketname=Poco X5 Pro 5G\
ro.infinity.soc=Snapdragon 778G 5G\
ro.infinity.battery=5000 mAh\
ro.infinity.display=1080 x 2400, 120 Hz\
ro.infinity.camera=108MP + 8MP + 2MP' "$SYSTEM_PROP"
    success "Infinity system props added."
fi

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  ROM configuration completed!       ${NC}"
echo -e "${GREEN}  You can now proceed to build.      ${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
