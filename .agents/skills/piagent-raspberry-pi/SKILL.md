---
name: piagent-raspberry-pi
description: 在 PiAgent（PocketNet AI）仓库中检查树莓派 Ubuntu 和有线 SSH，开发或部署设备端 MCP 与扫描助手，或排查 systemd 服务、管理热点和 BLE 校时。用在涉及 PiAgent 树莓派端的开发、诊断和发布任务。
---

# PiAgent 树莓派开发与部署

## 按任务查资料

- 新设备安装、有线直连和 HTTPS 服务配置见 [项目 README](../../../README.md)。先读目标机的 `/etc/os-release` 和 CPU 架构，依照实际 Ubuntu 版本处理系统依赖。
- V0.8 的 MCP 和扫描助手清单、服务重启和实机判据见 [V0.8 无线观测说明](../../../docs/v0.8-wireless.md)。部署其他版本时按对应版本的文档或实际变更确定清单。
- 手机无线操作与助手配置见 [无线操作说明](../../../docs/phone-controls.md)。BLE 校时协议和验收见 [时间同步说明](../../../docs/time-sync.md)。

## 连接和只读诊断

1. 优先使用用户给定或已在本项目确认的有线 SSH 目标。README 中电脑 `192.168.77.1`、树莓派 `192.168.77.2` 是直连配置示例。Windows 上有多个网络接口时，核对有线网卡地址，必要时用 `ssh -b` 绑定它。
2. 用已有的 SSH 主机密钥记录验证身份。遇到密钥变化时先核对指纹。区分无法建立 SSH 连接、认证被拒绝和成功登录。成功后用 `hostname` 与 `ip -br addr` 确认设备及有线地址。使用现有授权的认证方式；密码、私钥、设备令牌和云端 API Key 保留在各自的凭据存储中。
3. 查 MCP 运行状态可以执行 `systemctl show piagent-mcp.service -p ActiveState -p SubState -p Result -p MainPID`。诊断启动失败时读 `journalctl -u piagent-mcp.service -b -n 40 --no-pager`。用户仅要求检查连接时，确认 SSH 登录即可。
4. 排查热点和扫描共存时，先用 `iw dev` 枚举接口及其 PHY。同一 PHY 上的两个接口共用同一块无线电。`iw dev` 是只读枚举，`iw dev <接口> scan` 会发起扫描。

## 构建和部署

- C++ 原生服务优先在 Windows 电脑上借助 WSL 或 Linux 容器交叉编译，生成适配目标 Ubuntu 的 ARM64 产物后再上传。使用与目标发行版匹配的 ARM64 工具链和 sysroot，核对 ELF 架构及动态库版本。WSL 的 x86_64 测试产物用于本地验证。交叉构建确实不可行时，再按当前部署授权在树莓派上构建。

1. 按用户指定的版本和范围列出源文件与目标。用 `systemctl show piagent-mcp.service -p WorkingDirectory -p User -p Group -p FragmentPath` 获取实际服务目录和运行账户，有覆盖配置时用 `systemctl cat piagent-mcp.service` 核对。目标模块通常在该工作目录的 `raspberry/mcp_server/` 下。
2. 更新助手时核对对应 systemd 单元的 `WorkingDirectory` 和 `ExecStart`。已有安装中，普通扫描助手使用 `/usr/lib/piagent-managed-scan/raspberry/mcp_server/managed_scan.py`，手机无线操作助手使用 `/usr/local/lib/piagent-sources/raspberry/mcp_server/phone_radio.py`。同名模块可能在 MCP 目录另有一份，按本次清单核对每个目标。
3. 先传到树莓派的私有临时目录，用本机 SHA-256 核对传输内容，再按服务所需的所有者和权限替换指定文件。更新方式按用户授权执行。直接替换时只暂存本次新文件。安装后逐一核对目标文件的 SHA-256。
4. 只重启本次更新要求的服务。仅更新 MCP 与按调用加载的这两个助手 Python 文件时，重启 `piagent-mcp.service` 即可。单元定义发生变化且在任务范围内时才需要重新加载 systemd 配置。重启后检查服务状态及新 PID，失败时检查启动日志并报告。清理由本次部署创建的临时文件。

## 验证和交付

- 分别记录本地测试、设备文件校验、服务运行状态和手机实机验收。需要主动发起扫描、持续观测、BLE 校时或重启设备时，按本轮实机验收授权执行。用户自行验收时，部署后只读检查服务状态。
- 交付记录写清树莓派目标、更新范围、文件校验结果、重启的服务和实际验证结果。实机验收由用户负责时，附上对应页面、只读命令和通过标准。
