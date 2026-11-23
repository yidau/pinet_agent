# PocketNet 开发镜像

在 Windows 11 的 Ubuntu 22.04 x86-64 WSL2 中进入仓库，首次安装构建依赖，再生成镜像。

    ./scripts/bootstrap-wsl.sh
    ./scripts/build-image.sh

构建器优先读取 WSL 用户的 SSH 公钥 ~/.ssh/id_ed25519.pub，其次读取 Windows 用户目录中的同名公钥。也可以把任意有效的 OpenSSH 公钥文件作为首个参数。

    ./scripts/build-image.sh /mnt/c/Users/你的Windows用户名/.ssh/id_ed25519.pub

构建过程将官方 Ubuntu 22.04.5 树莓派镜像的签名、SHA-256 和缓存分别核对，在 WSL 的临时工作副本上挂载 loop 分区，通过 QEMU ARM64 chroot 安装目标依赖和编译。构建日志保存在 /var/cache/pocketnet-image/logs/ 下。生成的 IMG、软件更新包、manifest.json 和 SHA256SUMS 放在 dist/。

## 烧录后通过网线调试

1. 把 Windows 的有线网卡设为 192.168.77.1，掩码 255.255.255.0，网关留空。
2. 使用 Raspberry Pi Imager 把 IMG 或 IMG.XZ 烧录到能容纳 8 GiB 镜像的存储卡，例如 16 GB 的卡。在烧录软件里保留镜像自带的配置。
3. 给 Raspberry Pi 4B 通电。首次启动时系统创建 yidau 调试账户和该设备专用的 SSH 主机密钥。可在开机前或开机后接上网线。
4. 在 Windows PowerShell 执行下面的命令。

       ssh -b 192.168.77.1 yidau@192.168.77.2

用构建时公钥对应的私钥登录。若 Windows SSH 选用了其他身份，用 -i 指定自己的私钥。SSH 独立于 PocketNet 初始化，便于排查热点或 BLE 启动故障。覆盖烧录后，若 Windows 仍记录旧密钥，先通过本机控制台核对新指纹，再更新旧记录。

## 通过 SSH 更新软件

在电脑上核对 dist/SHA256SUMS，然后通过 SCP 传输 pocketnet-release-…-jammy-arm64.tar.gz。

    scp -o BindAddress=192.168.77.1 <更新包> yidau@192.168.77.2:~/

首次升级到 RAM-first 版本时，将当前源码里的 `deploy/release/install.sh` 一同通过 SCP 上传到家目录，并用它安装更新包。填入更新包在 SHA256SUMS 中的哈希。

    sudo bash ~/install.sh --sha256 <SHA-256> ~/<更新包>

之后可以直接调用设备上已更新的安装器。

    sudo /opt/pocketnet/deploy/install-release.sh --sha256 <SHA-256> ~/<更新包>

更新器保留设备身份、手机注册、TLS 和 Kismet 凭据。升级失败时回退软件链接和修改过的系统配置。树莓派事件缓冲在 RAM，历史以手机 SQLite 为准。已有版本留下的事件文件保留供回退，RAM-first 服务不再打开它们。完整镜像适用于新卡或重新初始化。

镜像和 SSH 升级都安装 32 MiB 的 volatile journald 配置和 64 MiB 的 `/tmp` tmpfs 单元。就地升级后，`/tmp` 在下一次启动时切换。Ubuntu 的 `/run` 与 `/dev/shm` 作为 RAM 运行目录，本次不迁移 `/var/lib` 或添加 swap。真实 SD 卡写入量、网卡和手机通信由实机验收确认。

需要预配外接 USB 监听网卡时，在目标镜像的 /etc/pocketnet/usb-monitor.conf 中填写一行“接口名 USB 厂商 ID USB 产品 ID USB 端口 驱动名”。永久注册二维码生成在 /root/piagent-enrollment.svg。

可在 Ubuntu 22.04 WSL2 离线检查已经生成的镜像。

    ./scripts/verify-image.sh dist/<镜像>.img.xz

## WSL 构建验证

验证环境为 Ubuntu 22.04.5 x86-64 WSL2。运行 bootstrap-wsl.sh 后，QEMU ARM64 binfmt 检查和工作文件的 loop 挂载检查通过。Ubuntu 官方镜像 SHA256SUMS 的签名和官方 IMG.XZ 的 SHA-256 均通过。

构建器在 ARM64 chroot 中生成 Protobuf/gRPC 绑定并完成 C++ Release 编译。file 和 readelf 确认为 AArch64，目标 chroot 的 ldd 无缺失库。镜像验证器确认 Python 3.12.16、Kismet 2026-10-R1、首次启动与 SSH 单元、预设有线地址，以及根分区和启动分区文件系统。

构建失败清理也实际验证过。软件源返回 HTTP 503 的一次构建结束后，losetup 和 findmnt 均未找到该工作 IMG 残留的 loop 或挂载点，日志保留在 WSL 缓存目录。烧录后的 SSH 登录、无线与 BLE 留作树莓派实机验收。

## RAM-first storage and swap validation

The image enables volatile journald, mounts /tmp as bounded tmpfs, and runs Kismet's HTTP session database under /run. Kismet authentication and device identity remain persistent. The image installs zram-tools with ALGO=lz4, PERCENT=25, and PRIORITY=100; block-backed swap entries are removed from /etc/fstab, and swapfile.swap / dphys-swapfile.service are masked.

On a running device, verify:

```bash
findmnt /run /tmp /dev/shm
swapon --show
zramctl
systemctl is-active zramswap.service
systemctl show piagent-kismet.service -p MainPID
pid=$(systemctl show piagent-kismet.service -p MainPID --value)
grep -E '^(VmRSS|VmHWM):' "/proc/$pid/status"
journalctl -u piagent-telemetry.service -b --since '2 minutes ago' --no-pager
```

Only /dev/zram* should appear in swapon --show. A block-backed swap device is a failed SD-card-write policy check. The EventStore's 16 MiB figure is serialized Protobuf payload, not total heap/RSS; compare the Telemetry RSS journal metric and Kismet's separate RSS.
