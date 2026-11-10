# 2026-11-10 · patterns 库按根因归并

## 起因
宫磊发现「最近几天记录了很多技术问题」，除他问过的那条外，其余都是后台夜间复盘自动写入的。
他指出这些条目「看起来是一个问题」——确实是同一条根因被反复记了 141 遍。

## 动作
- 备份：`memory/evolution/archive/{agent-ops,memory-system}.full-20261110.md`（原始全文，未改动）
- 归并：`agent-ops.md` 79 条 → **A1~A11**（11 条，1987 行 → 962 行）
       `memory-system.md` 62 条 → **B1~B10**（10 条，1780 行 → 618 行）
- 共 141 条 → 21 条根因主题
- 每条新结构：**一句话判据 → 规则 → 常见形态 → 检查动作 → 证据 → 合并自**
- 校验：脚本比对原始备份，标题**零缺失、零重复**（全角括号的 2 条标题需特殊匹配）
- 证据全部保留：路径、jobId（924a5d1a / e12bc525 / lore-sync / nightly-review / cleanup-5day 等）、实测数字、日期
- 归并口径存档：`memory/evolution/archive/_taxonomy-20261110.md`

## 防复发（关键）
1. **nightly-review cron payload 已改**：新增第 4 条硬规则——写 pattern 前先查 `patterns/index.md` 主题表，
   命中已有主题就在该主题内追加证据行，禁止新建平行条目；无法归类才允许新增并须说明理由。
   （`~/.openclaw/cron/jobs.json` 已改，备份 `jobs.json.bak.20261110-merge`）
2. `patterns/index.md`：索引改为主题表 + 归并说明 + 使用约定更新
3. `memory/evolution/README.md`：patterns 章节写入新格式与写入纪律
4. 归并口径文件移入 `archive/`（避免被当成 pattern 条目），prompt 内引用路径同步更新

## 教训（本身也是 A10 的一条实例）
「同一模式再次出现时更新原条目」这条约定，在 141 条按日期堆叠的文件形态下形同虚设——
条目粒度太细，根因被拆散，约定无法执行。**必须先有主题粒度，约定才有约束力。**
