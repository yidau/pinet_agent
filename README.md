# PiAgent 0.3.0

用手机管理 Raspberry Pi 和开发 Linux 程序。手机负责 Agent 决策和云端模型调用，树莓派执行 MCP 工具。App 可以读取系统状态、管理工作区，并在配置 Rootless Docker 后编译 C++17 项目和运行 CTest。

首次注册时，手机扫描树莓派的永久二维码，通过蓝牙完成授权。每台手机使用独立的热点密码和 MCP 令牌。安装完成后，扫码注册、蓝牙校时和手机访问树莓派可以离线运行。使用 DeepSeek 聊天时，手机仍需能访问互联网。

## 1. 准备一台新的 Ubuntu 树莓派

- 建议使用 Raspberry Pi 4B 和 **Ubuntu Server 26.04 LTS ARM64**。本项目曾在 Ubuntu 26.04.1 ARM64 上完成真机部署。Ubuntu Server 24.04 LTS 的 Python 版本也满足依赖要求。Ubuntu 22.04 自带 Python 3.10，建议先升级系统。 [Ubuntu 树莓派镜像与说明](https://ubuntu.com/hardware/docs/boards/how-to/ubuntu_supported/raspberry-pi/)
- 开启 SSH，将电脑和树莓派接到同一局域网，用 Ubuntu 安装时创建的普通用户登录。有线连接用于安装和后续管理。安装软件包和 Python 依赖时，树莓派需要能访问互联网。以下树莓派命令均从该普通用户的 Bash 执行。
- 用 `ip -br link` 确认内置无线接口是 `wlan0`。如果树莓派暂时通过 Wi-Fi 上网，先下载完第 3 步的依赖，再将 `wlan0` 交给 PiAgent 热点。

```bash
sudo apt update
sudo apt install -y git python3-venv bluez rfkill hostapd dnsmasq-base openssl curl iproute2
git clone --branch v0.3.0 https://gitee.com/zhaojiayi1101/piagent.git
cd piagent
```

若电脑和树莓派以后直插网线使用，将下列 `addresses` 合并到树莓派现有的 Netplan 有线接口配置中。`eth0` 请按实际接口名修改。通过 `sudo netplan try` 应用配置，再将电脑有线网卡设为 `192.168.77.1/24`，网关留空，即可用 `ssh 用户名@192.168.77.2` 直连。 [Netplan 静态地址示例](https://netplan.readthedocs.io/en/stable-0.106/examples/)

```yaml
network:
  version: 2
  ethernets:
    eth0:
      addresses: [192.168.77.2/24]
```

## 2. 配置手机热点和 DHCP

以下配置将热点命名为 `PiAgent`。将 `country_code=CN` 改为树莓派所在国家或地区的两字母代码。先保留空的热点凭据表，等待手机扫码注册后生成独立密码。 [独立热点凭据说明](docs/v0.3-wifi.md)

```bash
sudo install -d -m 0755 /etc/hostapd
sudo install -d -m 0700 /var/lib/piagent-enrollment
sudo test -e /var/lib/piagent-enrollment/hostapd.psk ||
  sudo install -m 0600 /dev/null /var/lib/piagent-enrollment/hostapd.psk
sudo tee /etc/hostapd/piagent.conf >/dev/null <<'EOF'
interface=wlan0
driver=nl80211
ssid=PiAgent
country_code=CN
hw_mode=g
channel=6
ieee80211d=1
ctrl_interface=/run/hostapd
ctrl_interface_group=0
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_psk_file=/var/lib/piagent-enrollment/hostapd.psk
disable_pmksa_caching=1
EOF

sudo tee /etc/piagent-dnsmasq.conf >/dev/null <<'EOF'
interface=wlan0
bind-interfaces
port=0
dhcp-authoritative
dhcp-range=192.168.4.20,192.168.4.80,255.255.255.0,12h
dhcp-option=option:router
dhcp-option=option:dns-server
dhcp-leasefile=/run/piagent-dhcp/dnsmasq.leases
EOF

sudo tee /etc/systemd/system/piagent-hotspot.service >/dev/null <<'EOF'
[Unit]
Description=PiAgent Wi-Fi hotspot
BindsTo=sys-subsystem-net-devices-wlan0.device
After=sys-subsystem-net-devices-wlan0.device

[Service]
ExecStartPre=/usr/sbin/ip link set wlan0 up
ExecStartPre=/usr/sbin/ip address replace 192.168.4.1/24 dev wlan0
ExecStart=/usr/sbin/hostapd /etc/hostapd/piagent.conf
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/piagent-dhcp.service >/dev/null <<'EOF'
[Unit]
Description=PiAgent hotspot DHCP
Requires=piagent-hotspot.service
After=piagent-hotspot.service
PartOf=piagent-hotspot.service

[Service]
RuntimeDirectory=piagent-dhcp
ExecStart=/usr/sbin/dnsmasq --keep-in-foreground --conf-file=/etc/piagent-dnsmasq.conf
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF
```

DHCP 只给手机分配本地地址。使用云端模型时，手机需保留一条可用的互联网连接，例如蜂窝数据。 [dnsmasq 配置说明](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html)

## 3. 安装服务并生成永久二维码

在仓库根目录执行。此安装使用 MCP 服务自带的 HTTPS，只监听热点地址 `192.168.4.1:8443`。以下命令在设备本地生成 CA 和服务器证书，手机注册时会获得对应的 CA 证书。

```bash
piagent_user="$(id -un)"
piagent_group="$(id -gn)"
test "$(id -u)" -ne 0

sudo install -m 0644 raspberry/config/time-sync/piagent-time-sync.sysusers.conf \
  raspberry/config/enrollment/piagent-enrollment.sysusers.conf /etc/sysusers.d/
sudo systemd-sysusers /etc/sysusers.d/piagent-time-sync.sysusers.conf \
  /etc/sysusers.d/piagent-enrollment.sysusers.conf

sudo install -d -m 0755 /opt/piagent-time-sync/raspberry/{enrollment,time_sync} \
  /opt/piagent-enrollment/raspberry/enrollment \
  /opt/piagent-mcp/raspberry/{enrollment,mcp_server}
sudo install -m 0644 raspberry/time_sync/*.py /opt/piagent-time-sync/raspberry/time_sync/
sudo install -m 0644 raspberry/enrollment/*.py /opt/piagent-time-sync/raspberry/enrollment/
sudo install -m 0644 raspberry/enrollment/wifi_helper.py /opt/piagent-enrollment/raspberry/enrollment/
sudo install -m 0644 raspberry/enrollment/{__init__,registry}.py /opt/piagent-mcp/raspberry/enrollment/
sudo install -m 0644 raspberry/mcp_server/*.py /opt/piagent-mcp/raspberry/mcp_server/

sudo python3 -m venv /opt/piagent-time-sync/.venv
sudo /opt/piagent-time-sync/.venv/bin/python -m pip install \
  -r raspberry/time_sync/requirements.txt -r raspberry/enrollment/requirements.txt
sudo python3 -m venv /opt/piagent-mcp/.venv
sudo /opt/piagent-mcp/.venv/bin/python -m pip install -r raspberry/requirements.txt

sudo install -d -m 0750 -o root -g piagent-enrollment /var/lib/piagent-devices
sudo install -d -m 0700 -o "$piagent_user" -g "$piagent_group" /var/lib/piagent-mcp/workspace
sudo install -d -m 0755 /etc/piagent-https
sudo sh <<'EOF'
set -eu
umask 077
cd /etc/piagent-https
test ! -e ca.key
test ! -e server.key
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -noenc -sha256 \
  -days 3650 -subj '/CN=PiAgent Local CA' -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,keyCertSign,cRLSign' -keyout ca.key -out ca.pem
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -noenc \
  -subj '/CN=192.168.4.1' -keyout server.key -out server.csr
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
  -days 365 -sha256 -extfile /dev/stdin -out server.pem <<'EXT'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth
subjectAltName=IP:192.168.4.1
EXT
chgrp piagent-enrollment server.key
chmod 0640 server.key
chmod 0644 ca.pem server.pem
EOF

(
  cd /opt/piagent-time-sync
  sudo .venv/bin/python -m raspberry.enrollment.admin init \
    --device-id "$(hostname -s)" --ssid PiAgent \
    --mcp-url https://192.168.4.1:8443/mcp --ca-file /etc/piagent-https/ca.pem \
    --qr-file /root/piagent-enrollment.svg
)
sudo chown piagent-ble:piagent-enrollment /var/lib/piagent-devices \
  /var/lib/piagent-devices/{device.key,authority.json,devices.sqlite3}
sudo chmod 2750 /var/lib/piagent-devices
sudo chmod 0640 /var/lib/piagent-devices/devices.sqlite3
```

依赖装好后，从有线 SSH 用 `sudo netplan edit` 移除现有的 `wlan0` Wi-Fi 客户端配置，再运行 `sudo netplan try`。全新系统若只配置了有线网络，可直接继续。接着将 MCP 与蓝牙、调时和热点凭据服务设为随系统启动。

```bash
sudo tee /etc/systemd/system/piagent-mcp.service >/dev/null <<EOF
[Unit]
Description=PiAgent HTTPS MCP Server
Requires=piagent-hotspot.service
After=piagent-hotspot.service
PartOf=piagent-hotspot.service

[Service]
User=$piagent_user
WorkingDirectory=/opt/piagent-mcp
ExecStart=/opt/piagent-mcp/.venv/bin/python -m raspberry.mcp_server.server --host 192.168.4.1 --port 8443 --allow-host 192.168.4.1:8443 --tls-cert /etc/piagent-https/server.pem --tls-key /etc/piagent-https/server.key --workspace /var/lib/piagent-mcp/workspace
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF

sudo install -m 0644 raspberry/config/time-sync/*.service raspberry/config/time-sync/*.socket \
  raspberry/config/enrollment/*.service raspberry/config/enrollment/*.socket /etc/systemd/system/
sudo install -D -m 0644 raspberry/config/enrollment/ble-enrollment.conf \
  /etc/systemd/system/piagent-ble-time-sync.service.d/enrollment.conf
sudo install -D -m 0644 raspberry/config/enrollment/mcp-device-auth.conf \
  /etc/systemd/system/piagent-mcp.service.d/device-auth.conf

sudo systemctl daemon-reload
sudo rfkill unblock wifi
sudo rfkill unblock bluetooth
sudo systemctl enable --now bluetooth.service
sudo bluetoothctl power on
sudo systemctl enable --now piagent-hotspot.service piagent-dhcp.service piagent-mcp.service \
  piagent-clock.socket piagent-enrollment-wifi.socket piagent-ble-time-sync.service

systemctl is-active piagent-hotspot piagent-dhcp piagent-mcp piagent-ble-time-sync
curl --cacert /etc/piagent-https/ca.pem -sS -o /dev/null -w '%{http_code}\n' \
  https://192.168.4.1:8443/mcp
```

四个服务应显示 `active`。最后一条命令预期返回 `401`，表示 HTTPS 已启动且正在要求设备令牌。由同一个 CA 签发的服务器证书到期后，用原 CA 重新签发包含同一 IP 的服务器证书，并重启 `piagent-mcp`。

## 4. 安装 App 并注册手机

在构建电脑上准备 Flutter 3.47+、Dart 3.13+、Android SDK 和 JDK 17。Android 11+ 支持 App 调起系统的热点保存确认。以下命令构建 ARM64 手机安装包。

```bash
cd mobile
flutter pub get
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

安装包位于 `mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`，路径从仓库根目录计算。仓库当前使用 Android 调试签名，生成的 APK 可侧载。构建公开安装包时，请勿传入 DeepSeek API Key 或设备令牌。

1. 从树莓派的 `/root/piagent-enrollment.svg` 私下取出永久二维码，打印或在另一块屏幕上显示。用有线 SSH 取文件时，在树莓派执行下列复制命令，然后在电脑运行 `scp 用户名@树莓派IP:piagent-enrollment.svg .`。取出后删除树莓派家目录中的临时副本。
2. 打开手机蓝牙和 Wi-Fi。进入 App 的「手机注册」，填写手机名称，点「扫描树莓派的永久二维码」，允许使用摄像头和附近设备。
3. 确认系统添加 `PiAgent` 热点。若手机未自动切换，在 Wi-Fi 设置里连接已保存的 `PiAgent`，回 App 点「测试 HTTPS 和 MCP 连接」。
4. 打开「蓝牙校时」，选中树莓派并点「开始校时」。若要使用自然语言 Agent，在「配置连接」填写自己的云端 API Key。DeepSeek 可使用 `https://api.deepseek.com/chat/completions` 和模型 `deepseek-flash`。 [DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)

```bash
sudo install -m 0600 -o "$(id -u)" -g "$(id -g)" \
  /root/piagent-enrollment.svg "$HOME/piagent-enrollment.svg"
```

永久二维码用于授权新手机，应由设备所有者保管。后续注册可继续使用这张二维码。请勿将二维码、设备数据库、证书私钥或 API Key 上传到 Gitee。

## 5. 可选配置 C++ 编译和 CTest

用第 3 步运行 MCP 的同一个普通用户安装 Rootless Docker，确认启用 cgroup v2、seccomp 及 CPU、内存、交换区和 PID 限制。Ubuntu 上可按 Docker 官方说明安装 `docker-ce-rootless-extras`，然后由普通用户执行以下命令。 [Rootless Docker 安装](https://docs.docker.com/engine/security/rootless/) · [资源限制配置](https://docs.docker.com/engine/security/rootless/tips/#limiting-resources)

```bash
dockerd-rootless-setuptool.sh install
sudo loginctl enable-linger "$(id -un)"
systemctl --user enable --now docker.service
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/docker.sock"
docker info
docker build -t piagent-builder:0.1 raspberry/config
```

完成后，在 App 发送 C++17 验收任务，查看 CMake 编译和 CTest 的实际结果。设备代码工作区为 `/var/lib/piagent-mcp/workspace`。编译容器使用工作区快照，运行时没有网络和宿主机目录挂载。

## 运维与验收

```bash
cd /opt/piagent-time-sync
sudo -u piagent-ble .venv/bin/python -m raspberry.enrollment.admin list
sudo -u piagent-ble .venv/bin/python -m raspberry.enrollment.admin registration off
sudo -u piagent-ble .venv/bin/python -m raspberry.enrollment.admin registration on
sudo journalctl -u piagent-ble-time-sync -u piagent-mcp -u piagent-hotspot -n 80 --no-pager
```

用 `admin revoke DEVICE_ID` 可撤销指定手机。设备将失去热点、校时和 MCP 权限。V0.3 已实测单机扫码、校时、热点和 MCP 访问，以及撤销和恢复。断电重启后注册新手机、双手机撤销和 iOS 构建仍待验证。每项实机测试超过 4 分钟可记录为跳过。 [实机验收记录与协议](docs/v0.3-enrollment.md)
