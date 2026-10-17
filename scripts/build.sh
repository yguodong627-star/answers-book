#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
build_platform="${1:-simulator}"
simulator_id="${2:-}"

if ! xcodebuild -version > /dev/null 2>&1; then
  print -u2 -- "需要完整的Xcode。请先打开Xcode完成首次安装，并在Settings → Locations中选择Command Line Tools。"
  exit 1
fi

case "$build_platform" in
  simulator)
    destination="generic/platform=iOS Simulator"
    if [[ -n "$simulator_id" ]]; then
      destination="platform=iOS Simulator,id=$simulator_id"
    fi
    ;;
  device)
    destination="generic/platform=iOS"
    ;;
  *)
    print -u2 -- "用法：./scripts/build.sh [simulator|device] [模拟器UUID]"
    exit 2
    ;;
esac

mkdir -p "$project_root/.build/logs"
build_log="$project_root/.build/logs/build-$build_platform.log"
print -- "正在构建 AnswersBook（$build_platform）……"

if ! xcodebuild \
  -project "$project_root/ios/AnswersBook.xcodeproj" \
  -scheme AnswersBook \
  -configuration Debug \
  -destination "$destination" \
  -derivedDataPath "$project_root/.build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build > "$build_log" 2>&1; then
  tail -n 80 "$build_log" >&2
  print -u2 -- "构建失败，完整日志：$build_log"
  exit 1
fi

print -- "BUILD SUCCEEDED：AnswersBook（$build_platform）"
print -- "完整日志：$build_log"

