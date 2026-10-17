# 答案之书网页体验版

版本：V1.0｜状态：已完成本地浏览器检查，公开发布｜日期：2026年10月17日。

[公开体验](https://answers-book-ethan.yguodong627.chatgpt.site) · [GitHub源码](https://github.com/yguodong627-star/answers-book)

基于iOS 0.14.1构建41，复用已确认Book V0.4动画、Audio V0.3声音、答案V0.2及图标V0.2。新增网页版交互：随机翻阅、收藏/历史、备注、删除确认及本地PNG分享。网页视觉与原生App不完全相同，未宣称网页观感已获用户验收。

## 运行与维护

无构建依赖，所有运行文件在dist：

```sh
python3 -m http.server 8080 --directory web-preview/dist
```

打开 http://localhost:8080 。通过HTTP运行，不能直接双击HTML；样式、脚本、字体与媒体均使用相对路径。应用状态通过原生DOM与媒体API实现，无后端数据库和账号。记录/偏好使用localStorage，只属于当前浏览器，与iPhone不互通；首次访问需联网，尚无Service Worker离线缓存。

分享每次重置为隐藏备注，生成期间清除旧预览/禁用保存，使用递增标识防止旧异步结果覆盖最新选择。图片生成设12M像素及20000逻辑高度保护，过长内容提示关闭备注，不静默截断。浏览器系统分享依支持情况显示，已实测保存PNG；本轮未向他人发送。

视频固定576×1248，静态端点与视频同源尺寸，首次视频帧就绪后直接切换；不使用封面/视频交叉淡化。高清及全程60fps仍待后续素材和优化，不改变iOS暂停事项。网页声音默认关闭，可主动开启；不模拟iOS静音键、音频会话或真机触觉。

## 素材版本与来源

| 分类 | 网页路径 | 来源与状态 |
| --- | --- | --- |
| 视频及静态端点 | dist/assets/book/v0.4 | 原样复制ios运行Book/V0.4，用户现有即梦素材与已确认端点；未重新生成，清晰度保留已知限制 |
| 声音 | dist/assets/audio/v0.3 | 原样复制已确认音效，InspectorJ CC BY4.0与Joseph SARDIN CC0；完整署名见同目录ATTRIBUTION.md |
| 字体 | dist/assets/fonts/v0.1 | 原样复制Noto Serif SC，保留OFL；英文使用Georgia系统字体 |
| 双语答案 | dist/assets/answers/v0.2 | 原样复制现用120条JSON；不修改编号、文案或顺序 |
| 图标 | dist/assets/icon/v0.2 | 原样复制已确认双语棕色书封图标；原生成提示词与历史保留在本地设计素材 |
| 装饰 | dist/assets/ornaments/answer.svg | 从现有页面设计的花饰路径复用，源文件与提取记录保留在本地项目 |

网页README不取代第三方许可；资产公开展示不意味着商业发行授权已完成核对。

## 发布

.openai/hosting.json绑定同一Sites项目，不另建站点。先在项目.build/发布内的隔离目录复制源码，再用Sites工作流推送、打包、保存版本、部署；禁止在用户主目录运行。凭据仅通过stdin传入，不写入文件。GitHub是单独的公开源码快照，不把本地私有测试历史推上远端。发布记录见根项目docs/验证记录/T29。
