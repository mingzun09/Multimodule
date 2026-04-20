#!/sbin/sh

# ==========================================
# 环境变量定义与配置
# ==========================================
MODDIR="$MODPATH"
MODULES_DIR="/data/adb/modules"

# Root 管理器最低版本要求 (引入自参考脚本)
MIN_KSU_VERSION=10940
MIN_KSUD_VERSION=11575
MIN_MAGISK_VERSION=26402
MIN_APATCH_VERSION=10700

# ==========================================
# 环境校验 (融合并强化多管理器支持)
# ==========================================
if [ "$BOOTMODE" ] && [ "$KSU" ]; then
  ui_print "- 正在从 KernelSU 安装"
  if ! [ "$KSU_KERNEL_VER_CODE" ] || [ "$KSU_KERNEL_VER_CODE" -lt "$MIN_KSU_VERSION" ]; then
    abort "! KernelSU 内核版本过低！请更新至最新版。"
  fi
  if ! [ "$KSU_VER_CODE" ] || [ "$KSU_VER_CODE" -lt "$MIN_KSUD_VERSION" ]; then
    abort "! ksud 版本过低！请更新 KernelSU 管理器至最新版。"
  fi
  if [ "$(which magisk)" ]; then
    abort "! 检测到多重 Root 冲突，请卸载 Magisk 后再在 KSU 中操作！"
  fi
elif [ "$BOOTMODE" ] && [ "$APATCH" ]; then
  ui_print "- 正在从 APatch 安装"
  if ! [ "$APATCH_VER_CODE" ] || [ "$APATCH_VER_CODE" -lt "$MIN_APATCH_VERSION" ]; then
    abort "! APatch 版本过低！请更新至最新版。"
  fi
elif [ "$BOOTMODE" ] && [ "$MAGISK_VER_CODE" ]; then
  ui_print "- 正在从 Magisk 安装"
  if [ "$MAGISK_VER_CODE" -lt "$MIN_MAGISK_VERSION" ]; then
    abort "! Magisk 版本过低！请更新至最新版。"
  fi
else
  ui_print "*********************************************************"
  ui_print "! 不支持在 Recovery 模式下安装，或无法识别 Root 环境"
  ui_print "! 请在 Magisk / KernelSU / APatch 应用内执行刷入"
  abort    "*********************************************************"
fi

ui_print "**********************************"
ui_print "  多功能模块安装程序 v3.0 (多端兼容)"
ui_print "  - 完美兼容 Magisk/KSU/APatch"
ui_print "  - 使用原生安全 APK 安装机制"
ui_print "**********************************"

# ==========================================
# 子模块安装 (修复原生命令兼容性)
# ==========================================
ui_print "- 开始处理嵌套子模块..."
MODULE_COUNT=0
MODULE_FILES="$MODPATH/modules"/*.zip

if [ ! -d "$MODPATH/modules" ]; then
  ui_print "  ⚠ 模块目录不存在: $MODPATH/modules，跳过..."
else
  for module in $MODULE_FILES; do
    if [ -f "$module" ]; then
      MODULE_COUNT=$((MODULE_COUNT + 1))
      ui_print "正在准备模块 [$MODULE_COUNT]: $(basename "$module")"
      
      # 提取 module.prop 以校验并防止重复安装
      TMP_PROP_DIR="$MODPATH/tmp_prop_$RANDOM"
      mkdir -p "$TMP_PROP_DIR"
      unzip -p "$module" module.prop 2>/dev/null | head -c 1024 > "$TMP_PROP_DIR/module.prop"
      
      if [ $? -ne 0 ] || [ ! -s "$TMP_PROP_DIR/module.prop" ]; then
        ui_print "  ✘ 模块损坏: 无法提取 module.prop"
        rm -rf "$TMP_PROP_DIR"
        continue
      fi
      
      module_id=$(grep -m1 '^id=' "$TMP_PROP_DIR/module.prop" | cut -d= -f2- | tr -d '\r" ')
      rm -rf "$TMP_PROP_DIR"

      if [ -z "$module_id" ]; then
        ui_print "  ✘ 模块无效: 未检测到有效 ID"
        continue
      fi

      existing_dir=$(find "$MODULES_DIR" -maxdepth 1 -iname "$module_id" -print -quit)
      if [ -n "$existing_dir" ]; then
        ui_print "  ! 检测到已安装: $(basename "$existing_dir")，跳过安装"
        continue
      fi

      ui_print "  -> 正在向系统注入模块: $module_id"
      
      # 动态识别当前管理器的专属安装命令
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
          ui_print "  ✘ 当前 Root 环境缺乏支持的模块安装命令接口"
          continue
      fi

      if [ $install_status -eq 0 ]; then
          ui_print "  ✔ 成功安装子模块: $module_id"
      else
          ui_print "  ✘ 安装子模块失败，管理器错误码: $install_status"
      fi
    fi
  done
  
  if [ $MODULE_COUNT -eq 0 ]; then
    ui_print "  未找到任何 ZIP 模块文件"
  else
    ui_print "  共尝试处理 $MODULE_COUNT 个子模块"
  fi
fi

# ==========================================
# APK 安装逻辑 (修复与重构)
# ==========================================
install_apk() {
  local apk_path="$1"
  # 模块刷入环境本身即是 Root，直接采用 pm install 即可。移除冗余 su 逻辑。
  # -r: 替换已存在应用, -d: 允许降级
  
  result=$(pm install -r -d "$apk_path" 2>&1)
  if echo "$result" | grep -q -i "Success"; then
    ui_print "  ✔ 已安装: $(basename "$apk_path")"
    return 0
  else
    ui_print "  ! 标准安装受阻，尝试流式注入 (针对 Android 13+ 权限拦截)..."
    # 通过 cat 绕过包管理器对 /data/adb/modules 临时目录的直接读取限制
    result2=$(cat "$apk_path" | pm install -S $(stat -c %s "$apk_path") -r -d 2>&1)
    if echo "$result2" | grep -q -i "Success"; then
      ui_print "  ✔ 备选方案注入成功: $(basename "$apk_path")"
      return 0
    else
      ui_print "  ✘ 安装失败: $(basename "$apk_path")"
      # 输出部分错误信息便于排障
      ui_print "    > $(echo "$result2" | head -n 2)" 
      return 1
    fi
  fi
}

ui_print "- 安装系统应用..."
APK_SRC_DIR="$MODPATH/system/priv-app"
if [ -d "$APK_SRC_DIR" ]; then
  find "$APK_SRC_DIR" -type f -name "*.apk" | while read apk; do
    if [ ! -s "$apk" ]; then
      ui_print "  ✘ 文件体积异常/损坏: $(basename "$apk")"
      continue
    fi
    chcon u:object_r:apk_data_file:s0 "$apk"
    if install_apk "$apk"; then
      sleep 1
    fi
  done
else
  ui_print "  ⚠ 未检测到需要安装的 APK 目录"
fi

ui_print "所有处理流程结束！"
ui_print "- 请重启设备以应用生效 -"

# ==========================================
# 环境自清理 (一次性部署模块的常规做法)
# ==========================================
ui_print "- 正在移除本安装包留存数据..."
rm -rf "$MODPATH"
