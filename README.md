# PiAgent

Mobile AI Agent for Linux System Management & Development

在手机上用自然语言管理 Raspberry Pi 并开发 Linux 程序。Flutter 应用运行 Agent 循环并调用云端模型。树莓派通过 MCP Streamable HTTP 提供系统、文件和 CMake 工具。

## V0.1

- 查询系统、CPU、温度、内存和磁盘状态。
- 浏览工作区、读写 UTF-8 文件、创建目录和 C++17 CMake 项目。
- 把 CMake 和 CTest 的执行结果交回手机端模型，让模型根据诊断修复并重试。手机显示工具执行结果，并在 SQLite 中保存消息和工具状态。
- 编译和测试从工作区快照启动独立容器。容器无网络、无宿主机目录挂载，使用只读根文件系统，并限制 CPU、内存、进程数、输出和执行时间。

## 在 Raspberry Pi 上启动

使用支持 cgroup v2 的 64 位 Raspberry Pi OS、Python 3.11+ 和启用了 seccomp 的 rootless Docker。运行服务和 Docker 的账户应为同一非 root 账户。先配置 rootless Docker 的 CPU、内存和 PID 控制器委派，再构建镜像。参考 [Docker rootless 安装文档](https://docs.docker.com/engine/security/rootless/) 和 [资源限制配置](https://docs.docker.com/engine/security/rootless/tips/#limiting-resources)。

```bash
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/docker.sock"
docker info
docker build -t piagent-builder:0.1 raspberry/config

python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r raspberry/requirements.txt

export PIAGENT_TOKEN="$(python -c 'import secrets; print(secrets.token_urlsafe(32))')"
python -m raspberry.mcp_server.server
```

默认地址是 `http://127.0.0.1:8000/mcp`。默认工作区是 `raspberry/workspace`。也可用 `--workspace` 指定由服务账户独享的目录。命令日志记录工具名称和执行状态。

手机访问时，使用手机信任的证书，并确保地址与证书名称匹配。下例中的主机名、证书和私钥路径需替换为实际值。

```bash
python -m raspberry.mcp_server.server \
  --host 0.0.0.0 --port 8443 \
  --allow-host pi.example.net:8443 \
  --tls-cert /path/to/fullchain.pem --tls-key /path/to/privkey.pem
```

## 运行手机端

安装 Flutter 3.47 或更新版本和目标平台的工具链。Android 需要 Android SDK，iOS 需要 macOS 和 Xcode。手机需能访问树莓派的 MCP 地址和云端模型 API。

```bash
cd mobile
flutter pub get
flutter run
```

打开「配置连接」，输入树莓派 MCP 完整地址、`PIAGENT_TOKEN`、支持工具调用的 Chat Completions API 完整地址、模型名称和 API Key。连接设置保留在应用进程内。模型会收到任务消息和相关工具结果，云端 API Key 用于手机直连模型服务。

## 运行 Windows 客户端

使用已安装「使用 C++ 的桌面开发」工作负载的 Visual Studio 构建。可分发文件位于 `mobile/build/windows/x64/runner/Release/`，运行时请保留该目录中的 DLL 和 `data/`。

```powershell
cd mobile
flutter build windows --release
```

如果树莓派上的 MCP 服务监听本机端口 8000，可以从 Windows 打开有线 SSH 隧道。将 SSH 用户名和 IP 换成实际值。

```powershell
ssh -N -L 127.0.0.1:19842:127.0.0.1:8000 yidau@192.168.77.2
```

打开「配置连接」，填写 `http://127.0.0.1:19842/mcp` 和设备令牌，点击「测试树莓派连接」。成功后界面会显示主机名、系统、架构和内核。

聊天默认使用 DeepSeek 的 `deepseek-flash`。Windows 客户端会从项目根目录或应用程序旁的 `deepseekapi.txt` 读取单行 API Key，也可在设置中手动填写。Git 会忽略该文件。

## 验收

在手机中选择「运行 C++17 验收」并发送。确认任务实际创建 C++17 生产者消费者队列，编译成功，并且 CTest 验证了线程间的 FIFO 顺序与关闭行为。展开工具结果可查看编译和测试输出。

下列脚本使用真实 MCP 和编译沙箱，依次注入编译错误、写入修复并检查 CTest 结果。它会在工作区生成一个独立的 `queue_*` 项目。

```bash
python tests/mcp_acceptance.py http://127.0.0.1:8000/mcp
```

### 本地回归验证

```bash
python -m unittest discover -s tests -v
cd mobile
flutter analyze
flutter test
```
