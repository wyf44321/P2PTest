# P2PTest

P2P 网络质量基准测试工具 — 提供纯净的 P2P 连接环境，自动检测 NAT 类型并建立点对点连接。

## 功能概览

- **NAT 类型检测**：启动时顺序查询所有 STUN 服务器，根据端口变化自动判断 NAT 类型（非对称 / 对称型），并展示在主界面
- **公网地址获取**：通过 STUN 服务获取自身公网 IP 和端口
- **STUN 服务配置**：支持用户手动配置 STUN 服务器，提供默认可选列表
- **NAT 映射保活**：始终使用同一个 socket，若 5 秒无发包则自动向 STUN 服务器发送保活包
- **NAT 元数据**：NAT 类型信息编码为元数据字符串（如 `cone`、`sym,d=2`），附加在候选地址后，便于对端做端口预测决策
- **监听用户管理**：手动添加/删除监听用户，支持粘贴含 NAT 元数据的候选地址
- **1 字节随机包**：所有发往监听用户的 UDP 包均为 1 字节随机内容，轻量高效
- **智能发包策略**：
  - 非对称 NAT / 内网地址：每 10ms 发一次，1 分钟无回包则重连（最多 5 次）
  - 对称型 NAT：根据元数据预测端口步长，向基础端口 ±5N 范围同时发包，探测到联通端口后锁定
- **并行发包**：不同用户的发包规则并行执行，但共用同一个 socket
- **自动重连**：1 分钟无回包触发重连，5 次重连失败后判定断开
- **IP 归属地展示**：自动查询并展示 IP 归属地信息，分行展示避免遮挡 NAT 类型
- **一键清除**：一键清除所有已断开连接的监听用户

## 技术栈

| 技术 | 版本要求 |
|-----|---------|
| Flutter | ≥ 3.19 |
| Dart | ≥ 3.3 |

### 核心依赖

| 功能 | 包 |
|-----|---|
| 状态管理 | `provider` |
| UDP 通信 | `dart:io` (`RawDatagramSocket`) |
| STUN 客户端 | 纯 Dart 实现 |
| IP 归属地 | `http` (ip-api.com) |
| 本地存储 | `shared_preferences` |

## 环境搭建

1. 安装 Flutter SDK (≥ 3.19): https://flutter.dev/docs/get-started/install
2. 确保 Dart SDK ≥ 3.3

## 构建与运行

```bash
cd client

# 安装依赖
flutter pub get

# 运行（开发模式）
flutter run

# 指定设备运行
flutter run -d <device_id>

# 构建 Android APK
flutter build apk --release

# 构建 iOS
flutter build ios --release
```

## 项目结构

```
P2PTest/
├── docs/                          # 文档
│   └── 产品文档（参考）.md
├── client/                        # 客户端 (Flutter/Dart)
│   ├── lib/
│   │   ├── main.dart              # App 入口
│   │   ├── app/
│   │   │   ├── app.dart           # App 根组件
│   │   │   └── theme.dart         # 主题配置
│   │   ├── config/
│   │   │   ├── constants.dart     # 常量配置
│   │   │   └── stun_servers.dart  # STUN 服务器默认列表
│   │   ├── models/
│   │   │   ├── monitored_peer.dart # 监听用户模型（含 NAT 元数据）
│   │   │   ├── peer_candidate.dart # 候选地址模型
│   │   │   └── self_info.dart     # 本端信息模型（含 NAT 类型）
│   │   ├── services/
│   │   │   ├── udp_service.dart   # UDP 服务：1字节包发送、保活
│   │   │   ├── stun_service.dart  # STUN 服务：多服务器查询、NAT 分析
│   │   │   ├── monitor_service.dart # 连接服务：每用户发包循环、重连
│   │   │   ├── ip_geo_service.dart # IP 归属地查询服务
│   │   │   └── storage_service.dart # 本地持久化服务
│   │   ├── providers/
│   │   │   ├── peer_provider.dart  # 监听用户状态管理
│   │   │   └── self_info_provider.dart # 本端信息状态管理
│   │   ├── screens/
│   │   │   ├── home_screen.dart   # 主界面
│   │   │   └── stun_config_screen.dart # STUN 服务器配置界面
│   │   ├── widgets/
│   │   │   ├── public_address_card.dart # 公网地址卡片（含 NAT 类型）
│   │   │   ├── peer_card.dart     # 监听用户卡片
│   │   │   ├── add_peer_dialog.dart # 添加用户对话框
│   │   │   └── stun_loading_view.dart # STUN 加载等待视图
│   │   └── utils/
│   │       ├── logger.dart        # 日志工具
│   │       └── validators.dart    # 输入校验工具（含 NAT 元数据解析）
│   └── pubspec.yaml
└── README.md
```

## NAT 类型检测原理

启动时，应用会顺序向 STUN 服务器列表中的所有服务器发送 Binding Request：
- 若所有服务器返回的公网端口相同 → **非对称 NAT**（cone），元数据为 `cone`
- 若端口有变化 → **对称型 NAT**（symmetric），计算端口步长 N，元数据为 `sym,d=N`

候选地址格式：`内网IP:端口,公网IP:端口|NAT元数据`

例：`192.168.1.100:12345,1.2.3.4:50001|sym,d=2`

## 发包策略

| 场景 | 策略 |
|-----|------|
| 内网 / 非对称 NAT | 每 10ms 向已知地址发 1 字节包 |
| 对称型 NAT | 每 10ms 向 basePort ± 5×step 范围端口同时发包 |
| 收到回包 | 锁定该端口，切换为单端口发送 |
| 1 分钟无回包 | 触发重连 |
| 重连 | 最多 5 次，每次 1 分钟窗口 |
| 5 次重连失败 | 判定断开，停止发包 |

## 平台要求

| 平台 | 最低版本 |
|-----|---------|
| iOS | 14.0+ |
| Android | 8.0 (API 26)+ |

## 多设备调试

| 场景 | 设备组合 | 说明 |
|-----|---------|------|
| 最小化 | 2 台模拟器 | 适合调试基本流程 |
| 推荐 | 1 台模拟器 + 1 台真机 | 更接近真实环境 |
| 完整 | 多台真机（跨网络） | 测试 NAT 穿透和真实网络指标 |

## 版本

v3.0.0
