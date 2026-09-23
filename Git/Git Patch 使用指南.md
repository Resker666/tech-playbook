# git patch

在 `git status` 中查看到的差异，通常分为“尚未暂存（Changes not staged for commit）”和“已暂存（Changes to be committed）”两种状态。如果你想将特定文件的差异导出为一个 patch 包，可以根据文件所处的状态选择以下命令：

### 1. 如果文件在“尚未暂存”的修改中

如果你想导出某个**尚未执行 `git add`** 的特定文件，可以使用以下命令：

```bash
git diff <文件路径> > my_changes.patch
```

例如，你想导出 `src/main.js` 这个文件的修改：
`git diff src/main.js > main_fix.patch`

### 2. 如果文件在“已暂存”的修改中

如果你已经对某些文件执行了 `git add`，它们处于暂存区，导出特定文件的命令需要加上 `--staged`（或 `--cached`）参数：

```bash
git diff --staged <文件路径> > my_staged_changes.patch
```

例如，导出已暂存的 `utils/helper.py`：
`git diff --staged utils/helper.py > helper_update.patch`

### 3. 如果你想一次性导出多个特定文件

直接在命令后面依次加上文件路径即可：

```bash
git diff <文件路径1> <文件路径2> > multiple_files.patch
```

例如：`git diff src/main.js README.md > combined.patch`

### 💡 补充小技巧

- **导出所有未提交的特定文件修改**：如果你想把某个文件所有未提交的修改（无论是已暂存还是未暂存）一次性打出来，可以使用 `HEAD` 来对比：
  `git diff HEAD <文件路径> > all_changes.patch`
- **如何应用这个 patch 包**：生成好 `.patch` 文件后，如果需要在其他仓库或分支应用它，可以使用以下命令：
  `git apply my_changes.patch`

你可以根据 `git status` 中文件的具体状态，直接复制上面的命令替换成你的文件名来操作。如果有其他疑问，随时告诉我！