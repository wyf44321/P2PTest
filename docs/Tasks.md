# P2PTest AI 实现任务拆分

> 版本：v2.3.0 | 作者：AI | 日期：2026-03-10 | 基于：产品文档 v2.3.0、需求文档 v2.3.0、实现文档 v2.3.0

---

## 任务总览

| 阶段 | 名称 | 任务数 | 预计耗时 | 依赖 |
|------|------|--------|---------|------|
| Phase 0 | 项目初始化 | 2 | 0.5 天 | 无 |
| Phase 1 | P2P 连接层（纯 Dart） | 3 | 1-2 天 | Phase 0 |
| Phase 2 | 客户端基础 UI | 14 | 3-4 天 | Phase 0 |
| Phase 3 | 连接监控 | 5 | 2 天 | Phase 1 |
| Phase 4 | 断线重连 | 4 | 1-2 天 | Phase 1 |
| Phase 5 | 功能集成 | 5 | 1-2 天 | Phase 2, 3, 4 |
| Phase 6 | 测试与优化 | 4 | 1-2 天 | Phase 5 |

---

## Phase 0 — 项目初始化

### Task 0.1 创建项目目录结构

**优先级**：P0
**模块**：全局
**描述**：按照实现文档 1.1 节的仓库结构创建完整目录骨架。

**具体操作**：
- 创建 `client/lib/` 目录及其子目录：`app/`、`config/`、`models/`、`services/`、`providers/`、`screens/`、`widgets/`、`utils/`

**验收标准**：
- [ ] 所有目录已创建
- [ ] 目录结构与实现文档一致

---

### Task 0.2 初始化 Flutter 客户端项目

**优先级**：P0
**模块**：客户端
**描述**：创建 Flutter 项目，添加核心依赖。

**具体操作**：
- 在 `client/` 下执行 `flutter create .`
- 在 `pubspec.yaml` 中添加依赖：`provider` 或 `riverpod`、`shared_preferences`
- 配置 Android `minSdkVersion` 为 26（API 26 = Android 8.0）
- 配置 iOS deployment target 为 14.0

**验收标准**：
- [ ] `flutter pub get` 执行成功
- [ ] `flutter analyze` 无错误
- [ ] Android 和 iOS 平台配置正确

---

## Phase 1 — P2P 连接层（纯 Dart）

### Task 1.1 实现 UDP 通信服务

**优先级**：P0
**模块**：`client/lib/services/udp_service.dart`
**描述**：使用 Dart 原生 `RawDatagramSocket` 实现 UDP 通信，支持消息收发和打洞。

**输入参考**：实现文档 3.2 节

**具体操作**：
- 实现 `UdpService` 类，封装 `RawDatagramSocket`
- 实现 `bind({int port})` 绑定本地 UDP 端口
- 实现 `sendMessage(ip, port, type, data)` 发送 JSON 格式 UDP 消息
- 实现 `holePunch(remoteIp, remotePort, {timeoutSec})` UDP 打洞
- 实现 `UdpEventListener` 回调接口（onMessage）
- 实现 `close()` 关闭 socket

**验收标准**：
- [ ] 本地 UDP socket 绑定成功
- [ ] 消息可双向收发
- [ ] JSON 格式消息正确编解码
- [ ] 打洞超时正确触发

---

### Task 1.2 实现 STUN 客户端（纯 Dart）

**优先级**：P0
**模块**：`client/lib/services/stun_service.dart`
**描述**：纯 Dart 实现 STUN Binding Request 协议，通过 STUN 服务器获取公网 IP 和端口。

**输入参考**：实现文档 3.3 节

**具体操作**：
- 实现 STUN Binding Request 消息构造（RFC 5389）
- 实现 STUN Binding Response 解析（XOR-MAPPED-ADDRESS）
- 实现 `getPublicAddr(socket, stunHost, stunPort, {timeout})` 获取公网地址
- 配置默认 STUN 服务器列表（9 个服务器，含自建 61.151.231.231:2311/2312）
- 支持传入用户配置的优先服务器
- 实现 `fetchPublicAddress({preferredServer})` 依次尝试服务器列表

**验收标准**：
- [ ] 可获取公网 IP 和端口
- [ ] 自建 STUN 服务器优先尝试
- [ ] 用户配置的服务器优先尝试
- [ ] 单个 STUN 失败自动尝试下一个
- [ ] 所有 STUN 失败时返回明确错误

---

### Task 1.3 实现 IP 归属地查询服务

**优先级**：P1
**模块**：`client/lib/services/ip_geo_service.dart`
**描述**：通过 IP 查询 API 获取 IP 归属地信息（省市/运营商），结果缓存到内存。

**输入参考**：实现文档 6.1 节、需求文档 FR-005a

**具体操作**：
- 实现 `IpGeoService` 类
- 实现 `queryLocation(ip)` 异步查询 IP 归属地
- 使用 ip-api.com API（`http://ip-api.com/json/{ip}?lang=zh-CN`）
- 实现内存缓存，同一 IP 不重复查询
- 实现内网 IP 检测（10.x / 172.16-31.x / 192.168.x），返回「内网地址」
- 查询失败优雅降级，返回「未知」

**验收标准**：
- [ ] 公网 IP 查询返回正确的省市和运营商
- [ ] 查询结果缓存生效，同一 IP 不重复请求
- [ ] 内网 IP 正确返回「内网地址」
- [ ] 查询失败返回「未知」，不抛异常
- [ ] 查询不阻塞 UI

---

## Phase 2 — 客户端基础 UI

### Task 2.1 实现客户端常量配置

**优先级**：P0
**模块**：`client/lib/config/constants.dart`
**描述**：定义客户端所有常量。

**具体操作**：
- P2P 打洞超时：10 秒
- STUN 单服务器超时：5 秒
- 轮询探测间隔：1 秒（每秒探测一个用户）
- 降级探测间隔：60 秒（重连失败后每分钟探测一次）
- 丢包率计算间隔：5 秒
- 丢包率窗口大小：30
- Pong 超时：3 秒
- 重连策略间隔：[1s, 5s, 10s, 30s, 60s]
- 最大重连次数：5

**验收标准**：
- [ ] 所有常量已定义
- [ ] 值与需求文档一致

---

### Task 2.2 实现客户端数据模型

**优先级**：P0
**模块**：`client/lib/models/`
**描述**：定义 MonitoredPeer 和 SelfInfo 模型。

**输入参考**：需求文档 4 节

**具体操作**：
- **MonitoredPeer**：id, ip, port, address, ipLocation, status, rttMs, packetLoss, createdAt, reconnectCount
- **SelfInfo**：publicIp, publicPort, localPort, stunStatus
- **枚举**：ConnectionStatus（含 degradedMonitoring 降级监控状态）、StunStatus
- 实现 `fromJson()` / `toJson()` 方法

**验收标准**：
- [ ] 模型字段与需求文档一致（含 ipLocation）
- [ ] JSON 序列化/反序列化正确
- [ ] 枚举值完整（含 degradedMonitoring）

---

### Task 2.3 实现 SelfInfoProvider 状态管理

**优先级**：P0
**模块**：`client/lib/providers/self_info_provider.dart`
**描述**：管理本端公网地址信息和 STUN 配置。

**具体操作**：
- 实现 SelfInfoState 和 SelfInfoProvider
- 方法：fetchPublicAddress(stunServer?)、retry()、saveStunConfig()、loadStunConfig()
- StunStatus 枚举增加 `configuring` 状态
- 状态转换：loading → success / failed → configuring → loading

**验收标准**：
- [ ] STUN 获取状态正确管理（含 configuring 状态）
- [ ] 状态变更通知 UI 刷新
- [ ] STUN 配置加载和保存正确

---

### Task 2.4 实现 PeerProvider 状态管理

**优先级**：P0
**模块**：`client/lib/providers/peer_provider.dart`
**描述**：管理监听用户列表状态。

**具体操作**：
- 实现 PeerState 和 PeerProvider
- 方法：addPeer、removePeer、updatePeerStatus、updateRTT、updatePacketLoss、updateReconnectProgress、updateIpLocation、clearDisconnectedPeers
- 实现 `hasDisconnectedPeers` getter（控制「清除断开」按钮状态）
- 集成 StorageService 实现持久化

**验收标准**：
- [ ] 增删改查操作正确
- [ ] clearDisconnectedPeers 正确移除所有已断开/降级监控中的用户
- [ ] hasDisconnectedPeers 正确反映是否存在断开用户
- [ ] 状态变更通知 UI 刷新
- [ ] 持久化正确触发

---

### Task 2.5 实现公网地址卡片组件

**优先级**：P0
**模块**：`client/lib/widgets/public_address_card.dart`
**描述**：展示 STUN 获取的公网地址，含设置图标入口。

**具体操作**：
- Card 布局：地址展示 + 复制按钮 + 设置图标（⚙）
- 复制到剪贴板 + Toast 提示
- 设置图标点击后导航到 STUN 配置界面

**验收标准**：
- [ ] 地址正确展示
- [ ] 复制功能可用
- [ ] 设置图标点击可进入 STUN 配置界面

---

### Task 2.5a 实现 STUN 加载等待视图

**优先级**：P0
**模块**：`client/lib/widgets/stun_loading_view.dart`
**描述**：App 启动获取公网地址时的全屏加载等待视图。

**输入参考**：产品文档 4.1 节

**具体操作**：
- 居中显示 CircularProgressIndicator 转圈动画
- 动画下方显示提示文字「正在获取公网地址…」
- 整体居中在屏幕中央

**验收标准**：
- [ ] 转圈动画流畅居中展示
- [ ] 提示文字清晰可读
- [ ] 获取成功后视图自动切换到主界面
- [ ] 获取失败后视图自动切换到 STUN 配置界面

---

### Task 2.5b 实现 STUN 服务器默认列表配置

**优先级**：P0
**模块**：`client/lib/config/stun_servers.dart`
**描述**：定义 STUN 服务器默认可选列表。

**具体操作**：
- 定义 StunServerOption 数据类（name、host、port）
- 定义 StunServers.defaultServers 列表，包含 9 个 STUN 服务器
- 服务器列表：自建 STUN 61.151.231.231:2311/2312（优先）、Google STUN (x3)、stunprotocol.org、Ekiga、IdeasIP、Schlund

**验收标准**：
- [ ] 列表包含 9 个 STUN 服务器
- [ ] 自建 STUN 服务器排在列表最前面
- [ ] 每个条目包含名称、主机、端口

---

### Task 2.5c 实现 STUN 服务器配置界面

**优先级**：P0
**模块**：`client/lib/screens/stun_config_screen.dart`
**描述**：STUN 服务获取失败时的配置界面，支持用户选择或手动输入 STUN 服务器地址。

**输入参考**：产品文档 4.2 节、需求文档 FR-001a

**具体操作**：
- 顶部提示区：显示「⚠ STUN 服务不可用，请选择或输入 STUN 服务器」
- 默认可选列表：Radio 单选列表，展示 StunServers.defaultServers
- 自定义输入区：STUN 服务器地址（host）+ 端口输入框
- 「重新获取」按钮
- 选择/输入后调用 SelfInfoProvider.saveStunConfig() 持久化
- 使用新服务器调用 SelfInfoProvider.fetchPublicAddress() 重新获取
- 获取成功自动进入主界面，获取失败提示并留在配置界面

**验收标准**：
- [ ] STUN 获取失败后自动展示配置界面
- [ ] 展示默认可选 STUN 服务器列表（Radio 单选）
- [ ] 支持自定义输入 STUN 服务器地址
- [ ] 自定义地址格式校验（host:port）
- [ ] 点击「重新获取」使用选中的服务器重新尝试
- [ ] 用户选择持久化到本地
- [ ] 获取成功后自动进入主界面
- [ ] 获取失败提示用户尝试其他服务器

---

### Task 2.5d 实现 STUN 配置持久化

**优先级**：P0
**模块**：`client/lib/services/storage_service.dart`、`client/lib/providers/self_info_provider.dart`
**描述**：将用户选择的 STUN 服务器配置持久化到本地，App 启动时恢复。

**具体操作**：
- 在 StorageService 中新增 saveStunConfig / loadStunConfig 方法
- 持久化字段：selected_server（host:port）、is_custom、updated_at
- 在 SelfInfoProvider 中新增 saveStunConfig() 和 loadStunConfig() 方法
- App 启动时先加载 STUN 配置，再执行 STUN 获取

**验收标准**：
- [ ] 用户选择后自动保存到本地
- [ ] App 重启后正确恢复 STUN 配置
- [ ] 恢复后优先使用用户记录的 STUN 服务器获取公网地址
- [ ] 无记录时使用默认列表

---

### Task 2.6 实现监听用户卡片组件

**优先级**：P0
**模块**：`client/lib/widgets/peer_card.dart`
**描述**：监听用户列表中的单个用户展示卡片。

**输入参考**：产品文档 4.1 节

**具体操作**：
- Card 布局：IP:Port、IP 归属地、连接状态+颜色圆点、延迟、丢包率
- IP 归属地：查询中显示「查询中...」，查询失败显示「未知」，内网显示「内网地址」
- 重连中显示进度
- 断开/失败时延迟和丢包显示「--」

**验收标准**：
- [ ] 所有字段正确展示（含 IP 归属地）
- [ ] IP 归属地正确展示各状态
- [ ] 连接状态颜色正确
- [ ] 断开时显示「--」

---

### Task 2.7 实现添加用户对话框

**优先级**：P0
**模块**：`client/lib/widgets/add_peer_dialog.dart`
**描述**：手动输入 IP 和端口添加监听用户。

**输入参考**：需求文档 FR-003

**具体操作**：
- IP 地址输入框（IPv4 格式校验）
- 端口号输入框（数字键盘，1-65535 校验）
- 「添加」/「取消」按钮
- 实时表单验证反馈
- 重复检查

**验收标准**：
- [ ] IP 格式校验正确
- [ ] 端口范围校验正确
- [ ] 重复添加提示
- [ ] 表单验证实时反馈

---

### Task 2.8 实现主界面

**优先级**：P0
**模块**：`client/lib/screens/home_screen.dart`
**描述**：App 主界面，根据 STUN 状态展示不同视图。

**输入参考**：产品文档 4.1 ~ 4.3 节

**具体操作**：
- 根据 StunStatus 切换视图：
  - `loading` → StunLoadingView（转圈等待）
  - `failed` / `configuring` → StunConfigScreen（配置界面）
  - `success` → 主内容（公网地址卡片 + 监听用户列表）
- 主内容：顶部 App 标题、公网地址卡片（PublicAddressCard）、「监听用户」标题 + 「清除断开」按钮 + 「＋」按钮、监听用户列表、空状态提示、底部版本号

**验收标准**：
- [ ] loading 状态显示转圈等待视图
- [ ] failed 状态自动切换到 STUN 配置界面
- [ ] success 状态展示主界面
- [ ] 界面布局完整美观
- [ ] 左滑删除可用
- [ ] 空状态正确显示
- [ ] 添加按钮可用
- [ ] 「清除断开」按钮可用

---

### Task 2.9 实现一键清除断开连接功能

**优先级**：P0
**模块**：`client/lib/widgets/clear_disconnected_button.dart`、`client/lib/screens/home_screen.dart`
**描述**：在「监听用户」标题栏实现一键清除所有已断开连接的监听用户功能。

**输入参考**：需求文档 FR-010

**具体操作**：
- 在「监听用户」标题栏添加「清除断开」按钮（图标或文字按钮）
- 按钮状态联动 PeerProvider.hasDisconnectedPeers：存在断开用户时可用，否则置灰
- 点击后弹出确认对话框「确定清除所有已断开的监听用户？」
- 确认后调用 PeerProvider.clearDisconnectedPeers()
- 同时调用 MonitorService.clearDisconnectedPeers() 清理连接资源和降级定时器
- 更新本地持久化数据

**验收标准**：
- [ ] 「清除断开」按钮展示在标题栏
- [ ] 无断开用户时按钮置灰
- [ ] 点击后弹出确认对话框
- [ ] 确认后正确移除所有已断开/降级监控中的用户
- [ ] P2P 连接和降级定时器正确清理
- [ ] 列表和本地持久化同步更新

---

## Phase 3 — 连接监控

### Task 3.1 实现轮询探测和延迟测量

**优先级**：P0
**模块**：`client/lib/services/monitor_service.dart`
**描述**：每秒依次探测一个监听用户（轮询），通过 UdpService 发送 Ping 测量 RTT 并更新连接状态。

**输入参考**：实现文档 4.1 节

**具体操作**：
- 实现 MonitorService，注入 UdpService，维护轮询索引 `_currentIndex`
- 每 1 秒探测下一个已连接用户（Round-Robin），通过 UDP 发送 Ping（seq + timestamp）
- 收到 Pong 时计算 RTT，更新 PeerProvider
- 探测到连接断开时触发重连逻辑
- N 个用户时，每个用户有效探测间隔为 N 秒

**验收标准**：
- [ ] 每秒探测一个用户（轮询）
- [ ] RTT 计算正确
- [ ] 断开/降级的 Peer 不参与正常轮询
- [ ] 轮询索引循环正确

---

### Task 3.2 实现 Pong 响应

**优先级**：P0
**模块**：`client/lib/services/monitor_service.dart`
**描述**：收到 Ping 立即回复 Pong。

**具体操作**：
- 注册 Ping 消息处理
- 收到 Ping 后立即发送 Pong（回传 seq 和 ping_timestamp）

**验收标准**：
- [ ] Pong 响应及时
- [ ] seq 和 ping_timestamp 正确回传

---

### Task 3.3 实现丢包率统计

**优先级**：P0
**模块**：`client/lib/services/monitor_service.dart`
**描述**：基于 Ping/Pong 统计丢包率。

**输入参考**：实现文档 4.3 节

**具体操作**：
- 实现 PingStats 类（滑动窗口 30，Pong 超时 3000ms）
- 每 5 秒计算一次丢包率
- 更新 PeerProvider

**验收标准**：
- [ ] 丢包率每 5 秒更新
- [ ] 百分比保留一位小数
- [ ] 窗口大小正确

---

### Task 3.4 实现 UDP 消息路由分发

**优先级**：P0
**模块**：`client/lib/services/udp_service.dart`
**描述**：收到 UDP 消息后的统一路由。

**具体操作**：
- 在 UdpEventListener.onMessage 回调中根据 type 分发：
  - `ping` → MonitorService.onPingReceived
  - `pong` → MonitorService.onPongReceived
  - `punch` → 打洞响应处理
- 未知消息类型记录日志并忽略

**验收标准**：
- [ ] 消息类型正确路由
- [ ] 未知消息不导致崩溃

---

### Task 3.5 实现降级探测机制

**优先级**：P0
**模块**：`client/lib/services/monitor_service.dart`
**描述**：重连全部失败后，对已断开用户降级为每 1 分钟探测一次，如恢复连接则自动切回正常轮询。

**输入参考**：实现文档 4.1 节、需求文档 FR-006

**具体操作**：
- 实现 `startDegradedMonitoring(peerId)`：为指定用户创建 60 秒周期定时器
- 每分钟向该用户发送 Ping 探测
- 收到 Pong 响应时：取消降级定时器，状态恢复为 connected，重新加入正常轮询
- 实现 `_cancelDegradedTimer(peerId)`：取消降级定时器
- 用户被删除或清除时，同步清理降级定时器

**验收标准**：
- [ ] 重连失败后自动启动降级探测
- [ ] 降级探测间隔为 60 秒
- [ ] 降级期间用户状态显示「已断开（每分钟探测）」
- [ ] 降级探测收到 Pong 后自动恢复连接，切回正常轮询
- [ ] 用户删除/清除时降级定时器正确清理

---

## Phase 4 — 断线重连

### Task 4.1 实现重连策略和控制器

**优先级**：P0
**模块**：`client/lib/utils/reconnect.dart`
**描述**：实现梯度重连策略。

**输入参考**：实现文档 5.1、5.2 节

**具体操作**：
- 定义 ReconnectStrategy（intervals + maxAttempts）
- 实现 ReconnectController（start、cancel、回调）

**验收标准**：
- [ ] 重连间隔符合梯度策略
- [ ] 成功/失败回调正确触发
- [ ] cancel 可中断

---

### Task 4.2 实现断线检测

**优先级**：P0
**模块**：`client/lib/services/monitor_service.dart`
**描述**：通过轮询探测检测连接断开并触发重连。

**输入参考**：实现文档 5.3 节

**具体操作**：
- 在探测超时（Ping 无 Pong 响应）时判定连接断开
- 更新 Peer 状态为 reconnecting
- 创建 ReconnectController 执行 UDP 打洞重连

**验收标准**：
- [ ] 断开通过轮询探测被检测
- [ ] 重连进度更新到 UI
- [ ] 重连成功恢复状态，切回正常轮询
- [ ] 重连全部失败后启动降级探测（每 1 分钟探测一次）

---

### Task 4.3 实现网络切换处理

**优先级**：P1
**模块**：`client/lib/services/stun_service.dart`
**描述**：网络切换后重新获取 STUN 地址。

**具体操作**：
- 监听网络状态变化
- 网络切换后重新执行 STUN 获取
- 更新顶部地址展示
- 已有连接触发重连流程

**验收标准**：
- [ ] 网络切换后重新获取公网地址
- [ ] 顶部地址实时更新

---

### Task 4.4 集成降级探测到重连流程

**优先级**：P0
**模块**：`client/lib/services/monitor_service.dart`、`client/lib/utils/reconnect.dart`
**描述**：在重连控制器的 onFailure 回调中启动降级探测，确保重连失败后平滑过渡到降级监控状态。

**具体操作**：
- 在 ReconnectController 的 onFailure 回调中调用 `monitorService.startDegradedMonitoring(peerId)`
- 状态从 reconnecting → degradedMonitoring
- 降级探测恢复连接时，状态从 degradedMonitoring → connected
- 确保用户被删除/清除时，中断重连控制器并清理降级定时器

**验收标准**：
- [ ] 重连 5 次失败后自动转入降级探测
- [ ] 降级探测恢复连接后正确更新状态
- [ ] 用户删除时重连和降级定时器全部清理

---

## Phase 5 — 功能集成

### Task 5.1 集成添加用户完整流程

**优先级**：P0
**模块**：客户端多模块协作
**描述**：串联添加监听用户的全部步骤。

**完整流程**：
1. 用户点击「＋」按钮
2. 弹出 AddPeerDialog，输入 IP 和端口
3. 验证输入合法性，检查重复
4. 添加到 PeerProvider（状态：connecting）
5. 异步查询 IP 归属地（IpGeoService），更新 PeerProvider
6. 调用 UdpService.holePunch(ip, port, timeout=10s) 发起 UDP 打洞
7. 连接成功：状态变为 connected，启动 MonitorService
8. 连接失败：状态变为 failed
9. 持久化到本地存储

**验收标准**：
- [ ] 完整流程无中断
- [ ] 任何步骤失败有友好错误提示
- [ ] 连接状态实时更新

---

### Task 5.2 集成删除用户完整流程

**优先级**：P0
**模块**：客户端多模块协作
**描述**：串联删除监听用户的全部步骤。

**完整流程**：
1. 用户左滑呼出删除按钮
2. 点击删除
3. 停止该用户的 MonitorService
4. 取消该用户的 ReconnectController（如有）
5. 从 PeerProvider 移除
6. 更新本地存储

**验收标准**：
- [ ] 连接正确关闭
- [ ] 所有定时器清理
- [ ] 列表和存储同步更新

---

### Task 5.2a 集成一键清除断开连接流程

**优先级**：P0
**模块**：客户端多模块协作
**描述**：串联一键清除断开连接的全部步骤。

**完整流程**：
1. 用户点击「清除断开」按钮
2. 弹出确认对话框
3. 用户确认
4. 遍历所有已断开/降级监控中的用户
5. 停止每个用户的降级探测定时器
6. 取消进行中的 ReconnectController（如有）
7. 从 PeerProvider 移除用户
8. 更新本地存储

**验收标准**：
- [ ] 完整流程无中断
- [ ] 所有降级定时器和重连控制器正确清理
- [ ] 列表和持久化同步更新
- [ ] 无断开用户时按钮置灰

---

### Task 5.3 集成 App 启动流程

**优先级**：P0
**模块**：客户端多模块协作
**描述**：串联 App 启动的全部步骤，含 STUN 配置恢复和加载等待体验。

**完整流程**：
1. App 启动，界面显示 StunLoadingView（转圈 + 「正在获取公网地址…」）
2. 从本地存储加载 STUN 服务器配置（如有）
3. 初始化 UdpService.bind() 绑定本地 UDP 端口
4. 使用用户记录的 STUN 服务器（如有）或默认列表获取公网地址
5. 获取成功：进入主界面，更新 SelfInfoProvider
6. 获取失败：自动切换到 StunConfigScreen（STUN 配置界面）
7. 用户配置后重新获取成功 → 进入主界面
8. 从本地存储加载已保存的监听用户列表
9. 对每个已保存用户自动发起 UDP 打洞连接
10. 异步查询每个用户的 IP 归属地
11. 列表展示连接进度

**验收标准**：
- [ ] 启动时显示转圈加载动画
- [ ] STUN 配置从本地正确恢复
- [ ] STUN 获取失败自动切换到配置界面
- [ ] 配置界面可正常工作并重新获取
- [ ] 已保存用户自动重连

---

### Task 5.4 实现本地持久化服务

**优先级**：P1
**模块**：`client/lib/services/storage_service.dart`
**描述**：监听用户列表的本地持久化。

**输入参考**：实现文档 6 节

**具体操作**：
- 使用 shared_preferences 或 hive
- 实现 savePeers / loadPeers
- 仅持久化静态信息（IP、端口、添加时间）

**验收标准**：
- [ ] 添加/删除后自动保存
- [ ] App 重启后正确恢复
- [ ] 不保存运行时状态

---

## Phase 6 — 测试与优化

### Task 6.1 客户端单元测试

**优先级**：P1
**模块**：`client/`
**描述**：为核心逻辑编写单元测试。

**测试用例**：
- MonitoredPeer / SelfInfo 模型 JSON 序列化（含 ipLocation 字段）
- ReconnectController 重连策略和回调
- PingStats 丢包率计算
- PeerProvider / SelfInfoProvider 状态转换
- IpGeoService 归属地查询和缓存
- STUN 协议构造和解析
- IP 格式和端口范围校验

**验收标准**：
- [ ] 核心逻辑测试覆盖率 ≥ 70%
- [ ] `flutter test` 全部通过

---

### Task 6.2 UI 视觉优化

**优先级**：P2
**模块**：`client/`
**描述**：优化界面视觉效果和交互体验。

**具体操作**：
- 统一 Material Design 3 主题色和字体
- 连接状态颜色圆点动画（呼吸效果）
- 加载状态骨架屏或 Shimmer 效果
- 空状态插图
- 左滑删除动画优化
- 适配深色模式（可选）

**验收标准**：
- [ ] 界面整体风格统一
- [ ] 交互反馈清晰
- [ ] 无明显 UI 缺陷

---

### Task 6.3 实现日志工具

**优先级**：P1
**模块**：`client/lib/utils/logger.dart`
**描述**：实现客户端日志工具。

**具体操作**：
- 封装统一日志接口（debug、info、warning、error）
- 支持日志级别控制
- 关键操作记录日志：STUN 获取、连接建立/断开、重连

**验收标准**：
- [ ] 日志级别可控
- [ ] 关键流程有日志覆盖

---

### Task 6.4 编写项目 README

**优先级**：P1
**模块**：根目录
**描述**：编写项目 README。

**具体操作**：
- 项目简介和功能概览
- 技术栈说明
- 环境要求（Flutter、Dart 版本）
- 客户端构建指南（Android / iOS）
- 项目结构说明

**验收标准**：
- [ ] 新开发者可据此完成环境搭建
- [ ] 构建步骤准确无遗漏

---

## 任务依赖关系

```
Phase 0 (项目初始化)
  ├── Phase 1 (P2P 连接层 - 纯 Dart)
  │     └── Task 1.1 (UDP) → 1.2 (STUN) → 1.3 (IP 归属地)
  │
  ├── Phase 2 (客户端 UI)
  │     └── Task 2.1 → 2.2 → 2.3 → 2.4
  │           2.5~2.5d (STUN 配置相关) 依赖 2.3
  │           2.6~2.8 依赖 2.3, 2.4
  │           2.9 (清除断开) 依赖 2.4
  │
  ├── Phase 3 (连接监控) ← 依赖 Phase 1
  │     └── Task 3.1 → 3.2 → 3.3 → 3.4
  │           3.5 (降级探测) 依赖 3.1
  │
  ├── Phase 4 (断线重连) ← 依赖 Phase 1
  │     └── Task 4.1 → 4.2 → 4.3
  │           4.4 (降级探测集成) 依赖 4.2, 3.5
  │
  └── Phase 5 (功能集成) ← 依赖 Phase 2, 3, 4
        └── Task 5.1, 5.2, 5.2a (清除断开集成), 5.3, 5.4

        Phase 6 (测试优化) ← 依赖 Phase 5
```

## 并行开发建议

以下任务可以并行进行：

| 并行组 | 任务 | 说明 |
|--------|------|------|
| A | Phase 1 (P2P 连接 - 纯 Dart) + Phase 2 (客户端 UI) | P2P 层和 UI 层无直接依赖，可同时开发 |
| B | Phase 3 (连接监控) + Phase 4 (断线重连) | 两者都依赖 Phase 1，但彼此无依赖 |
| C | Task 6.1 (单元测试) + Task 6.2 (UI 优化) | 测试和 UI 优化可并行 |

---

> 本文档基于 产品文档 v2.3.0、需求文档 v2.3.0、实现文档 v2.3.0 自动生成，将随项目推进持续更新。
