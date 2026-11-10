# Git `checkout` 与 `switch`：区别及使用场景

> 适用场景：日常分支管理、从发布分支创建开发分支，以及跨版本迁移修改。

## 1. 核心结论

在**创建并切换到新分支**这一场景下，下面两条命令效果相同：

```bash
git checkout -b feature/example-task origin/main
git switch -c feature/example-task origin/main
```

两者都会以 `origin/main` 为起点创建本地分支 `feature/example-task`，并切换到该分支。已有同名本地分支时，默认都会失败，而不是覆盖。

**日常已习惯 `git checkout -b`，可以继续使用，不必为了新语法而改变习惯。**

## 2. 为什么又有 `switch`？

早期 `git checkout` 同时承担**分支切换**和**文件恢复**两类操作，容易混淆。Git 2.23 引入了两个更专一的命令：

- `git switch`：切换分支、创建并切换分支。
- `git restore`：恢复工作区或暂存区的文件内容。

`git checkout` 仍然可用，并没有被废弃；新命令主要是让意图更明确。

## 3. 常用命令对照

| 目的 | 传统写法 | 新写法 |
| --- | --- | --- |
| 切换到已有分支 | `git checkout dev` | `git switch dev` |
| 创建并切换新分支 | `git checkout -b feature/test` | `git switch -c feature/test` |
| 基于远程分支创建本地分支 | `git checkout -b feature/demo origin/main` | `git switch -c feature/demo origin/main` |
| 切换到上一个分支 | `git checkout -` | `git switch -` |
| 检出某个 commit（分离 HEAD） | `git checkout abc1234` | `git switch --detach abc1234` |
| 丢弃某文件的**未暂存**修改 | `git checkout -- file.c` | `git restore file.c` |
| 从特定提交恢复文件 | `git checkout abc1234 -- file.c` | `git restore --source=abc1234 -- file.c` |

**注意**：`git restore file.c` 和 `git checkout -- file.c` 通常都会用**暂存区（index）中的内容**覆盖工作区文件，并不是无条件恢复到 `HEAD`。它们可能丢失未暂存的修改，执行前先看 `git diff -- file.c`。

另外，`git switch` 不直接支持像 `git checkout -- file.c` 这样的文件恢复操作。

## 4. 实际差异

### 4.1 语义与安全性

`checkout` 功能广：既能切换分支，也能恢复文件，还能直接检出某个提交。`switch` 专门处理分支切换，意图更清晰。

```bash
# 检出某个 commit，进入 detached HEAD 状态
git checkout abc1234

# switch 需要显式指出 detached 模式
git switch --detach abc1234
```

### 4.2 对未提交修改的处理

**两者都不会默认替你 stash、提交或丢弃未提交改动。** 如果切换分支会覆盖本地修改，通常会拒绝切换；如果不会冲突，未提交修改有可能跟随切换到目标分支。

因此切分支前先检查：

```bash
git status --short
```

如果需要隔离当前工作，再使用 `git stash` 或先提交到临时分支。

### 4.3 版本兼容

`git switch` 从 Git 2.23 开始提供；较旧的 Git 环境可能只有 `git checkout`。可以用 `git --version` 查看版本。

## 5. 实例：将未提交改动迁移到新分支

以下示例使用虚构的目录与分支名称，两种新建分支写法二选一即可：

```bash
# 先保存指定路径的未提交修改（包含未跟踪文件，但不包含被忽略的文件）
git stash push -u -m "wip: migrate example task" -- \
  src/ \
  scripts/build.sh

# 更新远程跟踪分支
git fetch origin

# 使用熟悉的 checkout 写法，从目标分支创建并切换开发分支
git checkout -b feature/example-task origin/main

# 将保存的修改应用到新分支；保留 stash 作为备份
git stash apply 'stash@{0}'

# 检查是否有冲突
git status
git diff --name-only --diff-filter=U
```

或者把上述 `checkout -b` 换成：

```bash
git switch -c feature/example-task origin/main
```

两者不改变 stash 恢复的逻辑。**冲突通常会在 `stash apply` 时暴露，`stash` 本身不是“暂存冲突文件”。**

注意：

1. `stash` 只保存未提交的修改，不包含原分支已提交的 commit；已提交的功能可能需要 `git cherry-pick` 等方式迁移。
2. 上述 stash 只覆盖列出的路径，其他工作区修改可能仍在，并可能影响切分支。
3. `stash@{0}` 是位置编号；若期间新增 stash，编号会改变。应用前用 `git stash list` 确认。
4. `git stash apply` 不会自动删除 stash。确认迁移成功、修改已提交后，再核对目标条目并考虑 `git stash drop`。

## 6. 常见误区

- **误区：`git branch -b feature/test` 用于创建并切换分支。** 正确写法是 `git checkout -b feature/test` 或 `git switch -c feature/test`；`git branch feature/test` 只创建、不切换。
- **误区：`switch` 比 `checkout` 性能更好。** 对这里的常见分支操作，没有必要据此选择命令。
- **误区：切换分支会自动保护所有修改。** 两者都可能携带未提交修改，也可能因覆盖风险而拒绝切换，应先检查 `git status`。
- **误区：`git checkout -- file.c` 只切换分支。** 它实际会覆盖文件的未暂存修改，需谨慎。

## 7. 推荐习惯

对于日常开发，推荐统一一套顺手的写法即可：

```bash
git fetch origin
git checkout -b feature/my-work origin/main
git branch -vv
git status
```

如果你希望命令语义更明确，可以逐步切换为 `git switch` / `git restore`，但**没有必要强制替换已经熟悉且正确的 `checkout` 用法**。

---

**建议归档**：放在 `tech-playbook` 仓库的 Git 笔记目录，例如 `git/checkout-vs-switch.md`（具体目录以仓库现有结构为准）。
