# Feature 001：Dynamic Island 集成与后台终端会话保活

> 目标：让 mRayon (iOS) 在 Dynamic Island / Lock Screen 中显示正在运行的 SSH / Mosh
> 终端状态，并在用户切到后台、锁屏、接电话、切 App 时尽可能地保持远程 shell 会话不断开。

---

## 0. 结论先行（TL;DR）

| 诉求 | 能否通过 Dynamic Island 实现 | 真正决定"存活率"的能力 |
|------|---------------------------|-----------------------|
| 让用户看到正在运行的会话、长命令进度、CPU/Mem 摘要 | ✅ Live Activity + Dynamic Island 可以做到 | — |
| **锁屏后继续运行 SSH shell / tmux / 长任务** | ❌ **Live Activity 不提供后台 CPU 时间**，只是一个"通知 UI" | 需要组合：`UIBackgroundModes` + `BGTaskScheduler` + **Mosh (UDP)** + **tmux 服务端复用** + 断线自动重连 |
| 显示 SSH 连接状态（已连/重连中/已断） | ✅ Live Activity 的长期用途之一 | — |
| 远端长任务完成后主动"叫醒"用户 | ✅ Live Activity push 更新 + 本地/远程通知 | — |

**核心认知**：Dynamic Island 本身**不是保活机制**，它是一个 *视觉* 机制。
iOS 的前台/后台模型不会因为你挂了 Live Activity 而对你多给 CPU 时间。

因此本功能应被拆分成两条独立主线：

1. **保活主线**（真正提高 SSH 后台存活率）——见 §3
2. **Dynamic Island 展示主线**（围绕保活主线的 UI 反馈）——见 §4

---

## 1. 当前架构现状

### 1.1 iOS 端（mRayon）连接实现

- 终端会话由 `TerminalContext` 管理，类型分两种（见 `Application/mRayon/mRayon/Interface/Terminal/TerminalContext.swift`）：
  - **SSH**：基于 `NSRemoteShell`（libssh2，TCP）
  - **Mosh**：基于 `NMSession`（UDP，可漫游）
- `TerminalManager.shared.terminals: [TerminalContext]` 持有所有活动会话。
- 已有 tmux bootstrap (`buildTmuxBootstrapCommand`)，默认不开启，用户需在设置里打开。
- 已有 shell 集成 (OSC 133)，可用于命令完成检测 (`TerminalCommandMonitor`)。
- 已有「命令完成通知」能力 (`TerminalCommandNotificationCenter.notify`)，但仅在应用仍在运行时被调用。

### 1.2 当前后台行为

grep 结果表明：

- `mRayon.entitlements` **未声明任何 Background Modes**（只有 `aps-environment=development` 与 iCloud）
- `Info.plist` **无 `UIBackgroundModes`** 条目
- `mRayonApp.swift` 未使用 `scenePhase`、`UIApplicationDelegate`、`BGTaskScheduler`
- 代码中只有一处 `UIApplication.shared.applicationState` 判定（决定是否发送通知）
- libssh2 的 `libssh2_keepalive_config(session, 0, 2)`：SSH 层面 2 秒发一次保活心跳，但这依赖 App 进程仍在得到 CPU

**这意味着：**

- 进入后台后，iOS 默认给应用 ~30 秒的"任务完成"时间，之后进程被挂起；
- 挂起 ≈ 所有 socket I/O 停止；
- TCP SSH 连接在服务端空闲超时（`ClientAliveInterval * ClientAliveCountMax`）或 NAT 超时（运营商通常 2-5 分钟）后被清理；
- 用户回到 App 时几乎必然已断线 → 必须重连。

### 1.3 已有的缓解手段

- **Mosh 模式**：UDP + 服务端缓冲 + 漫游，天然适合移动网络。**即使客户端被挂起，mosh-server 会保留会话**，回前台时 `NMSession` 可无缝续连。这已是现有架构下最强的"抗后台被杀"能力。
- **tmux**：服务端保留 shell，客户端重连时 `tmux attach`，体验上"会话没断"。
- **命令完成通知 (OSC 133)**：可在长命令结束时发本地通知。

---

## 2. 需求拆解与用户故事

1. **US-1 后台运行看得见**：我切到微信回了条消息，终端图标在灵动岛里变绿色、可点、可看主机名。
2. **US-2 长命令完成提醒**：`make -j8` 跑完了，不管 App 在不在前台都要提醒我，灵动岛展开能看到耗时。
3. **US-3 尽可能别断**：偶尔锁屏 2 分钟后解锁，理想是 tmux/mosh 不掉线、不用等重连。
4. **US-4 多会话指示**：打开了 3 台机器，灵动岛至少告诉我总数和"最近事件"。
5. **US-5 省电/不打扰**：不要因为这功能让电池掉太快或被系统降权。

---

## 3. 保活主线（真正的 backend）

### 3.1 iOS 后台执行模型回顾

| 模式 | 申请方式 | 实际可用时间 | 对本项目是否合规 |
|------|---------|-------------|-----------------|
| Background Task Completion | `beginBackgroundTask` | 通常 ~30 秒，系统可能给到 ~3 分钟 | 做优雅断开/保存会话快照 |
| `UIBackgroundModes = audio` | Info.plist + 播放静音音频 | 持续（只要在播音频） | **不合规**，App Store 明确禁止"仅为保活而播静音" |
| `UIBackgroundModes = voip` | Info.plist + CallKit/PushKit | 持续+被 push 唤醒 | **不合规**，非 VoIP 应用使用会被拒 |
| `UIBackgroundModes = location` | 持续定位 | 持续 | **不合规** |
| `BGTaskScheduler` (BGProcessingTask/BGAppRefreshTask) | iOS 13+ 正规 API | 系统择机调度，数分钟到数小时一次 | **合规**，可用于"定期握手" |
| `Push to Live Activity (ActivityKit)` | APNs token (`activity` / `liveactivity` push type) | Push 抵达时 widget extension 被短暂唤醒执行更新闭包 | **合规**，但只能更新 UI，不能唤醒主 App |
| Silent push + `content-available` | 远程推送 | 每次 push 给 App 短时间唤醒 | **合规但受系统限流**，不保证送达 |

**结论**：不存在任何官方的"在后台持续跑 TCP 长连接"的授权。
提高存活率只能走**断了快速续上**，而不是**让它一直连着**。

### 3.2 分层策略（按优先级落地）

**Tier 1（必做，立即见效，工作量最小）**

1. `beginBackgroundTask` 宽限期：在 `UIApplication.didEnterBackgroundNotification` 时
   - 对每个 `TerminalContext` 请求一个 background task assertion
   - 继续驱动 libssh2 的 I/O 循环 ~30 秒，尽量让 keepalive 多打几发
   - `backgroundTimeRemaining < 5` 时主动 `shell.requestDisconnectAndWait()`，避免被 SIGKILL 带走坏状态
2. **推广 tmux 默认开启**（或在每次新建会话的入口上更显眼地提示）
   - 服务端 tmux 脱机后，"客户端断连"只意味着用户要等 1~2 秒重连
   - 这是投入产出比最高的"保活"
3. **推广 Mosh 为默认连接类型**（对支持 Mosh 的主机）
   - 挂起 → 恢复时 `NMSession` 几乎无感续连
   - 搭配 Live Activity 展示"📶 roaming"状态非常自然

**Tier 2（中等工作量，主要功能）**

4. `BGTaskScheduler` 注册两类任务：
   - `BGAppRefreshTask`（短，~30 秒）——定时让 App 检查每条 tmux/mosh 会话的"最后活动时间"，必要时预热 DNS/TCP
   - `BGProcessingTask`（长，可达数分钟，需插电/联网条件）——做会话快照、日志上传、token 续期
   - 需要在 `Info.plist` 声明 `BGTaskSchedulerPermittedIdentifiers`：例如 `com.playstone.mRayon.refresh`
5. **断线自动重连策略**：`TerminalContext.reconnectInBackground()` 已存在，但当前只由 UI 按钮触发。应追加：
   - 进入后台时记录 `lastActiveAt`
   - 回前台（`scenePhase == .active`）时，对所有 `closed == true` 且 Mosh 不可用的 context，自动串行重连
   - 回前台但 < 30 秒时直接 `explicitRequestStatusPickup`，不真重连

**Tier 3（可选，远程推进）**

6. **远程远端 hook** 方案：在 `mosh-server` 所在机器上运行一个轻量 sidecar（例如通过 snippet 安装），命令完成后向 APNs 推 `liveactivity` push → 灵动岛即时更新 → 顺便把 App 从挂起唤醒。
   - 要求：服务器要有公网出网；需要把 APNs 鉴权所需的 team id/key id/p8 存到用户服务器，安全模型不小。
   - 作为"Premium"功能更合适。

### 3.3 实现要点清单

- [ ] `mRayon.entitlements`：保持现状，不加 `audio/voip/location`。
- [ ] `Info.plist`：
  ```xml
  <key>BGTaskSchedulerPermittedIdentifiers</key>
  <array>
    <string>com.playstone.mRayon.refresh</string>
    <string>com.playstone.mRayon.processing</string>
  </array>
  ```
- [ ] 新增 `SessionLifecycleCoordinator`（单例，`@MainActor`）：
  - 监听 `UIScene.willDeactivateNotification` / `didEnterBackgroundNotification` / `willEnterForegroundNotification`
  - 维护 `activeBackgroundTaskID: UIBackgroundTaskIdentifier`
  - 负责在后台收尾、前台唤醒
- [ ] 在 `TerminalContext` 暴露：
  - `var lastIOAt: Date`
  - `func preserveForBackground() async -> SessionSnapshot`
  - `func restoreFromForeground(_ snapshot: SessionSnapshot) async`

---

## 4. Dynamic Island / Live Activity 展示主线

### 4.1 技术约束

- **ActivityKit**：iOS 16.1+（Dynamic Island 需要 iPhone 14 Pro 及以上型号，但 Lock Screen 表现形式所有 iPhone 都支持）。
- **当前 `IPHONEOS_DEPLOYMENT_TARGET = 17.0`**（见 `mRayon.xcodeproj/project.pbxproj:1027`），Live Activity 全部 API 可用，无需 `@available` 分支太多。
- Live Activity **必须通过 Widget Extension 目标**实现 UI。目前工程内没有这个 target（grep: `ActivityKit|LiveActivity|DynamicIsland|WidgetExtension` → 无结果）。
- 每个 Live Activity 生命周期：最长 8 小时前台活跃 + 再 4 小时系统展示；可被用户 dismiss。
- Live Activity 的 UI 代码运行在扩展进程，不能直接调 App 内的 `RayonStore` / `TerminalManager`。跨进程共享只能通过：
  - App Group 容器（`group.com.playstone.mRayon`）—— 需要新建 App Group entitlement
  - ActivityKit 的 `ContentState`（每次 update 传入）

### 4.2 数据模型

```swift
import ActivityKit

public struct TerminalSessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public enum Status: String, Codable { case connected, reconnecting, disconnected, idle, running }
        public var status: Status
        public var host: String
        public var transport: String            // "SSH" / "Mosh"
        public var currentCommand: String?      // 来自 OSC 133
        public var commandStartedAt: Date?
        public var lastLineSnippet: String?     // 脱敏后的最近一行输出（去 ANSI）
        public var unreadBellCount: Int
    }

    public let sessionID: UUID
    public let machineName: String
    public let openedAt: Date
}
```

### 4.3 UI 布局（按 HIG）

Apple HIG 对 Dynamic Island 要求三种形态：

1. **Compact leading / trailing**（日常小胶囊）
   - leading：SF Symbol `terminal.fill`，按 `status` 上色（connected=绿 / reconnecting=橙 / disconnected=红）
   - trailing：短文本，例如 `build...` / `2m12s` / `3` (未读 bell)
2. **Minimal**（多个 Activity 同时存在时，被挤成一个 glyph）
   - 单 SF Symbol，仅显示 `status` 色
3. **Expanded**（长按或系统优先级提升时）
   - Region `leading`：主机名 + transport 徽章
   - Region `trailing`：计时器（`Text(timerInterval:)`）
   - Region `bottom`：当前命令（单行截断）+ 重连按钮（`DeepLink`，返回 App 指定 session）
   - Lock Screen 同布局，多一行 "最近输出"（已脱敏）

**不要放**：完整 shell 输出（隐私/合规）、长密码、任何个人可识别信息。

### 4.4 事件接入

| 事件 | 更新 Live Activity 的方式 |
|------|------------------------|
| 新建 session | `Activity.request(attributes:contentState:pushType:)` |
| OSC 133 `C`（命令开始） | `activity.update(using:)` in-app |
| OSC 133 `D`（命令结束） | update + 如果 in background 并且 push enable → 走远程 push |
| 连接状态变化 | update |
| 用户在 App 里关闭 session | `activity.end(using:dismissalPolicy:.immediate)` |
| 新 session 但已有活动 Activity | 决定策略：多会话合并成一个 Activity（列表态） vs 每 session 一个 Activity。建议 **一个主 Activity + 列表**，避免灵动岛爆炸。 |

### 4.5 文件结构（建议）

```
Application/mRayon/
├── mRayon/                       # 主 App（现有）
│   └── Interface/Terminal/
│       └── LiveActivityBridge.swift       # 新增：在 TerminalContext 事件点调用
└── mRayonLiveActivity/                     # 新增 Widget Extension target
    ├── Info.plist                         # NSExtensionPointIdentifier = com.apple.widgetkit-extension
    ├── mRayonLiveActivityBundle.swift     # @main WidgetBundle
    └── TerminalLiveActivity.swift         # ActivityConfiguration + DynamicIsland
Foundation/
└── RayonLiveActivity/                      # 新增 SPM 包（只放 ActivityAttributes，被主 App 与 Extension 同时引用）
    └── Sources/RayonLiveActivity/
        └── TerminalSessionAttributes.swift
```

### 4.6 entitlements / capability 变化

- 主 App：需要加 App Group（**可选**，仅当需要扩展读共享数据时）
- Extension：同 App Group
- 不需要加 `UIBackgroundModes`
- **若启用远程 push 更新 Live Activity**：需要在主 App 开启 Push Notifications capability（当前 `aps-environment=development` 已存在），并额外处理 `PushToken<PushType.liveActivity>`

---

## 5. 两条主线的协同

```
                        ┌───────────────────────────────┐
                        │    TerminalContext (主 App)    │
                        │  SSH / Mosh / tmux bootstrap   │
                        └──────┬────────────────┬────────┘
                               │                │
                 OSC 133 事件   │                │ 连接状态变化
                               ▼                ▼
                        ┌─────────────────────────────┐
                        │   SessionLifecycleCoordinator │
                        │  - scenePhase 监听            │
                        │  - beginBackgroundTask        │
                        │  - BGTaskScheduler 注册       │
                        └────┬──────────────────┬──────┘
                             │                  │
               bg entering   │                  │ 状态快照
                             ▼                  ▼
                     ┌────────────────┐   ┌──────────────────┐
                     │ Tier1 保活措施 │   │ LiveActivityBridge│
                     │ keepalive flush│   │  .request/update │
                     └────────────────┘   └────────┬─────────┘
                                                   │
                                                   ▼ ActivityKit IPC
                                          ┌──────────────────┐
                                          │ Widget Extension │
                                          │ 渲染灵动岛/锁屏   │
                                          └──────────────────┘
```

---

## 6. 里程碑建议

1. **M1 - 保活 Tier 1（1~2 天）**
   - `SessionLifecycleCoordinator` + `beginBackgroundTask`
   - 回前台自动重连（仅 SSH 需要，Mosh 免）
   - 可度量指标：后台 60 秒后回前台的会话保留率
2. **M2 - Live Activity MVP（2~3 天）**
   - 新建 `RayonLiveActivity` SPM + `mRayonLiveActivity` Widget Extension
   - 只实现 compact + expanded + lock screen 三态
   - 接入：session 开始/结束、连接状态、OSC 133 命令起止
3. **M3 - BGTaskScheduler + 抗断策略（1~2 天）**
   - `BGAppRefreshTask` 轻量心跳
   - 断线重连队列化
4. **M4 (可选) - 远程 Live Activity Push（3~5 天）**
   - 服务端 snippet + APNs `liveactivity` push
   - 需要后端或 sidecar 支持，安全模型评审

---

## 7. 风险与需要额外确认的点

- **归档项目政策**：CLAUDE.md 提到项目"currently archived but accepts minor fixes"。Live Activity 是一个明显的 *feature* 增量（新 target / 新依赖 / 新 entitlements），可能超出"minor fix"范围，**需要项目 owner 确认是否愿意接收**。
- **多会话的灵动岛管理**：iOS 对同时存在的 Live Activity 有数量限制（历史上是 1 个 compact + 少量额外），需要做合并态（list）而非每个 session 一个 Activity。
- **隐私**：灵动岛展示 "lastLineSnippet" 要做脱敏，尤其是 `ls -a`、密码提示、token 回显——建议：
  - 只展示最近一条 **用户输入**（不含输出）或当前 OSC 133 命令字面值
  - 提供用户开关 "在锁屏显示命令文本"
- **归档阶段的维护成本**：新加 target 会让 Xcode 工程更复杂，考虑在 Premium 模块后（参考 `Foundation/Premium/`）挂这个功能。
- **watchOS / visionOS**：目前有 `wRayon` 与 `vRayon` target，Live Activity 主要解决 iOS 场景，watchOS 的"Smart Stack"有独立接入方式，不在本文档范围。

---

## 8. 参考 API / 文档线索

- `ActivityKit` — `Activity.request`, `Activity.update`, `Activity.end`, `Activity.pushToken`
- `WidgetKit.DynamicIsland` — `.compactLeading`, `.compactTrailing`, `.minimal`, `.expanded`
- `BGTaskScheduler` — iOS 13+，WWDC 2019 session 707
- `UIApplication.beginBackgroundTask(withName:expirationHandler:)`
- libssh2 `libssh2_keepalive_config`（当前源码 `External/NSRemoteShell/Sources/NSRemoteShell/NSRemoteShell.m:646`，已设 2s）
- Apple HIG: Live Activities — 特别注意"不要在锁屏显示敏感信息"条款
- 现有相关代码入口：
  - `Application/mRayon/mRayon/Interface/Terminal/TerminalContext.swift`
  - `Application/mRayon/mRayon/Interface/Terminal/TerminalManager.swift`
  - `Foundation/RayonModule/Sources/RayonModule/Terminal/TerminalCommandMonitor.swift:245` (`requestAuthorizationIfNeeded`, `notify`)
