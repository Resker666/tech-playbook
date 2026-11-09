# Codex Desktop SSH 连接 Ubuntu 虚拟机失败：排查与修复

> 记录日期：2026-11-09  
> 环境：Windows 11、VMware Ubuntu、Codex Desktop、Windows OpenSSH  
> 状态：已修复  
> 隐私声明：文中的用户名、IP 地址、SSH Host 都是示例，请替换为实际环境配置。

## 1. 问题现象

此前 Codex Desktop 能通过 SSH 正常连接本地 Ubuntu 虚拟机，后来突然无法连接，报错：

~~~text
Permission denied (publickey,password).
~~~

但在 Windows PowerShell 中，普通 SSH 连接仍然可以通过输入密码成功登录：

~~~powershell
ssh ubuntu_local "whoami"
# 输入 Ubuntu 用户密码后：
# devuser
~~~

因此，网络连通性、SSH 服务运行状态、用户名及密码均不是当时的主要故障点。需要继续验证 Codex 所需的**非交互式认证**是否可用。

## 2. 排查过程

### 2.1 模拟非交互式 SSH 登录

~~~powershell
ssh -T -o BatchMode=yes -o ControlMaster=no -o ControlPath=none ubuntu_local "whoami"
~~~

故障时返回：

~~~text
Permission denied (publickey,password).
~~~

参数说明：

- `-T`：不分配伪终端。
- `BatchMode=yes`：关闭密码、密钥口令等交互式提示。
- `ControlMaster=no`：不创建 SSH 复用主连接。
- `ControlPath=none`：不通过复用套接字复用已有 SSH 连接。

**关键判断：普通密码 SSH 登录成功，不等于自动化客户端可以在无交互条件下完成认证。**

### 2.2 检查 Windows SSH 配置

打开：

~~~powershell
notepad "$env:USERPROFILE\.ssh\config"
~~~

原 SSH Host 只有主机地址和用户名：

~~~sshconfig
Host ubuntu_local
    HostName 192.168.56.101
    User devuser
~~~

没有显式指定用于此 Ubuntu 主机的独立 SSH 私钥。注意：仅凭缺少 `IdentityFile` 并不能证明必然失败；真正的验证依据是前面的 `BatchMode=yes` 测试。

## 3. 原因判断

**已确认：** 在故障环境中，SSH 密码登录正常，但非交互式 SSH 登录失败。配置专用公钥认证后，Codex Desktop 恢复连接。

**尚未证实：** 为什么“以前能连接、后来不能连接”。可能与 Codex 版本更新、曾经可用的交互式认证/连接状态变化、旧 SSH 配置或密钥状态变化有关。没有足够证据将最初诱因归结为某一次 Codex 更新。

## 4. 修复步骤

以下为可复用示例。假定：

- Windows 本地用户通过 `$env:USERPROFILE` 引用，不写入真实用户名；
- Ubuntu 登录用户为 `devuser`；
- Ubuntu 示例 IP 为 `192.168.56.101`；
- SSH Host 为 `ubuntu_local`；
- 专用私钥名为 `id_ed25519_ubuntu_local`。

### 4.1 生成独立的 Ed25519 密钥

在 **Windows PowerShell** 执行：

~~~powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\id_ed25519_ubuntu_local" -C "ubuntu-local"
~~~

如果同名文件已存在，先检查并复用，**不要覆盖原有私钥**。

生成两个文件：

~~~text
~/.ssh/id_ed25519_ubuntu_local       # 私钥，不得公开
~/.ssh/id_ed25519_ubuntu_local.pub   # 公钥
~~~

安全建议：可以给私钥设置口令并使用 `ssh-agent` 缓存，以支持无交互连接；如果选择无口令专用密钥，应严格保护本地私钥和系统账户。

### 4.2 将公钥追加到 Ubuntu 授权文件

将示例用户名和 IP 改为实际值后，在 Windows PowerShell 执行：

~~~powershell
Get-Content "$env:USERPROFILE\.ssh\id_ed25519_ubuntu_local.pub" |
ssh devuser@192.168.56.101 "umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys"
~~~

此处会要求输入一次 Ubuntu 登录密码。命令把公钥追加到远端的 `~/.ssh/authorized_keys`，不会覆盖原有授权，但重复运行可能产生重复条目。

### 4.3 配置 Windows OpenSSH Host

~~~powershell
notepad "$env:USERPROFILE\.ssh\config"
~~~

修改对应 Host（如果已经存在，编辑原配置块，不要重复添加相同别名）：

~~~sshconfig
Host ubuntu_local
    HostName 192.168.56.101
    User devuser
    Port 22
    IdentityFile ~/.ssh/id_ed25519_ubuntu_local
    IdentitiesOnly yes
~~~

其中：

- `IdentityFile`：显式指定给本地 Ubuntu 使用的私钥；
- `IdentitiesOnly yes`：避免自动尝试与该 Host 无关的其他身份密钥。

GitHub、云服务器等其他 SSH Host 及其独立密钥无需修改。

### 4.4 验证无交互连接

先执行：

~~~powershell
ssh -o BatchMode=yes ubuntu_local "whoami"
~~~

再执行更严格的测试：

~~~powershell
ssh -T -o BatchMode=yes -o ControlMaster=no -o ControlPath=none ubuntu_local "whoami"
~~~

预期均直接输出：

~~~text
devuser
~~~

无需输入密码或密钥口令，即说明当前 SSH 公钥认证可用于非交互式会话。

### 4.5 重新连接 Codex

返回 Codex Desktop，重新连接原 Ubuntu 远程工作区。

**本次实际结果：Codex Desktop 恢复正常连接。**

## 5. 后续常用排查命令

### 查看客户端最终生效配置

~~~powershell
ssh -G ubuntu_local |
Select-String "^(hostname|user|identityfile|identitiesonly) "
~~~

### 查看认证详细日志

~~~powershell
ssh -vvv -o BatchMode=yes ubuntu_local "whoami"
~~~

重点检查日志中的 `Offering public key`、`Server accepts key`、`Authenticated to` 等行。

### 检查 Ubuntu 虚拟机 IP

~~~bash
ip -4 addr
~~~

VMware 的网络模式或 DHCP 地址变化后，客户端配置中的 `HostName` 可能需要更新。

### 检查远端公钥文件权限

~~~bash
ls -ld ~/.ssh
ls -l ~/.ssh/authorized_keys
~~~

一般推荐 SSH 目录权限 `700`，授权文件权限 `600`。

## 6. 经验总结

1. **普通 SSH 能登录 ≠ 自动化工具能够登录。** 先用 `BatchMode=yes` 排查非交互式认证。
2. 区分网络故障、SSH 认证失败、远程目录权限与 Codex 远端启动失败，不要一开始就重装应用或虚拟机。
3. GitHub、云服务器、本地虚拟机使用相互独立的 SSH 密钥，便于单独管理和撤销授权。
4. 公钥可加入服务端授权文件，**私钥绝不提交到 GitHub**。
5. 公开故障记录时，对真实 Linux 用户名、Windows 用户目录、SSH 别名、IP 和内部项目路径进行匿名化。
6. 修复了直接故障，不等于确定了“原来为何可用、后来为何失效”的历史诱因；应将事实与推测分开记录。

> 核心结论：当 Codex Desktop 报 `Permission denied (publickey,password)`、但 PowerShell 输入密码可正常 SSH 登录时，优先检查并修复 **非交互式 SSH 公钥认证**。
