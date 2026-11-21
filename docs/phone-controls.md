# 用手机控制树莓派

覆盖安装安卓包，连接原来的 PiAgent 热点，在 App 顶部点「连接设备」。已注册手机沿用现有身份，撤销授权后服务端拒绝后续请求。日常操作通过热点 HTTPS 直达树莓派，离线时也可使用。云端 AI 可查询已产生的结果。

| 手机操作 | 预期结果 |
| --- | --- |
| Wireless → 扫描 Wi-Fi | 树莓派用已配置的无线接口执行一次扫描，界面显示执行状态，完成后 Wi-Fi Networks 自动更新。数据来源为 Managed Scan，普通扫描快照有效期为 5 分钟。 |
| Wireless → 开始蓝牙发现 | 在最长 120 秒的发现窗口中，Bluetooth Devices 显示实际观测。可随时点「停止蓝牙发现」。 |
| Captures → 从手机导入 | 用 Android 文件选择器选 PCAP 或 PCAPNG，确认文件名。成功后可在离线文件列表中点开元信息。单文件上限为 64 MiB，库内最多 64 个文件，重名会提示更换名称。 |
| Captures → 开始重放 → 选择文件 | 树莓派读取本地文件，手机显示进度状态、文件源 UUID 和可用的设备记录。可点「停止重放」，短文件可能直接显示已完成。 |

## V0.7.4 查看网络、接入点和观测历史

打开「无线 → 无线网络」。默认的「网络」视图将名称完全相同的 SSID 放在同一行。每行显示当前可见的 BSSID 数、信道数和信号强度。隐藏网络按 BSSID 分开列出。一个物理设备可以广播多个 BSSID。

点网络名称查看各 BSSID，再点一个 BSSID 查看观测时间、dBm、信道和来源。也可以直接切到「接入点」或「信道」。同一次扫描的结果读取多次，历史里仍只保留一份。信号范围取各 BSSID 最近可用的读数。Kismet 报告的设备关联会显示在详情中。

新版 APK 连接旧服务时也能按 SSID 分组。要保留多次普通扫描的历史，需同时更新树莓派 MCP 和普通扫描助手。助手按本次开机保存最近 4096 条普通扫描样本，每个 BSSID 的详情最多返回 64 条近期记录。树莓派重启后会开始新的普通扫描历史。

2026 年 11 月 22 日，树莓派 MCP 和普通扫描助手更新到 V0.7.4 后，设备所有者确认已完成手机实机验收。发布前通过了 16 项后端测试和 15 项 Flutter 测试。

已安装 V0.7.1 手机扫描功能的设备，在新版源码根目录运行以下命令即可更新。扫描助手在下次点「扫描 Wi-Fi」时加载新代码。

```bash
(
    set -eu
    src=$(realpath raspberry/mcp_server)
    work=$(systemctl show -p WorkingDirectory --value piagent-mcp.service)
    test -n "$work"
    test -d "$work/raspberry/mcp_server"
    mcp=$(realpath "$work/raspberry/mcp_server")
    if [ "$src" != "$mcp" ]; then
        for module in ap_observations capabilities kismet_adapter managed_scan wireless_service; do
            sudo install -m 0644 "$src/$module.py" "$mcp/"
        done
    fi
    sudo install -m 0644 "$src/managed_scan.py" "$src/kismet_adapter.py" /usr/lib/piagent-managed-scan/raspberry/mcp_server/
    sudo systemctl restart piagent-mcp.service
)
```

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
