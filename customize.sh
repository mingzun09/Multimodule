#!/sbin/sh

MODDIR="$MODPATH"
MODULES_DIR="/data/adb/modules"
MIN_KSU_VERSION=10940
MIN_KSUD_VERSION=11575
MIN_MAGISK_VERSION=26402
MIN_APATCH_VERSION=10700

if [ "$BOOTMODE" ] && [ "$KSU" ]; then
  ui_print "- Installing from KernelSU"
  if ! [ "$KSU_KERNEL_VER_CODE" ] || [ "$KSU_KERNEL_VER_CODE" -lt "$MIN_KSU_VERSION" ]; then
    abort "! KernelSU kernel version is too low! Please update to the latest version."
  fi
  if ! [ "$KSU_VER_CODE" ] || [ "$KSU_VER_CODE" -lt "$MIN_KSUD_VERSION" ]; then
    abort "! Ksud version is too low! Please update KernelSU Manager to the latest version."
  fi
  if [ "$(which magisk)" ]; then
    abort "! Multiple Root conflicts have been detected. Please uninstall Magisk before operating in KSU!"
  fi
elif [ "$BOOTMODE" ] && [ "$APATCH" ]; then
  ui_print "- Installing from APatch"
  if ! [ "$APATCH_VER_CODE" ] || [ "$APATCH_VER_CODE" -lt "$MIN_APATCH_VERSION" ]; then
    abort "! APatch version is too low! Please update to the latest version."
  fi
elif [ "$BOOTMODE" ] && [ "$MAGISK_VER_CODE" ]; then
  ui_print "- Installing from Magisk"
  if [ "$MAGISK_VER_CODE" -lt "$MIN_MAGISK_VERSION" ]; then
    abort "! Magisk version too low! Please update to the latest version."
  fi
else
  ui_print "*********************************************************"
  ui_print "! Installation in Recovery mode is not supported, or the Root environment is not recognized."
  ui_print "! Please perform swiping in Magisk/KernelSU/APatch application."
  abort    "*********************************************************"
fi
ui_print "**********************************"
ui_print "  Multimodule_v3.0 (Install_apk)"
ui_print "  - Perfect compatibility_Magisk/KSU/APatch"
ui_print "  - Use the native secure APK installation mechanism"
ui_print "**********************************"
ui_print "- Start processing nested submodules..."
MODULE_COUNT=0
MODULE_FILES="$MODPATH/modules"/*.zip

if [ ! -d "$MODPATH/modules" ]; then
  ui_print "  ⚠ Module directory does not exist: $MODPATH/modules，skip..."
else
  for module in $MODULE_FILES; do
    if [ -f "$module" ]; then
      MODULE_COUNT=$((MODULE_COUNT + 1))
      ui_print "Preparing module [$MODULE_COUNT]: $(basename "$module")"
      
      TMP_PROP_DIR="$MODPATH/tmp_prop_$RANDOM"
      mkdir -p "$TMP_PROP_DIR"
      unzip -p "$module" module.prop 2>/dev/null | head -c 1024 > "$TMP_PROP_DIR/module.prop"
      
      if [ $? -ne 0 ] || [ ! -s "$TMP_PROP_DIR/module.prop" ]; then
        ui_print "  ✘ Module corruption: unable to extract module.prop"
        rm -rf "$TMP_PROP_DIR"
        continue
      fi
      
      module_id=$(grep -m1 '^id=' "$TMP_PROP_DIR/module.prop" | cut -d= -f2- | tr -d '\r" ')
      rm -rf "$TMP_PROP_DIR"
      if [ -z "$module_id" ]; then
        ui_print "  ✘ flash module: No valid ID detected."
        continue
      fi
      existing_dir=$(find "$MODULES_DIR" -maxdepth 1 -iname "$module_id" -print -quit)
      if [ -n "$existing_dir" ]; then
        ui_print "  ! flash detected: $(basename "$existing_dir")，Skip flash"
        continue
      fi

      ui_print "  -> Flash submodule in progress: $module_id"
      
      install_status=1
      if [ -n "$KSU" ] && command -v ksud >/dev/null 2>&1; then
          ksud module install "$module"
          install_status=$?
      elif [ -n "$APATCH" ] && command -v apmod >/dev/null 2>&1; then
          apmod install "$module"
          install_status=$?
      elif command -v magisk >/dev/null 2>&1; then
          magisk --install-module "$module"
          install_status=$?
      else
          ui_print "  ✘ The current Root environment lacks a supported module installation command interface."
          continue
      fi

      if [ $install_status -eq 0 ]; then
          ui_print "  ✔ Successful flash submodule: $module_id"
      else
          ui_print "  ✘ Flash submodule failed, manager error code: $install_status"
      fi
    fi
  done
  
  if [ $MODULE_COUNT -eq 0 ]; then
    ui_print "  No module files were found."
  else
    ui_print "  Processed $MODULE_COUNT Submodule"
  fi
fi
install_apk() {
  local apk_path="$1"
  result=$(pm install -r -d "$apk_path" 2>&1)
  if echo "$result" | grep -q -i "Success"; then
    ui_print "  ✔ Installed: $(basename "$apk_path")"
    return 0
  else
    ui_print "  ! Standard installation blocked, try streaming injection (for Android 13+ permission interception)..."
    result2=$(cat "$apk_path" | pm install -S $(stat -c %s "$apk_path") -r -d 2>&1)
    if echo "$result2" | grep -q -i "Success"; then
      ui_print "  ✔ Alternative injection succeeded: $(basename "$apk_path")"
      return 0
    else
      ui_print "  ✘ Installation failed: $(basename "$apk_path")"

      ui_print "    > $(echo "$result2" | head -n 2)" 
      return 1
    fi
  fi
}

ui_print "- set up applications..."
APK_SRC_DIR="$MODPATH/system/priv-app"
if [ -d "$APK_SRC_DIR" ]; then
  find "$APK_SRC_DIR" -type f -name "*.apk" | while read apk; do
    if [ ! -s "$apk" ]; then
      ui_print "  ✘ Abnormal/corrupt file volume: $(basename "$apk")"
      continue
    fi
    chcon u:object_r:apk_data_file:s0 "$apk"
    if install_apk "$apk"; then
      sleep 1
    fi
  done
else
  ui_print "  ⚠ The APK directory to be installed was not detected"
fi

ui_print "😋All processes deal with done！"
ui_print "- Please reboot to apply to take effect. -"
ui_print "- Cleaning up Multimodule retained data...."
rm -rf "$MODPATH"
