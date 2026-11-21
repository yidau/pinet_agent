# 树莓派 MCP 工具清单与验证

## `aa2f817` 基线清单

11 个工具都由 `raspberry/mcp_server/server.py` 注册。FastMCP 提供标准 `tools/list` 和 `tools/call`，通过 Starlette ASGI 应用在 `/mcp` 提供无状态 Streamable HTTP 和 JSON 响应，由 Uvicorn 运行。

工具列表和调用都需要 Bearer 认证。设备登记模式只接受登记数据库中状态为 `active` 的设备令牌。使用旧式令牌配置启动时，服务验证配置的服务令牌。下表的只读和写入是工具声明，认证由外层 ASGI 入口统一执行。

| 工具 | 基线描述 | 参数 | 实现与数据来源 | 权限 | 基线返回字段 |
| --- | --- | --- | --- | --- | --- |
| `get_system_info` | 读取执行节点的操作系统、内核、主机名和 CPU 架构 | 空对象 | Python `platform`，Linux 系统名称来自 os-release | 认证，只读 | `hostname`、`os`、`kernel`、`architecture` |
| `get_cpu_info` | 读取 CPU 使用率、逻辑核数和可用的 CPU 温度 | 空对象 | `psutil` 采样 0.1 秒并查询已知 CPU 温度传感器 | 认证，只读 | `logical_cores`、`used_percent`、`temperature_c`，缺少温度读数时为 `null` |
| `get_memory_info` | 读取物理内存总量、可用字节和使用率 | 空对象 | `psutil.virtual_memory` | 认证，只读 | `total_bytes`、`available_bytes`、`used_percent` |
| `get_disk_usage` | 读取工作区所在文件系统的空间和使用率 | 空对象 | `psutil.disk_usage` 查询工作区根目录 | 认证，只读 | `total_bytes`、`used_bytes`、`free_bytes`、`used_percent` |
| `list_files` | 列出工作区某目录下可见的文件和子目录 | `path` 字符串，默认 `.` 代表工作区根目录 | `workspace.py` 枚举并过滤目录项 | 认证，只读 | `path`、`entries`，每项含 `name`、`type` |
| `read_file` | 读取工作区中的 UTF-8 文本文件，最多 64 KiB | 必填 `path` 字符串 | `workspace.py` 读取普通文件 | 认证，只读 | `path`、`content` |
| `create_directory` | 在已存在的父目录中创建一个工作区目录 | 必填 `path` 字符串 | `workspace.py` 校验路径后创建目录 | 认证，可写入 | `path` |
| `create_project` | 创建顶层 C++17 CMake 项目，已有项目会保留 | 必填 `name` 字符串 | `workspace.py` 生成 `CMakeLists.txt` 和 `main.cpp` | 认证，可写入 | `name`、`created` |
| `write_file` | 新建或覆盖工作区的 UTF-8 文件，最多 64 KiB，父目录须已存在 | 必填 `path`、`content` 字符串 | `workspace.py` 校验路径与大小后原子替换文件 | 认证，可覆盖 | `path`、`bytes_written` |
| `compile_project` | 在新沙箱中配置并编译 CMake 项目，返回执行阶段和诊断 | 必填 `name` 字符串 | `workspace.py` 生成快照，`sandbox.py` 使用 rootless Docker 构建 | 认证，可执行构建 | `ok`、`stage`、`exit_code`、`timed_out`、`output` |
| `run_tests` | 在沙箱中构建新快照并运行 CTest，缺少测试视为失败 | 必填 `name` 字符串 | `workspace.py` 生成快照，`sandbox.py` 构建并运行 CTest | 认证，可执行构建和测试 | `ok`、`stage`、`exit_code`、`timed_out`、`output` |

基线的 `path` 参数长度为 1–512 字符。`name` 以 ASCII 字母开头，后续可以是 ASCII 字母、数字、下划线或连字符，长度为 1–48 字符。`content` 的 Schema 上限为 65,536 字符，写入还受 64 KiB 的 UTF-8 字节限制。

## 更新后的设备观察结果

四项设备工具的采集逻辑位于 `raspberry/mcp_server/device_observations.py`。MCP 层注册工具、校验参数并转换结果。`tools/list` 仍列出这 11 个实际工具。Flutter V0.4 的 Agent 根据只读声明和自己的工具范围筛选能力。

- 成功结果的 `structuredContent` 保留原有顶层字段，并附带 `source` 和 ISO 8601 UTC `timestamp`。`get_system_info` 的四个字符串继续用于 Flutter 的「测试树莓派连接」。
- 使用率单位为百分比，存储和内存用字节表示，温度用摄氏度表示。设备未提供可用温度时，`temperature_c` 为 `null`。
- 工具参数 Schema 由 SDK 根据实际签名生成。服务端拒绝清单中未声明的参数，四项设备工具使用空对象。
- 采集失败通过 MCP `isError` 返回，包含错误类型、原因和是否可重试，并提供 Flutter 能直接显示的文本。
- 本基线没有网络查询工具，T6 和 F4 不适用。能力列表以设备实际注册的工具为准。

## 手动更新已有树莓派

在树莓派上进入包含本次修改的源码仓库。用 `systemctl show` 查询当前服务使用的目录。若工作目录就是已更新的仓库，只需重启服务。分开安装时，复制以下两个 Python 文件，并沿用现有安装文件的所有者和权限。

```bash
(
  set -eu
  repo_root="$(git rev-parse --show-toplevel)"
  install_root="$(systemctl show piagent-mcp.service -p WorkingDirectory --value)"
  test -n "$install_root"
  target="$install_root/raspberry/mcp_server"
  test -f "$target/server.py"
  owner="$(stat -c '%u' "$target/server.py")"
  group="$(stat -c '%g' "$target/server.py")"
  mode="$(stat -c '%a' "$target/server.py")"
  if ! test "$repo_root/raspberry/mcp_server/server.py" -ef "$target/server.py"; then
    sudo install -o "$owner" -g "$group" -m "$mode" \
      "$repo_root/raspberry/mcp_server/"{device_observations,server}.py "$target/"
  fi
  sudo systemctl restart piagent-mcp.service
  systemctl is-active piagent-mcp.service
)
```

## 验证记录

### 本地验证

| 用例 | 结果 |
| --- | --- |
| T1–T5、A1–A2 | 3 项本地用例通过。覆盖启动、11 项工具发现、描述及参数 Schema、四项设备查询、采集失败、登记令牌和未授权请求。 |
| F1–F3 | 1 项本机回环联调通过。现有 Flutter 客户端连接临时 MCP 服务，发现四项设备能力并成功读取系统信息。 |
| T6、F4 | 基线没有网络查询工具。 |

每项本地验证均在 3 分钟内完成。

### 实机结果

通过有线 SSH 更新了两个 MCP 文件，并重启 `piagent-mcp.service`，服务状态为 `active`。用户用现有 V0.4 安卓 App 重新连接，确认工具列表显示新版 `get_system_info` 描述，调用结果包含 `source` 和 `timestamp`。这次实机反馈覆盖 F1–F3。

### 手动复验步骤

每项最多 3 分钟。

1. 确认 `piagent-mcp.service` 为 `active`。手机连接 PiAgent 热点，在 V0.4 App 中点「连接设备」并打开「设备能力」，核对可见的四项状态查询。
2. 用 App 的「测试树莓派连接」核对主机名、操作系统、内核和架构。有云端模型配置时，可用 Agent 查询 CPU、内存或磁盘，核对返回单位。
3. 核对已授权手机能够查询。对同一 MCP URL 发送不带设备令牌的请求，预期返回 HTTP 401。
