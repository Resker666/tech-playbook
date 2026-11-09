# Windows Debug

记录 Windows 使用过程中遇到的问题、排查过程、调试命令以及最终解决方案。

这个目录更偏向实际问题复盘，而不是系统性的 Windows 教程。

---

## Contents

### [amdafdapp-auto-launch.md](./amdafdapp-auto-launch.md)

Windows 开机后自动弹出 `amdafdapp.exe` / Terminal 窗口的问题排查与解决。

主要涉及：

- Windows Task Scheduler
- AMD 驱动组件
- 启动项排查
- Service 排查
- Parent Process 追踪
- PowerShell 调试命令

---

### [codex-ubuntu-ssh-troubleshooting.md](./codex-ubuntu-ssh-troubleshooting.md)

Codex Desktop 无法通过 SSH 连接本地 Ubuntu 虚拟机的排障与修复记录（已匿名化）。

主要涉及：

- Windows OpenSSH / VMware Ubuntu
- SSH 密码认证与非交互式公钥认证
- `BatchMode=yes` 故障定位
- Ed25519 独立密钥与 `ssh_config`
- Codex 远程连接恢复验证

---

## Topics

后续可能继续补充：

- Windows 开机启动问题
- Driver / DriverStore
- Task Scheduler
- Service
- Registry
- PowerShell
- 网络问题
- WSL
- SSH
- 系统性能与资源占用
- 软件异常启动
