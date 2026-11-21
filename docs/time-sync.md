# PiAgent V0.2 蓝牙离线校时

手机通过 BLE 向 Raspberry Pi 4B 提供时间。部署后的校时服务由 systemd 在树莓派启动时运行。完成首次配对和授权后，手机可在没有 Wi-Fi、蜂窝数据和外部 NTP 的情况下校准 Linux 系统时间。部署只安装校时模块及其 systemd 单元，沿用现有的热点、SSH 和 MCP 配置。

## 部署

树莓派需要可用的蓝牙控制器、BlueZ、systemd 和 Python 3.11 或更新版本，并已安装 Python `venv` 支持。可在有网络时准备 BlueZ 等系统组件及 `raspberry/time_sync/requirements.txt` 中的依赖，再把离线 wheel 目录和本版本源码复制到树莓派。校时服务启动和运行时无需外网。

在树莓派的仓库根目录执行以下命令。将 `WHEELS` 改为树莓派上的离线 wheel 目录。

```bash
WHEELS=/path/to/wheels
sudo install -d -m 0755 /opt/piagent-time-sync/raspberry/time_sync
sudo install -m 0644 raspberry/time_sync/*.py /opt/piagent-time-sync/raspberry/time_sync/
sudo python3 -m venv /opt/piagent-time-sync/.venv
sudo /opt/piagent-time-sync/.venv/bin/python -m pip install \
  --no-index --find-links "$WHEELS" -r raspberry/time_sync/requirements.txt

sudo install -D -m 0644 raspberry/config/time-sync/piagent-time-sync.sysusers.conf \
  /etc/sysusers.d/piagent-time-sync.conf
sudo systemd-sysusers /etc/sysusers.d/piagent-time-sync.conf
sudo install -m 0644 raspberry/config/time-sync/*.service \
  raspberry/config/time-sync/*.socket /etc/systemd/system/
sudo install -d -m 0755 /etc/piagent-time-sync
sudo touch /etc/piagent-time-sync/peer
sudo chown root:root /etc/piagent-time-sync/peer
sudo chmod 0644 /etc/piagent-time-sync/peer

sudo systemctl daemon-reload
sudo systemctl enable --now bluetooth.service piagent-clock.socket piagent-ble-time-sync.service
```

`piagent-ble` 用户运行 GATT 服务。调时程序由本地 Unix 套接字 `/run/piagent-clock.sock` 激活，以独立的 `piagent-clock` 用户运行，权限限于 `CAP_SYS_TIME`。套接字仅供指定 BLE 服务账户访问，调时程序接收固定格式的时间数据。代码、虚拟环境和可信设备名单由管理员维护。 [systemd 套接字所有权与权限](https://freedesktop.org/software/systemd/man/latest/systemd.socket.html) · [systemd 进程能力](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html)

手机端从 `mobile` 构建。Android 使用 SDK 36，BLE 插件 5.5.0 沿用项目现有的 Kotlin 模式，并用同一 SDK 编译。构建命令为 `flutter build apk --release`。已有私用 APK 的连接预设时，可沿用原来的 `--dart-define-from-file` 参数。校时功能独立使用蓝牙，开始扫描时申请所需权限。

## 首次配对和使用

1. 在树莓派管理员终端运行 `sudo bluetoothctl`，保持该窗口打开，依次执行 `power on`、`agent DisplayYesNo`、`default-agent` 和 `pairable on`。
2. 在手机 PiAgent 打开「蓝牙校时」和「扫描树莓派」，选中 `PiAgent`。应用读取加密特征时，系统可发起配对。核对手机和管理员终端显示的是同一组六位数字，再在两端确认。配对尚未授权时，应用会提示管理员授权。 [BlueZ 配对代理](https://bluez.readthedocs.io/en/latest/agent-api/)
3. 用 `bluetoothctl devices Paired` 找出刚核对过的手机，用 `info 手机地址` 核对其配对和绑定状态，然后执行 `trust 手机地址`。把 BlueZ 显示的这台手机的设备身份地址写到 `/etc/piagent-time-sync/peer` 的唯一一行。地址格式为 `AA:BB:CC:DD:EE:FF`，应取自配对后的 BlueZ 设备信息。
4. 执行 `pairable off` 后退出 `bluetoothctl`，然后运行 `sudo systemctl restart piagent-ble-time-sync.service` 读取授权名单。手机断开后重新扫描连接，再点「开始校时」。发生回拨时，核对偏移量并选择「确认回拨」。完成后页面显示偏移、估算往返延迟和树莓派读回的 UTC 时间。

空名单时，BLE 服务可广播并接受系统配对流程，校时接口拒绝访问。授权需同时满足经过认证的加密链路、BlueZ 已配对和绑定、管理员信任及名单匹配。普通连接或另一个设备仅凭广告信息无法调时。 [BlueZ GATT 服务与特征权限](https://bluez.readthedocs.io/en/latest/gatt-api/)

## GATT 协议

服务 UUID 为 `2f70e150-8c6b-4ee4-8f11-25d94aa85c00`。特征 UUID 使用同一前缀，末尾两位替换为下表后缀。二进制帧采用大端字节序。时间戳使用有符号 64 位 UTC Unix 毫秒。`B`、`H`、`Q` 分别为无符号 8 位、16 位、64 位整数，`q` 为有符号 64 位整数。所有二进制帧都可放在默认 ATT MTU 的 20 字节载荷内。

| 特征 | 后缀 | 操作 | 数据格式 |
| --- | --- | --- | --- |
| DeviceInfo | `01` | 读 | UTF-8 设备标识 `PiAgent/xxxxxxxx` |
| TimeSyncRequest | `02` | 认证加密写，要求有响应 | `>BQHq`，19 字节。操作码、会话 nonce、样本 ID、时间戳。操作码 `1` 提交 T1，`2` 提交所选样本的 T4，`3` 提交 T4 并确认回拨 |
| TimeSyncResponse | `03` | 认证加密读 | `>Hqq`，18 字节。样本 ID、T2、T3 |
| TimeSyncResult | `04` | 认证加密读 | `>QHBq`，19 字节。会话 nonce、样本 ID、结果码、实际读回的树莓派 UTC 毫秒。失败或暂无结果时，时间字段为零 |
| TimeStatus | `05` | 认证加密读 | `>BBQ`，10 字节。版本 `1`、阶段、非零随机会话 nonce。阶段 `0` 采样，`1` 应用，`2` 结束 |

结果码为 `0` 成功、`1` 拒绝、`2` 执行失败、`3` 需要确认回拨、`4` 暂无结果、`5` 等待结果。每轮样本 ID 为 `1` 至 `5`，请求和结果通过会话 nonce 与样本 ID 关联。手机在一轮开始前读取 TimeStatus。已有采样且应用请求尚未提交时，重新读取会放弃旧采样并开始新的一轮。正在应用时返回阶段 `1`。树莓派首次处理该样本的响应读取时记录 T3，手机收到响应时记录 T4。

手机记录请求发送时的 T1 和响应接收时的 T4。树莓派记录探测请求到达时的 T2 和响应发出前的 T3。计算如下。

```text
偏移 θ = ((T2 − T1) + (T3 − T4)) / 2
往返延迟 δ = (T4 − T1) − (T3 − T2)
校准量 = −θ
```

`θ` 向零截断到整数毫秒。正偏移表示树莓派超前，应用回拨前需在手机确认。手机从最多五次探测中选择有效往返延迟最小的样本。有效样本要求 δ 在 `0` 至 `750 ms`，两端各自的时间跨度在 `0` 至 `5000 ms`，手机 UTC 时间在 `2024-01-01` 至 `2100-01-01` 之前，调整量绝对值不超过 `5 × 366` 天。会话按单调时钟计时，有效期 60 秒。校时程序设置系统时钟后读回 UTC 时间，并使用单调时钟测量耗时。

断线会清除该连接的采样会话。应用请求已经送出但结果尚未收到时，应标记结果未确认，并在重新连接后读取对应会话和样本的结果。重复提交不会用于确认结果。协议拒绝过期、错配和重放请求。正常 BLE 环境下与手机相差 1 秒以内是实机验收目标。

## 交付验收记录

只执行表中的时间同步与 SSH 测试。每项记录实际结果和相应证据，如手机界面、Pi 的 UTC 读回或 SSH 命令退出状态。超过五分钟仍无结果时记录「未验证（超时）」和待补证据。全部指定项目实际通过后才签收 V0.2。

本地代码检查使用 `python -m unittest discover -s tests -p test_time_sync.py -v`。6 项通过，覆盖 T1、T2、T3、T6 和 T7 的算法、边界校验及调时服务返回逻辑。Flutter 校时模块静态分析通过，Android ARM64 release 构建通过。调时使用模拟时钟，表中保留真实设备结果。

### 时间同步 T1–T7

使用真实手机和树莓派。开始 T1 前让树莓派正常关机后断电重启，记录 BLE 服务是否自动启动、手机是否能扫描连接和通过已有的可信配对访问。调整测试时钟时只做受控的短时偏移，测试后恢复到手机时间。

| 编号 | 操作和通过证据 | 当前结果 |
| --- | --- | --- |
| T1 | 让树莓派比手机慢约 30 秒后发起同步。偏移为负，收到成功结果，读回与手机 UTC 相差 1 秒以内 | 未验证 |
| T2 | 让树莓派比手机快约 30 秒。偏移为正，在手机确认回拨后收到成功结果，读回与手机 UTC 相差 1 秒以内 | 未验证 |
| T3 | 连续完成两轮同步。每轮最多采样五次，记录有效样本和所选最小延迟，两轮均收到各自的成功结果 | 未验证 |
| T4 | 在 T2 的回拨确认界面关闭手机蓝牙，再确认操作。记录断线失败提示，并读回树莓派时间确认未发生此次回拨 | 未验证 |
| T5 | 断开树莓派的外网上行，手机关闭 Wi-Fi 和蜂窝数据并开启蓝牙。保留可信配对并完成一轮同步，收到成功结果 | 未验证 |
| T6 | 从已授权的受控 BLE 客户端，用上一轮已结束的 nonce 发送一笔应用请求。记录拒绝，确认树莓派未因此产生时钟跳变 | 未验证 |
| T7 | 同步成功后立即比较手机 UTC、应用显示的读回时间和树莓派 `date -u` 的结果。记录观察到的差值，目标在 1 秒以内 | 未验证 |

### SSH S1–S5

T1–T7 全部通过后，在同一局域网内执行。使用现有的 SSH 配置和用户公钥。电脑应事先从可信管理员终端核实树莓派的主机公钥指纹。 [OpenSSH 客户端配置](https://man.openbsd.org/ssh_config)

| 编号 | 操作和通过证据 | 当前结果 |
| --- | --- | --- |
| S1 | 检查树莓派 `ssh.service` 的运行状态。若部署使用套接字激活，核对 `ssh.socket` 的监听状态 | 未执行 |
| S2 | 从电脑连接树莓派的局域网地址，记录 SSH 会话建立成功 | 未执行 |
| S3 | 在可信终端用 `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` 核对指纹。使用严格主机密钥检查连接，记录检查成功 | 未执行 |
| S4 | 电脑以公钥单独认证，记录登录成功和命令退出码 `0`。示例见下方 | 未执行 |
| S5 | 树莓派正常关机后断电重启，从手机完成校时，再从电脑重复 S3、S4，记录两项通过 | 未执行 |

```bash
ssh -o StrictHostKeyChecking=yes -o BatchMode=yes -o PreferredAuthentications=publickey \
  -o IdentitiesOnly=yes -i /path/to/private_key pi-user@192.168.77.2 true
```
