#!/bin/bash

echo ""
echo "====================================="
echo "  Welcome to BlueHeart Clone Script  "
echo "====================================="
echo ""

# Function: clone repo with branch selection
clone_repo_branch() {

REPO=$1
DEST=$2

echo ""
echo "Fetching branches from:"
echo "$REPO"
echo ""

branches=$(git ls-remote --heads $REPO | awk '{print $2}' | sed 's|refs/heads/||')

select branch in $branches
do
if [ -n "$branch" ]; then
echo ""
echo "Cloning branch: $branch"
git clone --depth=1 -b $branch $REPO $DEST
break
else
echo "Invalid selection"
fi
done
}

# Function: clone repo normally
clone_repo() {

REPO=$1
DEST=$2

echo ""
echo "Cloning $REPO"
git clone --depth=1 $REPO $DEST

}

# Clone device tree (ask branch)
clone_repo_branch https://github.com/BlueHeart01/device_xiaomi_redwood.git device/xiaomi/redwood

echo ""
echo "Device tree cloned successfully!"
echo ""

# Clone additional trees
clone_repo https://github.com/BlueHeart01/vendor_xiaomi_redwood.git vendor/xiaomi/redwood
clone_repo https://github.com/Redwood-AOSP/android_device_xiaomi_redwood-kernel.git device/xiaomi/redwood-kernel
clone_repo https://github.com/BlueHeart01/redwood_vendor_xiaomi_redwood-miuicamera.git vendor/xiaomi/redwood-miuicamera
clone_repo https://github.com/BlueHeart01/vendor_oneplus_dolby.git vendor/oneplus/dolby
clone_repo https://github.com/BlueHeart01/hardware_xiaomi.git hardware/xiaomi
clone_repo https://github.com/BlueHeart01/vendor_bcr.git vendor/bcr

echo ""
echo "All additional trees cloned successfully!"
echo ""

# ROM selection menu
echo "Select ROM to configure:"
echo ""
echo "1) Infinity"
echo "2) Avium"
echo "3) Clover"
echo "4) Axion"
echo "5) PixelOS"
echo "6) EuclidOS"
echo "7) Derpfest"
echo ""

read -p "Enter ROM name or number: " ROM

case "$ROM" in
1) ROM="infinity" ;;
2) ROM="avium" ;;
3) ROM="clover" ;;
4) ROM="axion" ;;
5) ROM="pixelos" ;;
6) ROM="euclid" ;;
7) ROM="derpfest" ;;
esac

ROM=$(echo $ROM | tr '[:upper:]' '[:lower:]')

echo ""
echo "You selected ROM: $ROM"
echo ""

DEVICE=device/xiaomi/redwood
ANDROID_PRODUCTS=$DEVICE/AndroidProducts.mk
BOARD_CONFIG=$DEVICE/BoardConfig.mk
LINEAGE_MK=$DEVICE/lineage_redwood.mk

# ROM specific configuration
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
AXION_CAMERA_REAR_INFO := 12,8,2
AXION_CAMERA_FRONT_INFO := 16
AXION_MAINTAINER := Sᴀʏᴀɴシ
AXION_PROCESSOR := Snapdragon778G
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
WITH_GMS := true
WITH_GAPPS := true
'
;;

*)

echo "Invalid ROM selected"
exit 1

;;

esac

echo ""
echo "Applying ROM specific changes..."

# Axion & Derpfest keep lineage base
if [[ "$ROM" == "axion" || "$ROM" == "derpfest" ]]; then

echo "This ROM uses Lineage base configuration."
echo "Skipping lineage replacement."

else

sed -i "s/lineage/$PREFIX/g" $ANDROID_PRODUCTS
sed -i "s/lineage/$PREFIX/g" $BOARD_CONFIG
sed -i "s/lineage/$PREFIX/g" $LINEAGE_MK

NEW_FILE=$DEVICE/${PREFIX}_redwood.mk
mv $LINEAGE_MK $NEW_FILE

echo "File renamed to: ${PREFIX}_redwood.mk"

LINEAGE_MK=$NEW_FILE

fi

# Add flags
echo "$FLAGS" >> $LINEAGE_MK

echo ""
echo "====================================="
echo "ROM specific changes completed!"
echo "You can now proceed to build your ROM"
echo "====================================="
echo ""
