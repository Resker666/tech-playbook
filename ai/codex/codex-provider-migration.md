# Codex 账号切换与本地历史会话迁移实录

- **记录日期**：2026-11-27
- **适用环境**：Windows VS Code → Remote SSH → Ubuntu → Codex 插件 / CLI
- **迁移方向**：公司 SUB API Key → 个人 ChatGPT Plus
- **迁移状态**：单条迁移及历史显示已验证成功；批量迁移大部分成功，最终成功数量尚未记录。

> 本文整理自实际排查和迁移过程，不是 Codex 官方迁移指南。脚本涉及本地 JSONL 和 SQLite 数据，执行前必须备份并停止 Codex 后台进程。本文不包含 API Key、Token、公司服务地址和内部项目路径。使用个人账号继续公司历史会话，应先确认公司允许将相关上下文发送给官方服务。

## 1. 背景与目标

原来通过 VS Code Remote SSH 连接 Ubuntu，在远程环境中运行 Codex，并使用公司的 SUB API 中转服务。由于共享账号使用人数较多、部分模型受到限制，准备切换为自己的 ChatGPT Plus 账号。

希望达到以下效果：

- 使用个人 Plus 的 Codex 额度及官方服务。
- 保留之前的聊天记录、会话 ID、项目路径和聊天正文。
- 不修改项目代码，不覆盖个人账号认证信息。
- 将来仍有机会切回公司账号。

## 2. 问题现象与根因

### 2.1 原有配置

公司的配置采用自定义 provider，关键结构如下（已脱敏，非完整配置）：

```toml
model_provider = "OpenAI"
# 其他模型、推理等级等配置省略

[model_providers.OpenAI]
name = "OpenAI"
base_url = "<COMPANY_API_BASE_URL>"
wire_api = "responses"
requires_openai_auth = true
```

切换个人 Plus 后，使用官方内置 provider：

```toml
model_provider = "openai"
forced_login_method = "chatgpt"
```

注意：`OpenAI` 与 `openai` 是不同的 provider ID，不是同一个标识的显示名称。

### 2.2 切换后的问题

个人账号登录成功，但 VS Code Codex 插件中看不到之前的历史会话。检查 Ubuntu 本地会话文件：

```bash
find ~/.codex/sessions -name '*.jsonl' | wc -l
```

当时输出：

```text
107
```

说明本地仍有会话文件，不能仅凭插件列表为空判断历史被删除。

通过 CLI 使用旧会话 ID 恢复：

```bash
codex resume <SESSION_ID>
```

CLI 能定位旧会话，并提示选择工作目录。选择原会话目录后能够查看旧内容，但提示：

```text
Model provider unavailable

This chat uses model provider "OpenAI",
which is no longer configured.
Restore this provider's configuration to continue.
```

至此确认：旧会话绑定了原来的 `OpenAI` provider，而当前配置只有 `openai`。至少在本次使用的 Codex 环境中，这会导致旧会话无法按原方式继续，并影响历史列表显示。

### 2.3 尝试过但失败的方案

曾尝试保留大写 `OpenAI` provider，并将自定义 provider 的地址设置为官方 ChatGPT Codex 后端，配合 ChatGPT 登录。实际测试不成功，具体失败原因未记录。

因此不再采用自定义 provider 模拟官方登录，而改为保留官方 `openai` 配置，迁移旧会话的本地 provider 元数据。

如需恢复尝试前的 Plus 配置（前提是备份确实存在）：

```bash
cp ~/.codex/config.plus.toml ~/.codex/config.toml
```

## 3. 本地数据结构与定位

Codex 实际运行在 Ubuntu 远程扩展宿主上，因此本次处理的是 Ubuntu 用户目录下的 `~/.codex`，而非 Windows 客户端的目录。如果设置过 `CODEX_HOME`，需以实际目录为准。

```text
~/.codex/
├── config.toml          # 当前配置
├── config.company.toml  # 公司配置备份（如已创建）
├── config.plus.toml     # 个人配置备份（如已创建）
├── auth.json           # 认证信息（如果采用文件存储）
├── session_index.jsonl # 会话索引（如存在）
├── sessions/          # 会话正文及元数据
├── archived_sessions/ # 归档会话（如存在）
├── state_5.sqlite     # 本次确认的本地状态数据库
└── migration_backup/  # 本次迁移备份
```

本次迁移涉及两处：

| 存储位置 | 字段 | 迁移内容 |
| --- | --- | --- |
| `sessions/**/*.jsonl` 第一行 | `session_meta.payload.model_provider` | `OpenAI` → `openai` |
| `state_5.sqlite` 的 `threads` 表 | `model_provider` | `OpenAI` → `openai` |

JSONL 中的其余内容保持原始字节不变。SQLite 中仅修改匹配会话的 `model_provider`，不主动修改会话 ID、标题、工作目录、归档状态等。

## 4. 只读排查

### 4.1 查看环境及剩余空间

```bash
ls -lah ~/.codex/
echo "$CODEX_HOME"
codex --version
ls -lh ~/.codex/*.sqlite
du -sh ~/.codex/sessions
df -h ~
```

本次数据库为 `state_5.sqlite`，但实际 Codex CLI 及插件版本未记录。其他版本的数据库名称、表结构可能不同，不能直接照搬。

### 4.2 统计数据库中的 provider

```bash
python3 - <<'PY'
import sqlite3
from pathlib import Path

p = Path.home() / '.codex/state_5.sqlite'
with sqlite3.connect(p.as_uri() + '?mode=ro', uri=True) as db:
    for row in db.execute('''
        SELECT model_provider, COUNT(*)
        FROM threads GROUP BY model_provider
    '''):
        print(row)
PY
```

当时实际输出：

```text
('OpenAI', 625)
('openai', 3)
```

### 4.3 检查旧会话文件是否存在

```bash
python3 - <<'PY'
import sqlite3
from pathlib import Path
from collections import Counter

p = Path.home() / '.codex/state_5.sqlite'
with sqlite3.connect(p.as_uri() + '?mode=ro', uri=True) as db:
    rows = db.execute('''
        SELECT id, rollout_path, archived
        FROM threads WHERE model_provider = 'OpenAI'
    ''').fetchall()

stats = Counter()
for sid, path, archived in rows:
    if not path or not Path(path).is_file():
        stats['missing'] += 1
    elif archived:
        stats['archived'] += 1
    else:
        stats['active'] += 1

print('Total:   ', len(rows))
print('Active:  ', stats['active'])
print('Archived:', stats['archived'])
print('Missing: ', stats['missing'])
PY
```

当时实际输出：

```text
Total:    625
Active:   105
Archived: 0
Missing:  520
```

结论：105 条旧会话索引指向实际存在的未归档文件；520 条索引的 `rollout_path` 对应文件不存在。后者可能是残留索引，也可能是文件被移动，原因未查明，不能判定永久丢失。

这次只处理数据库与 JSONL 都能匹配的有效会话，不删除或修改缺失文件的索引。最初的 107 个 JSONL 文件与数据库统计的时间、范围并不完全相同，不必强行将两组数字对应。

## 5. 迁移前准备

1. 保存正在进行的工作，关闭连接 Ubuntu 的 VS Code 窗口以及 Codex CLI。
2. 通过独立 SSH 终端（例如 MobaXterm）连接 Ubuntu。
3. 检查后台进程，确认没有进程正在访问 Codex 数据库。

```bash
pgrep -af codex
```

本次曾看到：

```text
1615 codex -c features.code_mode_host=true app-server --listen unix://
```

这是 Codex 的后台 app-server。确认该进程没有执行任务后正常结束：

```bash
kill 1615   # 仅为当时的示例，实际操作应使用当前 PID
pgrep -af codex
```

如果进程自动重启，先关闭对应 VS Code 窗口或远程扩展宿主。优先正常退出，不要直接强制结束所有进程。

检查磁盘空间后进行完整备份（此前未必已经创建）：

```bash
du -sh ~/.codex
df -h ~
cp -a ~/.codex ~/.codex_backup_$(date +%Y%m%d_%H%M%S)
```

备份可能包含登录凭据和公司内部代码、日志。应存放在公司允许的本地位置，限制访问权限，不要上传到公开仓库。

## 6. 单条迁移试验

本次先对最近的一条符合条件的旧会话进行测试，逻辑如下：

1. 从 `threads` 中选择 `model_provider = 'OpenAI'`、`archived = 0` 的最近记录。
2. 校验文件确实位于 `~/.codex/sessions` 下，第一行是 `session_meta`，会话 ID 和 provider 与数据库一致。
3. 使用 SQLite backup API 备份数据库，并复制原始 JSONL 文件。
4. 仅将 JSONL 第一行的 provider 改为 `openai`，其余内容按字节复制到临时文件，再原子替换原文件。
5. 在 SQLite 事务中按会话 ID 更新对应记录；发生常规异常时尝试恢复原文件、回滚数据库。
6. 重启 VS Code，检查旧会话是否重新出现、历史消息能否翻阅。

实际结果：单条迁移成功。最初一度以为无法向上翻阅历史，后来确认是选错对话；打开正确会话后，历史内容显示正常。

这验证了该迁移方法在本次环境中可行。建议其他环境同样先试验一条，再批量迁移。

## 7. 批量迁移脚本

下面保留本次对话中采用的批量脚本主体。它默认只预检查，只有加上 `--apply` 才写入文件。脚本跳过缺失路径、目录之外的文件及元数据不匹配的记录，并为本次候选会话建立独立备份。

保存为 `~/codex_migrate_provider.py`（如果已有脚本，不需要重复创建）：

```python
import sqlite3
import json
import shutil
import os
import sys
import tempfile
from pathlib import Path
from collections import Counter
from datetime import datetime

home = Path.home() / '.codex'
root = (home / 'sessions').resolve()
db_path = home / 'state_5.sqlite'

apply = '--apply' in sys.argv
db = sqlite3.connect(
    db_path.as_uri() + ('?mode=rw' if apply else '?mode=ro'),
    uri=True
)

rows = db.execute('''
    SELECT id, rollout_path
    FROM threads
    WHERE model_provider = 'OpenAI'
    AND archived = 0
''').fetchall()

jobs = []
stats = Counter()

# Precheck
for sid, path in rows:
    if not path:
        stats['missing'] += 1
        continue

    p = Path(path).resolve()
    if not p.is_file():
        stats['missing'] += 1
        continue
    if root not in p.parents:
        stats['outside'] += 1
        continue

    try:
        with p.open('rb') as f:
            meta = json.loads(f.readline())

        if (
            meta.get('type') != 'session_meta'
            or meta['payload'].get('id') != sid
            or meta['payload'].get('model_provider') != 'OpenAI'
        ):
            stats['mismatch'] += 1
            continue

        jobs.append((sid, p, meta))
    except (ValueError, OSError, KeyError, TypeError):
        stats['invalid'] += 1

print('Ready:   ', len(jobs))
print('Missing: ', stats['missing'])
print('Outside: ', stats['outside'])
print('Mismatch:', stats['mismatch'])
print('Invalid: ', stats['invalid'])

if not apply:
    print('\nDry run only. No files modified.')
    db.close()
    sys.exit(0)

if not jobs:
    db.close()
    sys.exit('No sessions to migrate.')

# Backup
backup_root = home / 'migration_backup'
backup_root.mkdir(mode=0o700, exist_ok=True)
backup = Path(tempfile.mkdtemp(
    prefix='batch_' + datetime.now().strftime('%Y%m%d_%H%M%S') + '_',
    dir=backup_root
))
print('\nBackup:', backup, flush=True)

with sqlite3.connect(backup / db_path.name) as dst:
    db.backup(dst)

for sid, p, meta in jobs:
    target = backup / p.relative_to(home)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(p, target)

# Migration
changed = []
tmp = None
try:
    db.execute('BEGIN IMMEDIATE')
    for i, (sid, p, meta) in enumerate(jobs, 1):
        meta['payload']['model_provider'] = 'openai'
        with tempfile.NamedTemporaryFile(
            mode='wb', dir=p.parent,
            prefix='.migration_', delete=False
        ) as dst:
            tmp = Path(dst.name)
            with p.open('rb') as src:
                src.readline()
                dst.write(
                    (json.dumps(meta, ensure_ascii=False) + '\n').encode()
                )
                shutil.copyfileobj(src, dst)

        shutil.copystat(p, tmp)
        result = db.execute('''
            UPDATE threads
            SET model_provider = 'openai'
            WHERE id = ? AND model_provider = 'OpenAI'
        ''', (sid,))
        if result.rowcount != 1:
            raise RuntimeError('Unexpected row count: ' + sid)

        os.replace(tmp, p)
        changed.append(p)
        tmp = None
        print(f'[{i}/{len(jobs)}] OK {sid}')

    db.commit()
except BaseException:
    db.rollback()
    for p in reversed(changed):
        shutil.copy2(backup / p.relative_to(home), p)
    print('Migration failed. Rollback attempted.')
    raise
finally:
    if tmp is not None:
        tmp.unlink(missing_ok=True)
    db.close()

print('\nMigration successful!')
print('Migrated:', len(changed))
print('Backup:  ', backup)
```

### 7.1 先预检查

```bash
python3 ~/codex_migrate_provider.py
```

单条成功后，理论上预计如下（不是实际批量运行输出）：

```text
Ready:    104
Missing:  520
Outside:  0
Mismatch: 0
Invalid:  0
Dry run only. No files modified.
```

如果 `Mismatch`、`Invalid` 或 `Outside` 不为零，先检查原因，不要盲目执行批量迁移。

如仅想做单条试验，可在此脚本预检查完成后、备份前增加 `jobs = jobs[:1]`，再执行 `--apply`；需要批量执行时移除该限制。这是本文整理时补充的操作方式，不是此前单条脚本的原样复现。

### 7.2 正式迁移

```bash
python3 ~/codex_migrate_provider.py --apply
```

记录脚本输出的 `Migrated` 数量及 `Backup` 路径。本次用户反馈大部分迁移成功，但没有提供最终统计，因此不将 104 条全部成功写成事实。

### 7.3 脚本限制

- 依赖 Python 3.8+（使用 `Path.unlink(missing_ok=True)`）。
- 针对 `~/.codex/state_5.sqlite` 和本次观察到的数据库字段；不自动适配其他版本或自定义 `CODEX_HOME`。
- 只处理未归档的 `OpenAI` 会话，且 JSONL 必须位于 `sessions` 目录内。
- 不会修改认证信息、配置文件或项目代码，也不发起网络请求。
- SQLite 事务与文件替换并非跨文件的统一原子事务；断电、强制杀进程、磁盘故障等可能产生部分迁移。脚本的异常回滚属于尽力恢复，不能替代独立备份。
- 备份发生在数据库写事务之前，且未实现并发进程锁；必须先停止 Codex，避免其他进程同时写入。

## 8. 迁移结果验证

重新执行第 4.2 节的数据库统计。若所有候选都成功，理论值如下：

| 项目 | 初始统计 | 单条成功后的理论值 | 全部有效会话迁移后的理论值 |
| --- | ---: | ---: | ---: |
| `OpenAI` 索引 | 625 | 624 | 520 |
| `openai` 索引 | 3 | 4 | 108 |
| 缺失文件的旧索引 | 520 | 520 | 520 |

实际数值可能受新增会话等影响，以重新查询为准。

重新打开 VS Code Remote SSH 窗口，验证：

- [ ] 个人 Plus 仍能正常登录及创建新对话。
- [ ] 原来的旧会话出现在历史列表中。
- [ ] 选中正确旧会话，向上滚动检查历史消息。
- [ ] 会话 ID 和原工作目录保持不变。
- [ ] 不再出现旧 provider 不可用提示。
- [ ] 如公司允许，使用非敏感内容验证新请求是否正常；继续旧会话前确认历史上下文获准传输。

若需要验证批量备份与当前文件的历史正文是否一致，可使用下面的只读命令（将目录替换为脚本实际输出的备份路径）：

```bash
BACKUP="$HOME/.codex/migration_backup/batch_实际目录名"
python3 - "$BACKUP" <<'PY'
import sys
from pathlib import Path
from collections import Counter

backup = Path(sys.argv[1])
home = Path.home() / '.codex'
stats = Counter()
if not (backup / 'sessions').is_dir():
    raise SystemExit('Invalid backup path')

for old in (backup / 'sessions').rglob('*.jsonl'):
    new = home / old.relative_to(backup)
    if not new.is_file():
        stats['missing'] += 1
        continue
    with old.open('rb') as f:
        f.readline()
        body = f.read()
    with new.open('rb') as f:
        f.readline()
        current = f.read()
    if current == body:
        stats['identical'] += 1
    elif current.startswith(body):
        stats['preserved_with_append'] += 1
    else:
        stats['different'] += 1
print(dict(stats))
PY
```

`identical` 表示除第一行外正文完全一致；`preserved_with_append` 表示原正文仍完整且可能追加了新数据；`different` 需要进一步检查，并不自动等于数据丢失。此检查是整理时补充的批量验证方式，未在实际 Ubuntu 环境运行。

## 9. 备份与回滚原则

建议保留以下文件（以实际存在的文件为准）：

| 文件或目录 | 用途 |
| --- | --- |
| `~/.codex/config.company.toml` | 公司中转配置 |
| `~/.codex/config.plus.toml` | 官方 Plus 配置 |
| `~/.codex/migration_backup/` | 单条及批量迁移备份 |
| `~/.codex_backup_*` | 完整环境备份 |
| `~/codex_migrate_provider.py` | 正向迁移脚本 |

```bash
ls -ld ~/.codex_backup*
ls -lh ~/.codex/config*.toml
ls -lh ~/.codex/migration_backup/
```

若迁移后立即失败且没有产生新会话，可以停止 Codex，在确认备份版本正确后恢复本次对应的 SQLite 备份和 JSONL 文件。恢复数据库时需同时处理 SQLite WAL/SHM 状态，避免把旧 WAL 误用于恢复后的数据库。不要在进程运行期间覆盖数据库。

若已经使用个人 Plus 一段时间，**不要直接将旧的 `~/.codex` 或旧数据库覆盖当前数据**，否则可能丢失迁移后新增的会话或消息。应先另做当前完整备份，再按会话 ID 进行有选择的反向迁移；反向脚本尚未实现或验证。

## 10. 未来切回公司账号的方案

本次迁移完成后，旧会话的 provider 已经从 `OpenAI` 改成 `openai`。如果直接恢复公司的大写 provider 配置，已迁移的会话可能再次被隐藏。

### 10.1 两套独立环境（优先考虑长期隔离）

目标结构：

```text
~/.codex-personal/   # 官方 Plus：独立认证、配置、历史
~/.codex-company/    # 公司 SUB：独立认证、配置、历史
```

CLI 使用方式示例：

```bash
CODEX_HOME="$HOME/.codex-personal" codex
CODEX_HOME="$HOME/.codex-company" codex
```

这是一种未来可选方案，并非已完成的配置。VS Code Remote SSH 插件是否继承 `CODEX_HOME` 需要针对远程扩展宿主验证；在普通终端中设置变量不一定影响插件。此外，现有 `threads.rollout_path` 使用路径定位 JSONL，不能简单复制或移动整个目录就认定历史已正确迁移。认证若使用系统凭据存储，也需单独确认隔离效果。

优点是降低个人 Token 发往公司中转服务、个人聊天与公司聊天互相混用的风险；代价是两套历史默认不共用。

### 10.2 统一 provider ID（有条件尝试）

此前讨论过让公司 API 与个人 Plus 都使用小写 `openai`，理论上减少 provider 变化导致的历史过滤。

个人配置保持官方默认服务；公司 API 若兼容内置 provider，可研究 `openai_base_url` 和 API 登录方式。但本次没有实际验证公司服务兼容性，也没有验证当前 Codex 版本下配置的完整行为。

切换到任何第三方中转服务之前必须确保个人 ChatGPT Token 不会被发送到该服务；仅修改 URL 或 `forced_login_method` 不能作为认证已隔离的证明。共用会话还可能把个人历史发送给公司服务或反向传输公司历史，因此不作为默认方案。

### 10.3 反向迁移指定旧会话

若必须继续使用原公司 provider，可参考本次迁移逻辑，将获准迁移的特定会话从 `openai` 改回 `OpenAI`，同时更新 JSONL 与 SQLite。

不能简单把所有 `openai` 记录批量改成 `OpenAI`：其中可能包含个人 Plus 新建会话。应以原迁移备份里的会话 ID 为白名单，仅修改经过检查的公司来源会话。此方案尚未实测，不建议直接执行全库 SQL 更新。

### 10.4 后续工具化设想

未来可考虑实现 `codex-switch.sh`：

```bash
codex-switch company
codex-switch personal
codex-switch status
```

设计要求：先停止后台进程，检查目标配置与认证，确保服务地址正确，保护原有历史和新增数据，必要时按白名单迁移并创建备份，提供明确的回滚方式。

以上仅为命令接口设计，本次没有实现该工具。

## 11. 经验总结

1. 账号切换后历史列表为空，先检查远程运行环境中的本地会话文件，不要直接重装插件或删除 `.codex`。
2. Provider ID 是大小写敏感的会话标识；`OpenAI` 与 `openai` 的差异是本次问题的关键。
3. 数据库索引数量不等于可恢复的会话文件数量，本次 625 条旧索引中仅 105 条满足文件存在且未归档的条件。
4. 迁移时同时处理 JSONL 元数据和 SQLite 索引，只修改 provider，不修改聊天正文。
5. 先只读排查、停止后台进程、备份、单条验证，再批量处理；对缺失文件的索引不做破坏性操作。
6. 迁移成功显示历史不等于跨模型推理上下文完全兼容，也不代表已经验证计费额度或获得公司数据外发授权。
7. 经常切换不同信任域的账号时，应优先考虑认证和历史隔离，而非无条件共享所有会话。

## 12. 最终状态

| 验证项 | 本次结果 |
| --- | --- |
| 个人 Plus 登录 | 已完成 |
| 原因定位 | 已确认 provider 不匹配 |
| 单条 JSONL + SQLite 迁移 | 已验证成功 |
| 单条会话历史显示 | 已验证正常 |
| 批量迁移 | 用户反馈大部分成功，确切数量未提供 |
| 520 条缺失路径索引 | 未主动迁移或删除 |
| 跨模型继续旧工作会话及实际额度扣减 | 未完整验证 |
| 切回公司账号 / 双环境切换脚本 | 尚未实现及测试 |

本文依据本次对话及用户提供的终端输出整理，未重新联网核验当前 Codex 官方源码、Issue 或版本兼容性；未直接访问用户 Ubuntu 主机或代为执行迁移命令。
