# 用手机控制树莓派（V0.7.1）

覆盖安装 V0.7.1 安卓包，连接原来的 PiAgent 热点，在 App 顶部点「连接设备」。已注册手机沿用现有身份，撤销授权后服务端拒绝后续请求。日常操作通过热点 HTTPS 直达树莓派，离线时也可使用。云端 AI 可查询已产生的结果。

| 手机操作 | 预期结果 |
| --- | --- |
| Wireless → 扫描 Wi-Fi | 树莓派用已配置的无线接口执行一次扫描，界面显示执行状态，完成后 Wi-Fi Networks 自动更新。数据来源为 Managed Scan，普通扫描快照有效期为 5 分钟。 |
| Wireless → 开始蓝牙发现 | 在最长 120 秒的发现窗口中，Bluetooth Devices 显示实际观测。可随时点「停止蓝牙发现」。 |
| Captures → 从手机导入 | 用 Android 文件选择器选 PCAP 或 PCAPNG，确认文件名。成功后可在离线文件列表中点开元信息。单文件上限为 64 MiB，库内最多 64 个文件，重名会提示更换名称。 |
| Captures → 开始重放 → 选择文件 | 树莓派读取本地文件，手机显示进度状态、文件源 UUID 和可用的设备记录。可点「停止重放」，短文件可能直接显示已完成。 |

## 从已部署的 V0.7 更新树莓派

使用这次更新的源码，在仓库根目录执行。已有的 Kismet、热点、注册数据库、证书和 BLE 校时服务可以继续使用。

```bash
work=$(systemctl show -p WorkingDirectory --value piagent-mcp.service)
test -n "$work" && test -d "$work/raspberry/mcp_server" || exit 1
if [ "$(realpath raspberry/mcp_server)" != "$(realpath "$work/raspberry/mcp_server")" ]; then
    sudo install -m 0644 raspberry/mcp_server/*.py "$work/raspberry/mcp_server/" || exit 1
fi
# 旧版可能把普通扫描程序的父目录装成仅 root 可进入。
sudo install -d -o root -g root -m 0755 /usr/lib/piagent-managed-scan \
    /usr/lib/piagent-managed-scan/raspberry /usr/lib/piagent-managed-scan/raspberry/mcp_server || exit 1
sudo python3 raspberry/config/kismet/configure_sources.py || exit 1
# 如正在重放文件，先让当前任务正常结束。
sudo systemctl try-restart piagent-replay.service
sudo systemctl restart piagent-mcp.service
```

直接由 MCP 提供 TLS 的安装使用同一个端口。若现有 HAProxy HTTPS 入口只允许 `/mcp`，在原 frontend 内把该路径规则更新为下列三行，沿用原来的 `allowed_host` 定义、设备认证和后端转发。检查配置后重载对应 HTTPS 服务。

```haproxy
    acl piagent_api_path path /mcp
    acl piagent_api_path path_beg /operator/
    http-request deny unless piagent_api_path allowed_host
```

手机只在已注册、已连接且服务端声明 `operator_api: 1` 时显示操作按钮。按钮通过 `/operator/` 发送用户指令，MCP 仍发布 51 项能力。浏览页面只读取状态。树莓派用受限的本地服务启动固定的扫描任务，重放限于已校验的本地文件。
