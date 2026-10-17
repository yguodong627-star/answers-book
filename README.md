# 答案之书 · The Book of Answers

把犹豫交给一页纸。为日常小事犹豫时，默念一个问题、翻开书，遇见一句中英双语启发；用收藏和备注留住当时的心情。

版本：iOS 0.14.1（构建41）／网页体验 V1.0｜日期：2026年10月17日。

[网页体验](https://answers-book-ethan.yguodong627.chatgpt.site) · [作品资料与截图](作品资料/答案之书/V1.0/README.md)

网页免登录公开体验。iOS版本暂未上架。

## 能做什么

- 真实素材开合动画、纸页音效、120条中英双语答案
- 独立收藏每次翻阅记录、编辑问题或备注、查看和清理历史
- 生成纸质分享卡片，默认隐藏备注，可选择包含问题
- iOS本地离线使用，独立声音和触觉设置；网页记录保存在当前浏览器

![网页封面](作品资料/答案之书/V1.0/截图/01_网页封面_桌面.jpg)
![双语答案](作品资料/答案之书/V1.0/截图/02_双语答案_桌面.jpg)

## 运行网页

```sh
git clone https://github.com/yguodong627-star/answers-book.git
cd answers-book
python3 -m http.server 8080 --directory web-preview/dist
```

打开 http://localhost:8080 ，无需npm或后端。声音需点击开启，清除浏览器数据会删除该浏览器的收藏和历史；与iPhone数据不互通。

## 运行iOS

需要Mac、完整Xcode、iPhone模拟器运行时。最低iOS18，Swift6，无第三方App依赖。

```sh
xcodebuild -version
chmod +x scripts/*.sh
./scripts/run-simulator.sh
```

也可 `open ios/AnswersBook.xcodeproj`，选择AnswersBook方案和模拟器后运行。只构建：`./scripts/build.sh simulator`。真机运行需在Xcode选择自己的签名Team，并将 `ios/Configuration/Base.xcconfig` 中占位Bundle ID改为账号下唯一标识。版本和构建号统一在该配置文件管理。

## 当前限制与接续

现用动画576×1248，清晰度等待更高清的整套视频及静态端点；全程稳定60fps尚未证明。替换媒体时同时检查尺寸、裁切、静态端点、页内文字坐标、时长与音画同步。不要混用高清封面与低清视频做淡入淡出。

iOS使用SwiftData和UserDefaults；修改数据模型前考虑迁移，不卸载真实App做回归。DEBUG隔离诊断参数只用于测试。网页不模拟系统音频会话、静音键或触觉；首次加载需要网络，尚未提供Service Worker离线缓存。分享使用Canvas，浏览器系统分享支持有差异，可保存PNG。

本仓库是可运行的公开展示快照，保留iOS与网页源码及运行素材；本地原始资料、历史测试日志、设备信息、签名配置与完整开发历史未上传。公开不等于为所有资产授予再分发许可。声音署名见[音效来源](web-preview/dist/assets/audio/v0.3/ATTRIBUTION.md)，字体遵循[OFL](web-preview/dist/assets/fonts/v0.1/OFL.txt)；视频、图标及答案内容沿用项目素材，商业发行授权仍需另行核对。
