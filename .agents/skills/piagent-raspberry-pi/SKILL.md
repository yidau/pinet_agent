---
name: piagent-raspberry-pi
description: 在 PocketNet 仓库中检查、构建或部署 Raspberry Pi Linux 监测服务、Kismet 无线采集、C++ gRPC 遥测、BLE 注册与时间同步、systemd 和管理热点。
---

# PocketNet 树莓派开发与部署

## 当前架构

- 树莓派端没有 MCP Server，也没有 Agent Runtime。
- C++ 常驻 Telemetry 服务是唯一的业务通信端点，使用 TLS gRPC + Protobuf。
- Kismet 是唯一原始无线采集引擎，默认受管 Linux Wi-Fi source 使用 `filter_mgmt=true`。
- `raspberry/wireless` 只包含小型 Python USB 无线设备管理器和 Kismet REST 适配器，不提供 MCP/HTTP 业务 API。
- BLE Enrollment 与 BLE Time Sync 暂时仍由 Python 运行；目标系统需提供 Python 3.12。
- 内置 Wi-Fi 只提供管理热点；外接 USB 网卡是唯一 Monitor Mode 设备，不得回退使用热点网卡。
- 手机使用 gRPC 订阅快照和事件；未来如需 MCP，应作为上层适配器，通过 Protobuf/gRPC 调用设备端。

## 按任务查资料

- 新设备安装和基本配置见 [项目 README](../../../README.md)。
- 无线 USB 设备绑定和 Kismet 采集见 [V1 无线管理器说明](../../../docs/v1.0-wireless-manager.md)。
- 遥测协议、C++ 服务和消息恢复见 [V1 遥测说明](../../../docs/v1.0-telemetry.md)。
- 手机 BLE 注册与操作见 [手机操作说明](../../../docs/phone-controls.md)。
- BLE 校时协议见 [时间同步说明](../../../docs/time-sync.md)。

## 机器检测规则

所有真实树莓派、无线网卡、驱动、systemd 和负载检测由项目所有者亲自执行。实施 Agent 只提供命令并分析用户返回的结果，不得假装连接或控制设备。

常用只读检查：

```bash
uname -a
cat /etc/os-release
lscpu
free -h
lsusb
iw dev
iw phy
ip -br link
systemctl is-active piagent-hotspot piagent-kismet piagent-wireless-manager piagent-telemetry piagent-ble-time-sync
```

检查 Kismet 采集源和状态：

```bash
cat /run/piagent-wireless/monitor.json
journalctl -u piagent-wireless-manager.service -u piagent-kismet.service -b -n 60 --no-pager
```

## 构建与部署

- C++ Telemetry 使用 C++17/CMake/gRPC/Protobuf，优先在匹配 Ubuntu 22.04 ARM64 的构建环境或交叉工具链中构建。
- 不得把在 Ubuntu 26.04 上链接到较新 glibc 的二进制直接复制到 Ubuntu 22.04。
- Python 只用于 BLE 注册、BLE 校时和 USB/Kismet datasource 管理；不要重新引入树莓派 MCP Server、MCP SDK 或 MCP HTTP endpoint。
- Kismet 管理器安装到 `/usr/local/lib/piagent-wireless/raspberry/wireless/`，systemd 执行 `python -m raspberry.wireless.wireless_manager`。
- Kismet 核心与 capture helper 必须来自同一发行版和匹配版本。
- Kismet API 凭据只允许 loopback 访问；readonly key 由 C++ Telemetry 使用，datasource 管理 key 由隔离的 wireless manager 使用。

## 验证和交付

- 区分本地编译/模拟测试与树莓派实机验收。
- 不得把代码检查或模拟结果描述为 Monitor Mode、filter_mgmt 实际过滤、USB 热插拔或 2GB 性能已验证。
- 每次部署列出修改文件、构建结果、服务变化和回滚方式。
- 树莓派升级、烧录、服务安装、Kismet 维护重启和真实负载测试均由用户执行。
