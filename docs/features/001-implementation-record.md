# Feature 001 — 实施记录

> 分支：`feature/dynamic-island`
> 日期：2026-04-18
> 状态：M1 + M2 + M3 已完成，M4 暂不实施

---

## 完成概览

| 里程碑 | 内容 | 状态 |
|--------|------|------|
| **M1** | 后台保活 Tier1 — `SessionLifecycleCoordinator` + `beginBackgroundTask` + 前台自动重连 | ✅ |
| **M2** | Live Activity MVP — SPM 包 + Widget Extension + Dynamic Island 三态 UI + ActivityKit 接入 | ✅ |
| **M3** | BGTaskScheduler — `BGAppRefreshTask` 轻量心跳 + `BGProcessingTask` 会话快照 | ✅ |
| **M4** | 远程 Live Activity Push（需服务端支持） | ⏸ 暂不实施 |

---

## 新增文件

### M1 — 后台保活

| 文件 | 说明 |
|------|------|
| `Application/mRayon/mRayon/Interface/Terminal/SessionLifecycleCoordinator.swift` | 单例，监听 scene 生命周期，管理 `beginBackgroundTask` 宽限期，前台自动重连策略，`BGTaskScheduler` 注册与调度 |

### M2 — Live Activity

| 文件 | 说明 |
|------|------|
| `Foundation/RayonLiveActivity/Package.swift` | SPM 包定义，iOS 17+，无外部依赖 |
| `Foundation/RayonLiveActivity/Sources/RayonLiveActivity/TerminalSessionAttributes.swift` | 共享 `ActivityAttributes` 类型：`TerminalSessionAttributes` + `ContentState.Status` 枚举（connected/reconnecting/disconnected/idle/running）+ SF Symbol 映射 |
| `Application/mRayon/mRayon/Interface/Terminal/LiveActivityBridge.swift` | ActivityKit 管理类，合并多会话为单个 Live Activity，提供 startTracking/stopTracking/updateSessionStatus/updateCommandStarted/updateCommandFinished/incrementBell 等方法 |
| `Application/mRayon/mRayonLiveActivity/mRayonLiveActivityLiveActivity.swift` | Dynamic Island UI（compact/expanded/minimal 三态）+ Lock Screen banner |
| `Application/mRayon/mRayonLiveActivity/mRayonLiveActivityBundle.swift` | Widget Extension 入口 `@main` |
| `Application/mRayon/mRayonLiveActivity/Info.plist` | Extension 配置，`NSExtensionPointIdentifier = com.apple.widgetkit-extension` |
| `Application/mRayon/mRayonLiveActivity/mRayonLiveActivityExtension.entitlements` | `aps-environment = development` |

---

## 修改文件

### TerminalContext.swift

| 变更 | 说明 |
|------|------|
| +`var lastIOAt: Date` | 在 `insertBuffer`、`handleShellOutput`、`handleMoshOutput` 中更新 |
| +`struct SessionSnapshot` | 保存会话快照（sessionId, machineName, transport, wasConnected, isInTmux, lastIOAt） |
| +`var preservedSnapshot: SessionSnapshot?` | 存储后台快照 |
| +`preserveForBackground()` | 捕获当前状态到 `preservedSnapshot` |
| +`restoreFromForeground(_:) async` | 从快照恢复，更新 `lastIOAt` |
| `moshModeActive` 访问级 `private` → `internal` | 供 `SessionLifecycleCoordinator` 判断连接类型 |
| +`insertBuffer()` 中调用 `LiveActivityBridge.updateCommandStarted` | 用户按回车时通知 Live Activity |
| +`consumeCommandMonitorOutput()` 中调用 `LiveActivityBridge.updateCommandFinished` + `updateSnippet` | OSC 133 命令完成时更新 |
| +`handleTerminalEvent(.bell)` 调用 `LiveActivityBridge.incrementBell` | Bell 事件计数 |
| +`processBootstrap()` 认证成功/失败时调用 `LiveActivityBridge.updateSessionStatus` | 连接状态通知 |
| +`reconnectInBackground()` 开头调用 `LiveActivityBridge.updateSessionStatus(.reconnecting)` | 重连中状态 |
| +`processShutdown()` 开头调用 `LiveActivityBridge.updateSessionStatus(.disconnected)` | 断开状态通知 |

### TerminalManager.swift

| 变更 | 说明 |
|------|------|
| +`begin(for machineId:)` 末尾 `LiveActivityBridge.startTracking` | 新建终端时开始追踪 |
| +`begin(for command:)` 末尾 `LiveActivityBridge.startTracking` | 命令终端同理 |
| +`end(for:)` 开头 `LiveActivityBridge.stopTracking` | 关闭终端时停止追踪 |

### mRayonApp.swift

| 变更 | 说明 |
|------|------|
| +初始化 `SessionLifecycleCoordinator.shared` | 激活生命周期监听 |
| +`scheduleNextAppRefresh()` | 启动时调度首次 BGAppRefreshTask |

### mRayon/Info.plist

| 变更 | 说明 |
|------|------|
| +`BGTaskSchedulerPermittedIdentifiers` | `com.playstone.mRayon.refresh` + `com.playstone.mRayon.processing` |
| +`UIBackgroundModes` | `processing` + `fetch` + `remote-notification` |
| +`NSSupportsLiveActivities = YES` | 声明支持 Live Activity |

### mRayon.xcodeproj/project.pbxproj

| 变更 | 说明 |
|------|------|
| +`LiveActivityBridge.swift` 文件引用 | PBXBuildFile + PBXFileReference + PBXGroup + PBXSourcesBuildPhase（mRayon + vRayon） |
| +`RayonLiveActivity` 包依赖 | mRayon target + mRayonLiveActivityExtension target 的 `packageProductDependencies` |
| +`mRayonLiveActivityExtension` target | Xcode 自动生成的 Widget Extension target（用户手动在 Xcode 中创建） |

### App.xcworkspace/contents.xcworkspacedata

| 变更 | 说明 |
|------|------|
| +`Foundation/RayonLiveActivity` | workspace 中添加 SPM 本地包引用 |

---

## 架构说明

### 数据流

```
TerminalManager.begin()
  └→ LiveActivityBridge.startTracking(context)
       └→ Activity.request() → Dynamic Island 出现

TerminalContext (用户输入 / OSC 133 / 连接状态变化)
  └→ LiveActivityBridge.updateXxx()
       └→ Activity.update() → Dynamic Island 实时更新

TerminalManager.end()
  └→ LiveActivityBridge.stopTracking(sessionId)
       └→ Activity.end() → Dynamic Island 消失

SessionLifecycleCoordinator (scene 生命周期)
  ├→ 后台: beginBackgroundTask + preserveForBackground()
  ├→ 前台: 自动重连断开的 SSH / 跳过 Mosh
  └→ BGTaskScheduler: 定期心跳检查
```

### Widget Extension 架构

```
mRayon (主 App)
  ├── LiveActivityBridge — 管理 ActivityKit 生命周期
  ├── TerminalSessionAttributes (from RayonLiveActivity SPM 包)
  └── mRayonLiveActivityExtension (Widget Extension, 独立进程)
        └── TerminalLiveActivity — 渲染 Dynamic Island / Lock Screen UI
              └── TerminalSessionAttributes (同一个 SPM 包)
```

---

## 后续事项

- [ ] Xcode 中确认 mRayon target 的 Signing & Capabilities 包含必要的 entitlements
- [ ] 真机测试 Dynamic Island 展示效果（需 iPhone 14 Pro+）
- [ ] 测试后台保活：锁屏 2 分钟后恢复、切 App 后恢复
- [ ] 测试 BGTaskScheduler 调度（Xcode → Debug → Simulate Background Fetch）
- [ ] 评估是否需要在设置中添加 "在锁屏显示命令文本" 开关（隐私）
- [ ] M4 远程 Push 实施时需要：服务端 sidecar + APNs key 配置 + `Activity.pushToken` 上报
