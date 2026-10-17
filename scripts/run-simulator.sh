#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
simulator_id="${1:-}"
developer_dir="$(xcode-select -p)"

# Xcode 27使用Device Hub，较早版本使用Simulator。
if [[ -d "$developer_dir/../Applications/DeviceHub.app" ]]; then
  simulator_window_app="$developer_dir/../Applications/DeviceHub.app"
elif [[ -d "$developer_dir/Applications/Simulator.app" ]]; then
  simulator_window_app="$developer_dir/Applications/Simulator.app"
else
  print -u2 -- "找不到Device Hub或Simulator窗口应用。请确认已安装完整Xcode，并正确选择Command Line Tools。"
  exit 1
fi

if [[ -z "$simulator_id" ]]; then
  if ! available_devices="$(xcrun simctl list devices available)"; then
    print -u2 -- "无法读取模拟器。请先启动Xcode，完成首次组件安装，再重试。"
    exit 1
  fi

  # 优先复用已启动的iPhone，否则选择第一个可用iPhone。
  simulator_id="$(print -r -- "$available_devices" | sed -nE '/iPhone/s/.*\(([0-9A-Fa-f-]{36})\) \(Booted\).*/\1/p' | head -n 1)"
  if [[ -z "$simulator_id" ]]; then
    simulator_id="$(print -r -- "$available_devices" | sed -nE '/iPhone/s/.*\(([0-9A-Fa-f-]{36})\).*/\1/p' | head -n 1)"
  fi
fi

if [[ -z "$simulator_id" ]]; then
  print -u2 -- "没有可用的iPhone模拟器。"
  print -u2 -- "请在Xcode → Settings → Components中安装iOS Simulator运行时。"
  print -u2 -- "若已安装，请在Xcode → Open Developer Tool → Device Hub中创建iPhone模拟器；旧版Xcode使用Window → Devices and Simulators。"
  print -u2 -- "完成后重新运行：./scripts/run-simulator.sh"
  exit 1
fi

# 已启动的设备无需再次boot，其他boot错误仍正常报告。
if ! xcrun simctl list devices booted | grep -Fq "$simulator_id"; then
  xcrun simctl boot "$simulator_id"
fi
open -a "$simulator_window_app"
xcrun simctl bootstatus "$simulator_id" -b

"$project_root/scripts/build.sh" simulator "$simulator_id"
app_path="$project_root/.build/DerivedData/Build/Products/Debug-iphonesimulator/AnswersBook.app"
xcrun simctl install "$simulator_id" "$app_path"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")"
xcrun simctl launch --terminate-running-process "$simulator_id" "$bundle_id"

print -- "启动成功：请在模拟器中确认暖灯书房合书场景；左滑开书、右滑文字淡去后合书（固定示例原型）。"
print -- "若Device Hub显示设备列表，请打开正在运行的iPhone设备，查看应用画面。"

