# 服务器生成ssh key用来拉去代码



**在云服务器生成 SSH key → 把公钥加到 GitHub/Gitee/GitLab → 测试连接 → 用 SSH 地址拉取/推送仓库。**

下面以 **GitHub** 为例。

## 1. 在云服务器生成 SSH 密钥

进入服务器终端：

```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
```

一路回车即可。

如果系统不支持 `ed25519`，用：

```bash
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

默认会生成：

```bash
~/.ssh/id_ed25519
~/.ssh/id_ed25519.pub
```

其中：

```bash
id_ed25519      # 私钥，不能泄露
id_ed25519.pub  # 公钥，可以放到 GitHub/Gitee/GitLab
```

## 2. 查看公钥内容

```bash
cat ~/.ssh/id_ed25519.pub
```

复制输出内容，类似：

```bash
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIxxxxxx your_email@example.com
```

## 3. 把公钥添加到 GitHub

GitHub 页面：

```text
头像 → Settings → SSH and GPG keys → New SSH key
```

填写：

```text
Title: 云服务器
Key: 粘贴 id_ed25519.pub 的内容
```

然后保存。

## 4. 测试 SSH 是否成功

```bash
ssh -T git@github.com
```

第一次会提示：

```text
Are you sure you want to continue connecting?
```

输入：

```bash
yes
```

成功的话会看到类似：

```text
Hi username! You've successfully authenticated...
```

## 5. 拉取仓库

注意要用 **SSH 地址**，不是 HTTPS 地址。

SSH 地址一般是：

```bash
git@github.com:用户名/仓库名.git
```

例如：

```bash
git clone git@github.com:xxx/xxx.git
```

## 6. 如果已有仓库，修改 remote 地址

进入你的仓库目录：

```bash
cd your_repo
```

查看当前 remote：

```bash
git remote -v
```

如果现在是 HTTPS：

```bash
https://github.com/xxx/xxx.git
```

改成 SSH：

```bash
git remote set-url origin git@github.com:xxx/xxx.git
```

再确认：

```bash
git remote -v
```

## 7. 推送代码

```bash
git status
git add .
git commit -m "your message"
git push origin 分支名
```

比如：

```bash
git push origin main
```

或者：

```bash
git push origin master
```

如果你当前在某个分支，可以看：

```bash
git branch
```

## 常见问题

如果 `ssh -T git@github.com` 超时：

```text
ssh: connect to host github.com port 22: Connection timed out
```

可以改用 GitHub 的 443 端口，在服务器编辑：

```bash
vim ~/.ssh/config
```

加入：

```bash
Host github.com
    Hostname ssh.github.com
    Port 443
    User git
```

然后再测试：

```bash
ssh -T git@github.com
```

最简流程就是：

```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
cat ~/.ssh/id_ed25519.pub
ssh -T git@github.com
git clone git@github.com:用户名/仓库名.git
```
