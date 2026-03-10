# P2PTest

P2P 网络质量基准测试工具 — 提供纯净的 P2P 连接环境，测量真实的网络延迟、丢包率等指标。

## 功能概览

- **公网地址获取**：通过 STUN 服务获取自身公网 IP 和端口
- **STUN 服务配置**：支持用户手动配置 STUN 服务器，提供默认可选列表
- **监听用户管理**：手动添加/删除监听用户，输入对方 IP 和端口建立 P2P 连接
- **实时监控**：轮询探测连接状态，实时展示延迟（RTT）和丢包率
- **IP 归属地展示**：自动查询并展示监听用户的 IP 归属地信息
- **自动重连**：断线后梯度重连机制，重连失败后降级为每分钟探测
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
│   ├── 产品文档.md
│   ├── 需求文档.md
│   ├── 实现文档.md
│   └── Tasks.md
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
│   │   │   ├── monitored_peer.dart # 监听用户模型
│   │   │   └── self_info.dart     # 本端信息模型
│   │   ├── services/
│   │   │   ├── udp_service.dart   # UDP P2P 连接服务
│   │   │   ├── stun_service.dart  # STUN 公网地址获取
│   │   │   ├── monitor_service.dart # 连接监控服务
│   │   │   ├── ip_geo_service.dart # IP 归属地查询服务
│   │   │   └── storage_service.dart # 本地持久化服务
│   │   ├── providers/
│   │   │   ├── peer_provider.dart  # 监听用户状态管理
│   │   │   └── self_info_provider.dart # 本端信息状态管理
│   │   ├── screens/
│   │   │   ├── home_screen.dart   # 主界面
│   │   │   └── stun_config_screen.dart # STUN 服务器配置界面
│   │   ├── widgets/
│   │   │   ├── public_address_card.dart # 公网地址卡片
│   │   │   ├── peer_card.dart     # 监听用户卡片
│   │   │   ├── add_peer_dialog.dart # 添加用户对话框
│   │   │   └── stun_loading_view.dart # STUN 加载等待视图
│   │   └── utils/
│   │       ├── logger.dart        # 日志工具
│   │       ├── validators.dart    # 输入校验工具
│   │       └── reconnect.dart     # 重连策略
│   └── pubspec.yaml
└── README.md
```

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

v2.3.0
