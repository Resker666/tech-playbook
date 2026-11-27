# GitHub 默认分支保护：模板与批量管理

适用于个人名下 GitHub 仓库。模板来自 tech-playbook 已生效的 Protect main 规则（2026-11-27），仅将名称改为 Protect default branch，使用 ~DEFAULT_BRANCH 自动匹配 main/master/develop。

## 文件

- [protect-default-branch.json](./protect-default-branch.json)：可在 GitHub 网页导入，也可作为 API 请求体。
- [apply-rulesets.sh](./apply-rulesets.sh)：Bash 批量工具；默认 dry-run，不修改仓库。

## 规则行为

Active；Repository admin (actor_id=5, always bypass)；Restrict updates、Restrict deletions、Block force pushes。其他有写权限的身份不能更新默认分支；管理员仍可直接 push、强推、删除（受 GitHub 其他限制约束）。不强制 PR。若 AI 使用管理员本人凭据，它同样能绕过；真正隔离需独立身份。普通公开访问者原本就没有写权限。

## 1. 网页导入

仓库 Settings → Rulesets → New ruleset → Import a ruleset → 选择 JSON → 确认 Active、目标分支和豁免名单 → Create。

## 2. CLI 准备

Linux/macOS/WSL 或装有 gh 和 jq 的 Git Bash。Ubuntu 可用 sudo apt install gh jq；macOS 可用 brew install gh jq。

```bash
gh auth login --hostname github.com
gh auth status --hostname github.com
gh api user --jq .login
git clone https://github.com/Resker666/tech-playbook.git
cd tech-playbook/Git/github-rulesets
```

已有仓库可直接进入目录，不用再次 clone。请核对 CLI 登录的是目标仓库所有者账号。创建规则集要求管理权限；fine-grained PAT 需要目标仓库 Administration: write，且能读取仓库和分支。不要把 token 写进仓库、命令记录或脚本。

## 3. 先预览，再执行

```bash
# 仅预览一个
bash apply-rulesets.sh Resker666/YeShunguangPet

# 实际执行一个，并检查 protected=true
bash apply-rulesets.sh --apply Resker666/YeShunguangPet

# 预览全部符合条件的自有公开仓库
bash apply-rulesets.sh --all-public

# 确认预览后执行所选项目（推荐）
bash apply-rulesets.sh --apply Resker666/YeShunguangPet Resker666/codex-desktop-token-monitor

# 确认全部候选项目都需要统一规则时才批量创建
bash apply-rulesets.sh --apply --all-public

# 私有仓库：仅显式指定，先预览；套餐必须支持
bash apply-rulesets.sh --include-private Resker666/investment-strategy
```

脚本跳过非本人仓库、无管理员权限、fork、归档仓库、已保护分支及任何已有规则集的仓库，不覆盖、不删除既有规则；空仓库或权限错误会报 FAIL，不尝试盲目创建。读取权限不足时也不会写入。重复运行通常会跳过已配置项目。批量操作不是事务：个别项目失败不会回滚此前成功的项目。私有仓库须显式加 --include-private 并指定仓库；不应为使用保护规则而公开隐私项目。

## 4. 验证和回退

```bash
gh api repos/Resker666/YeShunguangPet/branches/main --jq .protected
gh api repos/Resker666/YeShunguangPet/rulesets --jq '.[] | {id,name,enforcement}'
```

在 Settings → Rulesets 点开新规则，检查目标和 bypass；protected=true 仅表示存在有效保护，不证明每条限制符合预期。若需回退，仅由管理员在网页禁用或删除本次新建的规则集，勿删除历史规则。配置前可保留原有规则的导出 JSON。

## 5. 安全工作流

AI 在 feature/docs 分支工作 → 提交 PR → 本人审核 → 合并默认分支。此模板允许管理员直接更新，不是强制人工审批；需要更严格的策略时另建规则，先在测试仓库验证。个人知识库、正式应用及重要记录优先，纯实验项目可按需选择。

## 参考

- https://docs.github.com/en/rest/repos/rules#create-a-repository-ruleset
- https://docs.github.com/en/github-cli/github-cli/authenticating-with-github-cli
- https://cli.github.com/manual/gh_api
