# 公共能力目录

版本：随App 0.13.0（构建19）｜状态：本地内容、记录、设置及媒体能力已接通，人工验收待补｜日期：2026年10月13日。

Content/AnswerCatalog.swift加载并校验120条答案V0.2；DrawSession有效开书时从全库随机选择，不去重，先保存后发布快照。Persistence/RecordStore.swift使用SwiftData Schema 1.0.0，保存UUID、答案编号、双语快照、时间、收藏和可选备注，关闭云同步。相同答案的抽取不合并，库打开失败不清库。

RecordSnapshot提供界面值快照，收藏、备注、删除和清空仅在持久化成功后更新缓存。单条收藏删除必须明确确认；批量清空只移除未收藏记录。Settings/BookPreferences.swift通过UserDefaults持久化声音与触觉两个独立偏好，未设置时开启，重启即应用。

Audio/BookAudio.swift管理独立WAV与soloAmbient；Haptics/BookHaptics.swift管理轻微触觉。关闭设置或离开active即时停止，开启或返回前台不补播。T06/T07真机、T08文案及T09–T15人工验收待补；本轮停在T15。

T16已接通独立纸卡分享；默认隐藏备注，预览和导出同图，人工体验后补。素材及字体原件未改。
