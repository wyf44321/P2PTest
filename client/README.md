# P2PTest Client

Flutter 客户端 — P2P 网络质量基准测试工具。

## 快速开始

```bash
# 安装依赖
flutter pub get

# 运行
flutter run

# 代码分析
flutter analyze
```

## 架构说明

- **状态管理**: Provider 模式
- **P2P 通信**: 纯 Dart `RawDatagramSocket` UDP 实现
- **STUN 客户端**: 纯 Dart 实现 STUN Binding Request (RFC 5389)
- **持久化**: SharedPreferences

详细文档参见 `docs/` 目录。
