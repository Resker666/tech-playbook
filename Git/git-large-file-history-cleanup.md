# Git 大文件误提交后的历史清理实战

> 适用场景：大文件虽然已经从当前分支删除，但仍残留在 Git 历史中，导致 `git clone` / `git fetch` 下载体积过大，网络较差时容易卡住。

## 一、问题背景

在 `minimal-sleep` 项目中，曾误提交两个 WAV 文件：

```text
ios/MinimalSleep/Resources/rain-01.wav
ios/MinimalSleep/Resources/rain-04.wav
```

两个文件各约 52.6 MB，合计约 100 MB。

后来虽然已经在当前 `main` 分支中删除了它们，但 Git 的历史提交仍然保存对应 blob，因此：

```text
删除工作区文件 ≠ 删除 Git 历史中的文件
```

这会导致新的 `git clone` 仍可能下载这些历史大文件。

---

## 二、问题现象

仓库在网络较差时出现：

- `git clone` 长时间卡住
- 浅克隆也可能在下载阶段卡住
- 仓库 `.git` 目录明显偏大
- 当前目录中虽然已经没有 WAV，但历史 blob 仍可达

核心原因不是 GitHub 本身异常，而是仓库历史里保留了大文件。

---

## 三、排查方法

### 1. 查看仓库对象体积

```bash
git count-objects -vH
```

### 2. 查找历史中的大对象

```bash
git verify-pack -v .git/objects/pack/*.idx | sort -k3 -n | tail -20
```

### 3. 查某个文件是否仍存在于历史

```bash
git rev-list --objects --all | grep 'rain-01.wav'
git rev-list --objects --all | grep 'rain-04.wav'
```

如果能看到输出，说明文件即使已经从当前版本删除，仍存在于 Git 历史中。

---

# 四、清理思路

整体流程：

```text
确认工作区干净
    ↓
备份仓库
    ↓
创建临时 mirror 仓库
    ↓
使用 git-filter-repo 精确删除历史文件
    ↓
验证 blob / 路径消失
    ↓
确认受影响分支
    ↓
dry-run force push
    ↓
正式 force push
    ↓
重新 clone 验证
    ↓
旧 clone 停用
```

关键原则：

> 不直接在日常开发仓库中重写历史。

---

# 五、实际操作

## 1. 确认工作区干净

```bash
cd /Users/resker/develop/github/minimal-sleep
git status
```

期望：

```text
nothing to commit, working tree clean
```

如果还有未提交修改，应先保存、提交或导出 patch。

---

## 2. 创建备份

创建备份目录：

```bash
mkdir -p ~/git-backup/minimal-sleep
```

同步引用：

```bash
git fetch --all --tags --prune
```

创建 bundle：

```bash
git bundle create \
~/git-backup/minimal-sleep/minimal-sleep-before-clean.bundle \
--all
```

验证：

```bash
git bundle verify \
~/git-backup/minimal-sleep/minimal-sleep-before-clean.bundle
```

出现：

```text
...bundle is okay
```

说明 bundle 备份有效。

再创建 mirror 备份：

```bash
git clone --mirror --no-local \
/Users/resker/develop/github/minimal-sleep \
~/git-backup/minimal-sleep/minimal-sleep-before-clean.git
```

检查：

```bash
git -C ~/git-backup/minimal-sleep/minimal-sleep-before-clean.git fsck --full
```

---

## 3. 创建一次性清理仓库

```bash
git clone --mirror --no-local \
~/git-backup/minimal-sleep/minimal-sleep-before-clean.git \
/tmp/minimal-sleep-clean.git
```

检查：

```bash
git -C /tmp/minimal-sleep-clean.git fsck --full
```

之后所有历史重写操作都只针对：

```text
/tmp/minimal-sleep-clean.git
```

---

## 4. 安装 git-filter-repo

```bash
brew install git-filter-repo
```

验证：

```bash
git filter-repo --version
```

---

## 5. 精确删除两个 WAV 的全部历史

```bash
git -C /tmp/minimal-sleep-clean.git filter-repo \
  --path ios/MinimalSleep/Resources/rain-01.wav \
  --path ios/MinimalSleep/Resources/rain-04.wav \
  --invert-paths
```

这里使用精确路径，而不是：

```bash
--strip-blobs-bigger-than
```

原因是只删除明确目标文件，避免误删仓库中的其他大文件。

`git-filter-repo` 执行后会自动移除 `origin` remote，这是保护措施，避免误推重写后的历史。

---

# 六、验证清理结果

## 1. 验证文件路径已消失

```bash
git -C /tmp/minimal-sleep-clean.git rev-list --objects --all | \
grep 'ios/MinimalSleep/Resources/rain-01.wav'

git -C /tmp/minimal-sleep-clean.git rev-list --objects --all | \
grep 'ios/MinimalSleep/Resources/rain-04.wav'
```

正确结果：

```text
没有任何输出
```

## 2. 验证旧 blob 已消失

旧 blob：

```text
bb004c5d39fbd04dfe355e9d4a83814b654b116b
a527ff65a2bcda7b0f3bafea9afcd29253341762
```

检查：

```bash
git -C /tmp/minimal-sleep-clean.git rev-list --objects --all | \
grep bb004c5d39fbd04dfe355e9d4a83814b654b116b

git -C /tmp/minimal-sleep-clean.git rev-list --objects --all | \
grep a527ff65a2bcda7b0f3bafea9afcd29253341762
```

也应没有输出。

## 3. 检查仓库完整性

```bash
git -C /tmp/minimal-sleep-clean.git fsck --full
```

## 4. 查看体积

```bash
git -C /tmp/minimal-sleep-clean.git count-objects -vH
```

本次清理后：

```text
size-pack: 21.87 MiB
```

相比原来的 100 MB 级历史数据明显下降。

---

# 七、确认哪些分支被重写

```bash
cat /tmp/minimal-sleep-clean.git/filter-repo/changed-refs
```

本次结果：

```text
refs/heads/codex/ios-ci-phase-one
refs/heads/main
```

说明只有：

```text
main
codex/ios-ci-phase-one
```

需要更新远端。

其他分支与 tag 没有受到影响。

---

# 八、推送前确认 GitHub 没发生新提交

重新添加远端：

```bash
git -C /tmp/minimal-sleep-clean.git remote add publish \
git@github.com:Resker666/minimal-sleep.git
```

检查远端两个分支：

```bash
git -C /tmp/minimal-sleep-clean.git ls-remote --heads publish \
main codex/ios-ci-phase-one
```

确认它们仍然是开始清理前记录的旧 SHA。

这样可以避免覆盖别人或其他设备在清理期间产生的新提交。

---

# 九、先 dry-run

```bash
git -C /tmp/minimal-sleep-clean.git push \
  --dry-run \
  --atomic \
  --force-with-lease=refs/heads/main:7f64928a5c97cf2bc01e46b9779c21c5b8d64a7e \
  --force-with-lease=refs/heads/codex/ios-ci-phase-one:d5db78ed6ffb4b8ea352b5758158038622486149 \
  publish \
  refs/heads/main:refs/heads/main \
  refs/heads/codex/ios-ci-phase-one:refs/heads/codex/ios-ci-phase-one
```

正常时会看到：

```text
(forced update)
```

但不会真正修改 GitHub。

---

# 十、正式更新 GitHub 历史

确认 dry-run 正常后，删除 `--dry-run`：

```bash
git -C /tmp/minimal-sleep-clean.git push \
  --atomic \
  --force-with-lease=refs/heads/main:7f64928a5c97cf2bc01e46b9779c21c5b8d64a7e \
  --force-with-lease=refs/heads/codex/ios-ci-phase-one:d5db78ed6ffb4b8ea352b5758158038622486149 \
  publish \
  refs/heads/main:refs/heads/main \
  refs/heads/codex/ios-ci-phase-one:refs/heads/codex/ios-ci-phase-one
```

本次两个分支都成功：

```text
codex/ios-ci-phase-one -> codex/ios-ci-phase-one (forced update)
main                   -> main                   (forced update)
```

---

# 十一、从 GitHub 全新 clone 验证

```bash
rm -rf /tmp/minimal-sleep-verify

git clone \
git@github.com:Resker666/minimal-sleep.git \
/tmp/minimal-sleep-verify
```

再次检查两个文件路径和两个 blob：

```bash
git -C /tmp/minimal-sleep-verify rev-list --objects --all | \
grep 'ios/MinimalSleep/Resources/rain-01.wav'

git -C /tmp/minimal-sleep-verify rev-list --objects --all | \
grep 'ios/MinimalSleep/Resources/rain-04.wav'
```

以及旧 blob ID。

全部都没有输出。

完整性检查：

```bash
git -C /tmp/minimal-sleep-verify fsck --full
```

查看 `.git` 大小：

```bash
du -sh /tmp/minimal-sleep-verify/.git
```

最终约：

```text
22M
```

说明 GitHub 远端历史清理已真正生效。

---

# 十二、旧本地仓库不要继续使用

历史重写后，旧 clone 仍然保存旧提交和大 blob。

不建议直接在旧 clone 中：

```bash
git pull
git push
```

否则有机会再次把旧历史带回来。

正确做法：

```bash
cd /Users/resker/develop/github

mv minimal-sleep minimal-sleep-old-delete-10-5

git clone git@github.com:Resker666/minimal-sleep.git
```

今后继续使用新的：

```text
minimal-sleep
```

旧目录保留几天作为保险，确认 Xcode、Codex、分支与构建都正常后再删除。

---

# 十三、为什么 GitHub 没出现一条“清理历史”的新 commit？

因为 `git filter-repo` 不是创建一个新的提交，而是：

```text
重写已有历史
```

例如原来：

```text
A -> B(加入大文件) -> C -> D(删除大文件)
```

清理后变成：

```text
A -> B' -> C' -> D'
```

由于 commit 内容或父节点发生变化，后续 commit SHA 都会重新计算。

因此 GitHub 上看到的是：

- 原来的提交信息大多还在
- commit SHA 发生变化
- 不会额外出现一条 `cleanup history` 提交

---

# 十四、后续避免再次发生

## 1. 不要提交生成出来的大 WAV

项目已经有较小的 OGG 源文件以及生成脚本。

建议 Git 保存：

```text
rain-01.ogg
rain-04.ogg
tools/prepare_ios_audio.py
```

Git 不保存：

```text
rain-01.wav
rain-04.wav
临时转码 WAV
```

构建时：

```text
OGG
 ↓
FFmpeg / prepare_ios_audio.py
 ↓
WAV
 ↓
Xcode Build
```

## 2. 使用 `.gitignore`

例如：

```gitignore
/ios/MinimalSleep/Resources/rain-01.wav
/ios/MinimalSleep/Resources/rain-04.wav
/ios/MinimalSleep/Resources/.rain-*.transcoding.wav
```

## 3. 提交前检查

```bash
git status --short
```

或者：

```bash
git diff --cached --stat
```

看到异常大的二进制文件时先停下来检查。

---

# 十五、这次排障最重要的几个知识点

### 1. 删除文件不等于删除 Git 历史

```text
git rm + commit
```

只表示最新版本里没有文件。

历史里的 blob 仍然存在。

### 2. clone 下载的是历史对象，不只是当前目录

所以当前版本看不到大文件，不代表 clone 不会下载它。

### 3. 重写历史要先备份

推荐至少：

```text
bundle
+
mirror clone
```

### 4. 重写历史不要直接在日常工作仓库操作

使用一次性的：

```text
/tmp/...clean.git
```

### 5. force push 尽量使用

```bash
--force-with-lease
```

而不是：

```bash
--force
```

### 6. 推送前先 dry-run

```bash
--dry-run
```

可以降低误操作风险。

### 7. 历史重写后，旧 clone 应重新 clone

否则旧历史可能再次污染远端。

---

# 最终结果

清理前：

```text
Git 历史残留约 100 MB WAV
网络差时 clone 容易卡住
```

清理后：

```text
两个 WAV 路径已从全部可达历史中消失
两个旧 blob 已不可达
GitHub 两个受影响分支已重写
新 clone 正常
.git ≈ 22 MB
仓库完整性检查正常
```

问题最终解决。
