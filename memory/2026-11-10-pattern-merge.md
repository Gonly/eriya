
## 补充（13:10）：防复发的三层硬防线
1. **规则层**：nightly-review（主工作区写 patterns）+ 291bcec3（本工作区写 patterns）
   两个实际写入方的 prompt 都加了「按根因归并」硬规则；cleanup-5day 只引用 patterns 不写入，未改。
2. **校验层**：新增 `memory/evolution/patterns/_lint.py`——
   检查①无旧式 `### 标题 (日期)` 平行条目 ②编号序列恰为 A1~A11/B1~B10 ③21 条条目各含六个必需字段
   ④「合并自」引用的原始条目不重复归类。已接入 nightly-review prompt，退出码非 0 则不许回填 status=synthesized。
   ⚠️ 校验器自身踩过两个坑：①编号正则漏了 `###` 前缀导致引用计数恒为 0；
   ②只扫全文《》会把「已知未归并项」散文的引用误判为重复——已改为只取「合并自」字段。
3. **本工作区侧**：self-evolution/patterns/technical.md 的 cron 段 9 条（11-05~11-10）
   同样与主工作区 A2/A3/A5 同根因，已归并为 3 条（排查顺序 / 恢复判据 / 产物判定），
   并注明权威条目在主工作区，本地只留指针。技术条目 25 → 19。
