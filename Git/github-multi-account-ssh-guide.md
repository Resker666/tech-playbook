# GitHub 多账号 SSH 配置指南

> 适用场景：同一台电脑同时使用多个 GitHub 账号（如个人账号与工作账号）。
> 目标：让不同仓库使用各自指定的 SSH
> Key，避免账号串用、`Repository not found` 和
> `Permission denied (publickey)`。

## 1. 核心原理

如果所有仓库都使用：

``` bash
git@github.com:OWNER/REPOSITORY.git
```

SSH 可能使用默认密钥，导致认证到错误账号。

推荐方案是：

> **每个 GitHub 账号使用独立 SSH Key，并通过 SSH Host Alias 指定身份。**

例如：

``` text
github-personal -> 个人 SSH Key -> 个人 GitHub 账号
github-work     -> 工作 SSH Key -> 工作 GitHub 账号
```

## 2. 为不同账号生成 SSH Key

个人账号：

``` bash
ssh-keygen -t ed25519 -C "personal@example.com" -f ~/.ssh/id_ed25519_github_personal
```

工作账号：

``` bash
ssh-keygen -t ed25519 -C "work@example.com" -f ~/.ssh/id_ed25519_github_work
```

会分别生成私钥和公钥：

``` text
id_ed25519_github_personal
id_ed25519_github_personal.pub
id_ed25519_github_work
id_ed25519_github_work.pub
```

无 `.pub` 后缀的是私钥，必须妥善保管；`.pub` 是公钥，可添加到对应 GitHub
账号的 SSH Keys。

## 3. 配置 \~/.ssh/config

推荐配置：

``` sshconfig
Host github-personal
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github_personal
    IdentitiesOnly yes

Host github-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github_work
    IdentitiesOnly yes
```

`github-personal` 和 `github-work` 是本机自定义
Alias，真正连接的服务器仍是 `github.com`。

`IdentitiesOnly yes` 可以强制 SSH 只使用该 Host 指定的密钥，避免
ssh-agent 中多个 Key 导致身份串用。

## 4. 测试账号

个人账号：

``` bash
ssh -T git@github-personal
```

工作账号：

``` bash
ssh -T git@github-work
```

正常会看到：

``` text
Hi <username>! You've successfully authenticated, but GitHub does not provide shell access.
```

重点确认 `<username>` 是否是预期账号。

## 5. Clone 仓库

个人仓库：

``` bash
git clone git@github-personal:PERSONAL_USER/example.git
```

工作仓库：

``` bash
git clone git@github-work:WORK_ORG/example.git
```

关键是把普通的：

``` text
git@github.com:...
```

改为对应 Alias：

``` text
git@github-personal:...
git@github-work:...
```

## 6. 修改已经存在的仓库

查看当前 Remote：

``` bash
git remote -v
```

个人仓库可修改为：

``` bash
git remote set-url origin git@github-personal:PERSONAL_USER/example.git
```

工作仓库：

``` bash
git remote set-url origin git@github-work:WORK_ORG/example.git
```

再次确认：

``` bash
git remote -v
```

然后：

``` bash
git push
```

首次建立上游分支时：

``` bash
git push -u origin main
```

如果本地使用 `master`：

``` bash
git push -u origin master
```

## 7. Repository not found 排查

出现：

``` text
ERROR: Repository not found.
fatal: Could not read from remote repository.
```

不一定代表仓库真的不存在。

先检查：

``` bash
git remote -v
```

确认：

-   OWNER 是否正确
-   仓库名称是否正确
-   Host Alias 是否正确

再测试身份：

``` bash
ssh -T git@github-personal
```

如果显示的 GitHub 用户不是仓库所属账号，很可能就是 SSH 身份用错。

修改 Remote：

``` bash
git remote set-url origin git@github-personal:PERSONAL_USER/example.git
```

再 Push。

## 8. Permission denied (publickey) 排查

出现：

``` text
git@github.com: Permission denied (publickey).
```

检查 SSH 文件：

``` bash
ls -la ~/.ssh/
```

检查配置：

``` bash
cat ~/.ssh/config
```

测试：

``` bash
ssh -T git@github-personal
```

需要查看 SSH 实际尝试了哪个 Key：

``` bash
ssh -vT git@github-personal
```

重点关注输出中的：

``` text
Offering public key
```

## 9. SSH 身份与 Commit 身份不同

SSH Key 决定：

> **使用哪个 GitHub 账号访问远程仓库。**

而：

``` bash
git config user.name
git config user.email
```

决定：

> **Commit 记录中的作者身份。**

查看当前仓库：

``` bash
git config user.name
git config user.email
```

为当前仓库单独设置：

``` bash
git config user.name "Your Name"
git config user.email "your-email@example.com"
```

设置全局默认值：

``` bash
git config --global user.name "Your Name"
git config --global user.email "your-email@example.com"
```

多账号环境下，推荐按仓库配置 `user.name` / `user.email`，避免工作和个人
Commit 身份混用。

## 10. 推荐工作流

个人项目：

``` bash
git clone git@github-personal:PERSONAL_USER/example.git
cd example

git config user.name "Personal Name"
git config user.email "personal@example.com"

git add .
git commit -m "docs: update documentation"
git push
```

工作项目：

``` bash
git clone git@github-work:WORK_ORG/example.git
cd example

git config user.name "Work Name"
git config user.email "work@example.com"

git add .
git commit -m "fix: resolve issue"
git push
```

## 11. 常用命令速查

``` bash
# 查看 Remote
git remote -v

# 当前分支
git branch --show-current

# 当前 Commit 身份
git config user.name
git config user.email

# 测试个人 GitHub 身份
ssh -T git@github-personal

# 测试工作 GitHub 身份
ssh -T git@github-work

# SSH 详细调试
ssh -vT git@github-personal

# 查看 SSH 配置
cat ~/.ssh/config

# 查看 SSH 文件
ls -la ~/.ssh/
```

## 12. 安全注意事项

**绝对不要提交 SSH 私钥。**

不要将以下内容提交到 GitHub：

-   SSH 私钥
-   API Key
-   Access Token
-   Cookie
-   密码
-   `.env` 中的敏感变量
-   个人账户凭据

项目 `.gitignore` 可加入：

``` gitignore
.env
.env.*
*.pem
*.key
```

SSH Key 最好始终保存在 `~/.ssh/`，不要复制进项目目录。

## 13. 排查思路总结

多 GitHub 账号出现 Push / Clone 问题时，优先检查三层：

``` text
Remote URL
    ↓
SSH Host Alias
    ↓
IdentityFile
    ↓
实际认证的 GitHub Account
```

三个关键问题：

1.  `git remote -v` 使用了哪个 Host Alias？
2.  该 Alias 在 `~/.ssh/config` 指向哪个 `IdentityFile`？
3.  `ssh -T git@<alias>` 最终显示哪个 GitHub 用户？

只要这三层对应正确，多 GitHub 账号通常就不会再发生 SSH 身份串用。
