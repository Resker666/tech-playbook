# Git Clone 在弱网环境下卡住的排查与解决

## 问题背景

在 Windows Git Bash 中克隆 GitHub 仓库：

```bash
git clone git@github.com:Resker666/minimal-sleep.git
```

出现：

```text
Cloning into 'minimal-sleep'...
ssh: connect to host github.com port 22: Connection timed out
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists.
```

最开始容易怀疑：

* SSH Key 配置错误
* GitHub 仓库不存在
* GitHub 权限异常
* SSH 22 端口被网络屏蔽

但最终实际问题是：

> 当前网络质量较差，而仓库中存在较大的二进制资源，完整 Clone 需要传输较多 Git 对象，网络不稳定导致 Clone 过程卡住。

---

## 1. 检查 SSH 配置

本机 SSH 配置：

```text
C:\Users\fade\.ssh\
```

包含：

```text
config
id_ed25519_resker666
id_ed25519_resker666.pub
known_hosts
```

`~/.ssh/config`：

```sshconfig
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_resker666
    IdentitiesOnly yes
```

配置本身没有明显问题。

需要注意：

如果 SSH Key 或 GitHub 权限存在问题，一般更容易看到：

```text
Permission denied (publickey).
```

而：

```text
connect to host github.com port 22: Connection timed out
```

说明问题发生得更早：

> TCP / SSH 网络连接阶段就已经出现异常。

---

## 2. 测试 GitHub SSH 端口

Windows PowerShell：

```powershell
Test-NetConnection github.com -Port 22
```

测试结果：

```text
ComputerName     : github.com
RemotePort       : 22
TcpTestSucceeded : True
```

继续测试 GitHub 提供的 SSH over 443：

```powershell
Test-NetConnection ssh.github.com -Port 443
```

结果：

```text
ComputerName     : ssh.github.com
RemotePort       : 443
TcpTestSucceeded : True
```

因此可以排除：

* 22 端口被永久封锁
* 443 端口不可用
* GitHub 完全无法访问

说明之前的 SSH timeout 很可能只是：

> 临时网络抖动或链路不稳定。

---

## 3. 使用 `git ls-remote` 判断仓库和权限

执行：

```bash
git ls-remote git@github.com:Resker666/minimal-sleep.git
```

命令能够正常返回远程 refs。

这一步非常重要。

`git ls-remote` 成功基本可以证明：

* GitHub 仓库存在
* 仓库地址正确
* SSH Key 可以正常认证
* 当前账号拥有仓库访问权限
* Git 可以连接 GitHub

因此：

> 问题已经不应该继续围绕 SSH Key 和仓库权限排查。

---

## 4. 测试浅克隆

为了减少 Git 历史下载量，尝试：

```bash
git clone --depth=1 git@github.com:Resker666/minimal-sleep.git
```

仍然无法顺利完成。

`--depth=1` 表示只下载最近一层 Commit 历史。

例如完整仓库：

```text
commit D  ← 最新
↑
commit C
↑
commit B
↑
commit A
```

普通 Clone：

```bash
git clone <repo>
```

通常会获取完整历史。

而：

```bash
git clone --depth=1 <repo>
```

主要获取：

```text
commit D
```

因此可以显著减少历史对象的下载量。

但要注意：

> 当前最新 Commit 中正在使用的大文件仍然需要下载。

所以 shallow clone 并不能解决“当前版本本身包含大文件”的问题。

---

## 5. 排除 SSH 协议问题

继续尝试 HTTPS：

```bash
git clone --depth=1 https://github.com/Resker666/minimal-sleep.git
```

输出：

```text
Cloning into 'minimal-sleep'...

remote: Enumerating objects: 152, done.
remote: Counting objects: 100% (152/152), done.
remote: Compressing objects: 100% (134/134), done.

Receiving objects: 16% (25/152), 6.81 MiB | 2.35 MiB/s
```

然后同样出现长时间卡顿。

这是一个非常关键的现象。

SSH：

```text
git@github.com
```

卡。

HTTPS：

```text
https://github.com
```

也卡。

因此可以进一步判断：

> 问题不是单纯的 SSH 22 端口问题。

更应该检查：

* 网络稳定性
* 仓库大小
* 大型 Git Blob
* 二进制资源

---

## 6. 检查仓库中的大文件

进一步检查仓库后发现：

```text
ios/MinimalSleep/Resources/rain-01.wav
约 52.6 MB

ios/MinimalSleep/Resources/rain-04.wav
约 52.6 MB
```

两个 WAV 文件合计超过：

```text
100 MB
```

与此同时 Android 中对应压缩音频只有约：

```text
rain-01.ogg    ~4 MB
rain-04.ogg    ~4 MB
```

因此仓库最新版本本身包含两个比较大的二进制 Git Blob。

对于稳定网络而言，单个 50 MB 文件并不算特别巨大。

但是：

> Git + 大型二进制文件 + 不稳定网络

组合在一起，就很容易暴露网络传输问题。

---

## 7. 为什么 `git ls-remote` 正常，而 Clone 失败？

因为两者的数据量完全不同。

### `git ls-remote`

```bash
git ls-remote <repo>
```

主要获取：

```text
HEAD
refs/heads/main
refs/tags/...
```

数据量非常小。

因此即使网络质量一般，也很容易成功。

---

### `git clone`

Clone 需要传输：

* Commit
* Tree
* Blob
* Packfile
* 当前源码
* 二进制资源

例如这次仓库包含两个约 50 MB WAV 文件。

网络只要在持续传输期间发生明显抖动，就可能出现：

* 卡住
* timeout
* connection reset
* early EOF
* unexpected disconnect

所以：

```text
ls-remote 成功
```

并不代表：

```text
大规模 Git 数据传输一定稳定
```

---

## 8. 最终临时解决方法

当前网络较差的情况下，使用：

```bash
git clone --depth=1 https://github.com/Resker666/minimal-sleep.git
```

最终成功完成 Clone。

这样可以避免拉取整个 Git 历史，大幅降低首次 Clone 的数据量。

对于：

* 临时开发环境
* 新电脑
* 网络较差
* 暂时不需要完整历史

非常实用。

---

## 9. `--depth=1` 的限制

浅克隆以后：

```bash
git status
git add
git commit
git push
git pull
```

正常开发基本不受影响。

但是：

```bash
git log
```

只能看到有限的 Commit 历史。

如果以后网络恢复，希望获取完整历史：

```bash
git fetch --unshallow
```

即可将 shallow clone 转换为完整仓库。

---

## 10. 更长期的优化

这次虽然通过：

```bash
--depth=1
```

解决了开发阻塞，但仓库本身仍值得优化。

### 方案一：避免提交生成型大文件

如果 WAV 可以通过源音频生成：

```text
小体积源音频
    ↓
prepare script
    ↓
生成 WAV
```

更推荐：

```text
Git
├── 压缩后的源音频
├── prepare_ios_audio.py
└── 不提交生成后的大型 WAV
```

并通过 `.gitignore` 忽略生成文件。

---

### 方案二：使用更适合移动端的音频格式

如果应用没有必须使用 WAV，可以考虑：

* AAC
* M4A
* 压缩后的其他适用格式

避免几十 MB 的无压缩 WAV 长期存在于源码仓库中。

---

### 方案三：Git LFS

如果大型资源必须进行版本管理，可以考虑：

```text
Git LFS
```

Git 仓库保存 Pointer，而实际大文件交由 LFS 管理。

适用于：

* 音频
* 视频
* 模型
* PSD
* 大型二进制资源

---

## 11. 推荐排查流程

以后再遇到：

```text
git clone 卡住
```

可以按照下面顺序排查。

### Step 1：检查基础网络

```bash
ping github.com
```

或者 Windows：

```powershell
Test-NetConnection github.com -Port 443
```

SSH：

```powershell
Test-NetConnection github.com -Port 22
```

---

### Step 2：测试 SSH Authentication

```bash
ssh -T git@github.com
```

---

### Step 3：测试仓库是否可访问

```bash
git ls-remote <repo>
```

如果成功：

```text
仓库存在
+
权限基本正常
+
认证基本正常
```

---

### Step 4：测试 shallow clone

```bash
git clone --depth=1 <repo>
```

---

### Step 5：切换 SSH / HTTPS

SSH：

```bash
git clone git@github.com:user/repo.git
```

HTTPS：

```bash
git clone https://github.com/user/repo.git
```

如果两者都卡：

> 不要继续只排查 SSH。

---

### Step 6：检查仓库大型对象

本地已有仓库时：

```bash
git count-objects -vH
```

查看 Pack 大小。

进一步查看大型 Git 对象：

```bash
git verify-pack -v .git/objects/pack/*.idx |
sort -k3 -n |
tail -20
```

如果发现几十 MB 甚至上百 MB Blob，应检查对应文件。

---

## 12. 本次问题判断链

整个排查过程可以简化成：

```text
git clone SSH timeout
        ↓
怀疑 SSH / Key
        ↓
测试 22 / 443
        ↓
端口正常
        ↓
git ls-remote 成功
        ↓
权限、仓库、SSH Key 正常
        ↓
SSH Clone 卡住
        ↓
HTTPS Clone 同样卡住
        ↓
排除单纯 SSH 问题
        ↓
发现仓库存在约 50 MB × 2 WAV
        ↓
网络本身又不稳定
        ↓
大文件持续传输放大网络问题
        ↓
使用 --depth=1 减少历史下载量
        ↓
恢复正常开发
```

---

## 13. 核心经验

### 经验 1

看到：

```text
Could not read from remote repository
```

不要只看最后一行。

应该优先查看真正的首个错误。

例如：

```text
ssh: connect to host github.com port 22: Connection timed out
```

和：

```text
Permission denied (publickey)
```

属于完全不同的问题。

---

### 经验 2

```bash
git ls-remote
```

是一个非常好用的仓库连接诊断命令。

如果：

```bash
git ls-remote <repo>
```

成功，而 Clone 失败：

优先考虑：

* 数据传输
* 网络质量
* 仓库体积
* 大型 Blob

而不是继续折腾 SSH Key。

---

### 经验 3

SSH 和 HTTPS 都卡：

> 大概率就不能再简单归因于 SSH 配置。

---

### 经验 4

大型二进制文件不会必然导致 Git Clone 失败。

但：

```text
大型 Blob + 差网络
```

很容易让问题暴露。

---

### 经验 5

弱网环境下，可以优先尝试：

```bash
git clone --depth=1 <repo>
```

如果后续需要完整历史：

```bash
git fetch --unshallow
```

---

## Quick Reference

```bash
# 测试 SSH
ssh -T git@github.com

# 查看远程 refs / 判断仓库是否可访问
git ls-remote git@github.com:user/repo.git

# 弱网环境浅克隆
git clone --depth=1 https://github.com/user/repo.git

# 获取完整历史
git fetch --unshallow

# 查看仓库对象大小
git count-objects -vH

# 查看最大的 Git 对象
git verify-pack -v .git/objects/pack/*.idx |
sort -k3 -n |
tail -20
```

## 总结

本次问题并不是仓库损坏，也不是 SSH Key 配置错误。

真正的问题是：

```text
网络质量较差
+
仓库存在较大的二进制资源
+
完整 Git Clone 需要持续传输较多数据
```

大型 WAV 文件放大了弱网环境下的 Git 数据传输问题。

最终通过：

```bash
git clone --depth=1 ...
```

减少需要获取的 Git 历史数据量，使项目能够重新正常拉取并继续开发。

长期则应该考虑控制 Git 仓库中的大型二进制资源，必要时使用压缩格式、生成脚本或 Git LFS。
