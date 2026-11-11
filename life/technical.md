# Technical Patterns

> 个人技术知识库，记录踩坑经验和解决方案。
> 相关文件：L2 经验索引 `memory/evolution/patterns/index.md`；长期记忆 `MEMORY.md`；工具速查 `TOOLS.md`

---

## 索引

| 分类 | 内容 |
|------|------|
| [📌 Spring Boot 问题](#-spring-boot-问题) | Bean 命名、Bean 注入前提 |
| [📌 前后端与资源访问](#-前后端与资源访问) | OSS 白名单、CDN 缓存 |
| [📌 工作流引擎](#-工作流引擎) | Activiti 条件表达式 |
| [📌 待办系统与脚本](#-待办系统与脚本) | 滴答清单 API 限制、脚本修复 |
| [📌 定时任务与消息推送](#-定时任务与消息推送) | 多条消息拆分、快照同步静默化；**2026-11-10 归并**：① 零产出与「假恢复」的排查顺序（启动延迟→error 原文五分类→预算余量→连续轮次，含调度槽位碰撞与 payload.model 大小写）② 恢复的唯一判据是连续 ≥3 轮 ok（含轮次整轮不存在的第三形态、长挂起独立归类）③ status 不代表产出，判产出只看产物落盘；**2026-11-11 补证**：孤立 ok 占比升到 98.0% 仍非恢复、error 原文第五类「网关重启中断」 |
| [📌 时间与时区](#-时间与时区) | WSL2 UTC 偏移 |
| [📌 工具使用规范](#-工具使用规范) | 比价、文件同步、主键设计 |
| [📌 支付接口规范](#-支付接口规范) | 通华/银联、终端能力码值 |
| [📌 知识库维护](#-知识库维护) | 归档规则、L1/L2 分工、信号队列边界 |

---

## 技术栈概览

| 分类 | 说明 |
|------|------|
| 工作环境 | 内网环境，文件加密；WSL2（服务器时区 UTC） |
| 主要技术 | nginx 版本演进、Spring Boot、Activiti、OceanBase MySQL 模式 |
| 业务域 | 支付收银（通华/银联）、IC 卡圈提、待办工作流 |

> OceanBase 兼容性、API 错误处理、Skill 激活等专题已独立成文，见 `memory/evolution/patterns/`。

---

## 📌 Spring Boot 问题

### [2026-07-22] @Component 类名大写前缀导致 Bean 注册失败

**问题** 类名前三位连续大写时（如 `ABCService`），`@Component` 标注的 Bean 可能无法正常注册或装配。

**原因** Spring 默认使用 `Introspector.decapitalize()` 转换 Bean 名称：
- `AbcService` → `abcService` ✅ 正常
- `ABCService` → `ABCService` ❌ 保持全大写，注入失败

**常见踩坑案例** `ABCService`、`URLHelper`、`APIConfig`、`HTMLParser`

**解决方案**
1. 显式指定 Bean 名称：`@Component("abcService")`
2. 修改类名，避免前三位连续大写
3. 使用 `@Named` 注解

**排查技巧** 启动时加 `--debug` 看日志，或用 `ApplicationContext.getBeanDefinitionNames()` 检查实际注册的 Bean 名称。

---

### [2026-08-03] Bean 注入前提条件 — 处理类必须是 Spring Bean

**问题** 消息能获取到但没被处理。

**原因** 处理类没有加 `@Component`（或 `@Service`、`@Bean` 等），导致它本身不是 Spring Bean，因此无法通过 `@Autowired` 注入其他 Bean。

**关键点** 一个类想要通过注解注入其他 Bean，它自己必须也是一个 Bean。

**常见踩坑场景**
- MQ 消息监听器类忘记加 `@Component`
- 工具类、业务类忘记加注解
- 新增的处理类忘记注册为 Bean

**解决方案** 在处理类上添加 `@Component`、`@Service`、`@Configuration` 等注解，将其注册为 Spring Bean。

**排查技巧**
1. 检查处理类是否有 `@Component` 系列注解
2. 确认包扫描路径是否包含该类
3. 启动时加 `--debug` 查看 Bean 注册日志

---

## 📌 Java 线程池与阻塞排查

### [2026-11-09] 线程池 RejectedExecutionException 排查决策树

**背景** ICC卡批处理 `Evaluate.execute` 抛
`RejectedExecutionException ... [Running, pool size=20, active threads=20, queued tasks=20000, completed tasks=0]`
日志伴随 `SocketIO - connect to app.tkms.prd.csrcb:12002 timeout:6000s`。

**核心判据（按可靠性排序）**
1. **`completed tasks = 0`** → 最可靠的雪崩信号。活跃线程满可能只是正常高负载；
   completed 停在 0 说明有任务卡在**不可中断的 IO** 上，一个都没跑完。
2. `pool size` 与 `active threads` 长期相等 → 线程被占满
3. `queued tasks` 持续上涨到上限 → 堆积

**决策树**
```
RejectedExecutionException
├─ completed tasks = 0？ ── 否 → 单纯并发过高，调大池/降批量/加限流
│        │是
│        └─ jstack <pid> > /tmp/thread.txt，搜线程名（如 pool-92-thread-20）
│             ├─ 卡在 socketRead0 / connect  → 网络不可达或服务端不回包
│             ├─ 卡在 park/wait + 连接池      → 连接池耗尽（maxActive/maxWait）
│             ├─ 卡在 getConnection / lock    → 锁竞争
│             └─ 卡在业务方法（DB/下游 HTTP） → 下游慢，线程池只是背锅
└─ 队列 20000 满 + 池编号递增（pool-92） → 另有线程池泄漏（每任务/chunk new 一个）
```

**关键认知：超时值是「放大器」不是「起因」**
- 服务端**秒回**时，线程毫秒级释放，超时值根本不会生效 → 改 timeout 无效
- 服务端**不可达**（黑洞 DROP / backlog 满）时，connect 挂满整个超时窗口 →
  超时值决定「卡多久」。6000ms 写成 6000s = 一挂 100 分钟，20 线程全被钉死
- 因此：**先查根因（对端可达性），再调超时**。把 6000s 改 6000s→ms 只是让雪崩来得更快，
  不解决「对端连不上」

**超时配置的坑**
- connect 超时和 socket 读超时是**两个独立配置**，别只改一个
- 用连接池时，`maxActive` 不足 → 线程卡在「借连接」上，**不走 socket 超时**，
  只能看 `maxWait` 和活跃连接数；日志线索是 `wait millis`

**验证动作（快→慢）**
1. `nc -zv <host> <port>` / `telnet` 测握手
2. `ss -tan | grep <port>`：大量 SYN_SENT = 对方不回包；ESTABLISHED 堆积 = 连上了但不返数据
3. 查对端同期日志与连接数
4. 核对 connect/读超时两个配置项
5. 若用连接池，拉 `maxActive` / `maxWait` / 活跃连接数

**修复优先级**
1. 修根因（服务不可达/超时单位错）
2. 线程池改单例（Spring Bean 注入），禁止在 execute 内 new
3. 队列调小 + 换拒绝策略（落库/重试），别静默丢任务
4. 加熔断：连续 N 次超时即标记批次失败，不再投递
5. 监控补 pool size / active / queued / **completed** 四指标，completed 停在 0 应告警

**合规附带项** ICC 报文日志里 `iccPAN` 明文卡号、`signData01/02/03` 未脱敏，需一并处理

---

## 📌 前后端与资源访问

### [2026-08-06] 前端不能直接访问 OSS 地址

**问题** 前端直接访问 OSS 资源地址失败。

**原因** 生产环境的 OSS 有白名单限制，只有指定的服务器/IP 才能访问，前端浏览器不在白名单内。

**正确做法** 前端通过后端接口获取图片等资源，不要直接访问 OSS 地址。后端作为代理去 OSS 取资源返回给前端，或使用后端生成的带时效性的签名 URL。

**适用范围** 图片、文件等静态资源，任何存储在 OSS/OBS/S3 等对象存储上的资源。

---

### [2026-08-07] OSS 更新同名图片后 CDN 缓存不生效

**问题** OSS 上传同名文件覆盖后，前端访问到的还是旧图片。

**原因** OSS 上传同名文件会直接覆盖，但 CDN 会缓存旧文件，不会自动更新。

**解决方法** 手动刷新 CDN 缓存，让它重新回源拉取最新的 OSS 文件。

**适用场景** 图片、静态资源更新后不生效，OSS + CDN 架构的项目。

---

## 📌 工作流引擎

### [2026-08-24] Activiti conditionExpression 多条件判断写法

**问题** 如何在 Activiti 的 condition expression 中同时判断两个条件成立。

**解决方案** 使用 UEL/SPEL 表达式语法：

```xml
<sequenceFlow sourceRef="exclusiveGw" targetRef="approveTask">
  <conditionExpression xsi:type="tFormalExpression">
    ${amount >= 1000 and status == 'APPROVED'}
  </conditionExpression>
</sequenceFlow>
```

**常用逻辑运算符：**

| 逻辑关系 | 写法 |
|---------|------|
| 逻辑与 | `${条件1 && 条件2}` 或 `${条件1 and 条件2}` |
| 逻辑或 | `${条件1 || 条件2}` 或 `${条件1 or 条件2}` |
| 逻辑非 | `${!条件}` 或 `${not 条件}` |

**注意：** 变量需存在于表达式上下文中，否则报找不到属性错误。

---

## 📌 待办系统与脚本

### [2026-08] 滴答清单 API 限制

- `/project/{id}/data` **只返回未完成任务**（status=0），已完成的拿不到
- 因此无法通过 API 查询「今日已完成」的任务，只能靠 `dueDate < today` 判断超期
- 其他已知限制（不支持 DELETE、不支持 GET 单任务、complete 端点为 `/project/{pid}/task/{tid}/complete`）见 `TOOLS.md`

### [2026-07-14] 待办脚本三处修复

| 脚本 | 问题 | 修复 |
|------|------|------|
| `fetch_todo_from_api.py` | 任务完成后 API 不再返回，脚本静默标记 completed 不上报 | 增加变化检测与报告 |
| `todo_reminder_data.py` | 循环任务误报，非执行日也提醒 | 解析 RRULE 的 BYDAY 字段判断今天是否执行日 |
| 快照同步 cron | agentId 为 null、timeout 180s 超时 | 补 agentId，timeout 提到 300s |

---

## 📌 定时任务与消息推送

### [2026-07] cron 多条消息发送

**方法** prompt 里写「分多条发送」，模型会自动多次调用 `message` 工具。

**关键** `mimo-v2.5` 会用 message 工具但不稳定，有时偷懒合成一条；`minimax/MiniMax-M2.7` 每次都会老实拆分。

**教训** 拆分稳定性取决于 prompt 结构 —— 明确按类拆（工作/个人）比笼统说「1~3条」靠谱得多。

**参考 prompt 结构**：「【重要：分多条发送】把内容拆成 X 条消息分别发送，不要合成一条」

### [2026-07-14] 快照同步 cron 静默化

无变化时让模型回复 `NO_REPLY`，避免往 QQ 发无关消息。

### [2026-11-05~11-10 归并] 定时作业零产出与「假恢复」的排查顺序

> 本条由原 9 条按**根因**归并而成（同槽位排队 / model 大小写 / 预算余量 / 单次 ok / 连续 N 轮 /
> error≠零产出 / ok≠零产出 / 轮次整轮不存在 / 孤立 ok 占比无单调）。
> 主工作区侧的权威条目：`memory/evolution/patterns/agent-ops.md` → **A2 轮次健康三态判定**、
> **A3 输入侧无界**、**A5 配置由脚本断言**；证据细节见 `memory/evolution/patterns/cross-workspace-signal.md`（**小助工作区路径**，主工作区无此文件，见 📌 知识库维护 → 跨工作区相对路径会断链）。

**一句话判据：** 零产出或「疑似恢复」的结论，必须同时给出
**启动延迟 + error 原文分类 + 连续轮数 + 产物落盘事实**四项，缺一项就不成立。

**排查顺序（不可跳步）**

1. **先算启动延迟**：`start = ts - durationMs`，与 `runAtMs` 相减。
   `timeoutSeconds` 计时从**实际启动**开始，不是从名义调度点开始——
   「延迟 96 分钟启动 + 600s 预算」= 必然零产出。
   只看 `durationMs` 会误判成「作业变慢了／工作量变大了」。
2. **再分类 error 原文**（五类形态）：

   | error 形态 | 含义 | 处理方向 |
   |-----------|------|---------|
   | `rejected by ... allowlist` | **配置问题**，模型名与 allowlist 不匹配 | `payload.model` 精确到 allowlist 登记值（**大小写敏感**：`minimax/MiniMax-M2.7`） |
   | `cron: job execution timed out` | 执行预算问题 | 先查启动延迟，别急着提 timeout |
   | `timed out` 但该作业历史上常 ok | 工作量逼近预算上限 | 见判据 3 |
   | `FailoverError: LLM request failed: network connection error` | **网络/上游 failover**，与预算、配置无关 | 重试即可；不要改 timeout、不要动 payload |
   | `cron: job interrupted by gateway restart` | **基础设施中断**（网关重启），与预算、配置、工作量都无关 | 不调 timeout、不动 payload；查该轮 `runAtMs` 与 fin 的差值判断归属；**durationMs 远小于 timeout ⇒ 不是超时** |

   > 第四类实测（11-08 04:15，`924a5d1a`）：`durationMs=134377`，**远低于 timeout 上限**，
   > 是「根本没跑满就被打断」的形态。**error 轮 durationMs 明显小于 timeout ⇒ 不是预算问题。**
   > 改 `payload.model` / `payload.timeoutSeconds` 都在 `jobs.json` 的 **`payload` 节点**里，
   > 不在 job 顶层——改错层级会静默无效。

3. **再看预算余量**：ok 轮耗时中位数 > **0.7×timeout** ⇒ 判定「预算余量不足」，而非「环境不稳」。
   实测 `924a5d1a`（timeout 600s）ok 轮耗时 145s→509s（10-25~10-26）、253s→495s（11-02~11-04），
   近期多轮占掉 **70%~98%** 预算 ⇒ 「交替」会自然演化成「持续失败」。
   **处置优先级：先减工作量（缩小扫描范围／增量处理），再考虑提 timeout**——
   单纯提 timeout 只会把失败推迟到下一个更长的输入。

4. **最后才看连续轮数与恢复判据**（见下条）。

**调度层陷阱（独立于超时层）**
同一个 `0 2 * * *` 槽位上曾有三个作业（`nightly-review` timeout=0 / `291bcec3` timeout=600 /
`924a5d1a` 02:13 timeout=600）。11-04 `nightly-review` 跑了 **6368239ms（106 分钟）**独占窗口到 03:46，
`291bcec3` 名义 02:00、**实际 03:36:07 才开始跑**，剩 600s 预算 → 03:46:08 被砍，整轮调查作废。
⇒ **把 timeout 从 300 提到 600 解决不了这类失败**，瓶颈是排队延迟而非执行时长。
同槽位不同 agentId **不会**互相抢锁，但调度器照样串行化。
**解法：错开槽位**（`291bcec3` 已从 `0 2 * * *` 改为 `0 1 * * *`，改前备份 `cron/jobs.json.bak.20261105`，改后回读校验）；
给长跑作业设 timeout 时，同时确认**同槽位是否有不限时作业**（`timeout=0` 意味着一旦它变慢，整点窗口会被它吃掉）；
长作业的产物必须能被独立观测——用**产物文件 mtime** 反推实际运行时刻，
不要只看 `runs/*.jsonl`（被挤掉的槽位在 runs/ 里不留任何 skipped 标记）。

**证据**
- `runs/291bcec3-*.jsonl` 末行 ts 与 `nightly-review` 末行 ts 相差 1ms（同一瞬间被砍）。
- `924a5d1a` 10-24~10-25 连续 12 轮失败，error 原文为
  `cron payload.model 'minimax/minimax-M2.7' rejected by agents.defaults.models allowlist: minimax/minimax-M2.7`。
- 11-05 那轮 `291bcec3` 耗时 438195ms（占 600s 的 **73%**），本身已进入余量不足区间。

---

### [2026-11-07~11-10 归并] 「恢复」的唯一判据是连续 ≥3 轮 ok

> 由原 4 条归并：单次 ok ≠ 恢复 / 连续 N 轮才叫恢复 / 孤立 ok 占比无单调趋势 / 轮次可能整轮不存在。

**一句话判据：** **恢复 = 连续 ≥3 轮 ok**。单轮 ok（无论耗时占比多低）都只是一次采样，不构成恢复证据。

**为什么不能用耗时占比当恢复判据**

| 孤立 ok 轮 | 耗时占比 | 事后 |
|-----------|---------|------|
| 11-06 06:13 | 76.3% | 又连续 9 轮 error（判「假恢复」，对） |
| 11-07 08:13 | **53.5%** | 又连续 8 轮 error（三级判据没覆盖到） |
| **11-09 22:21** | **87.7%**（526063ms） | 11-10 00:23 立即 error（占比反弹，仍不是恢复） |
| **11-10 06:13** | **70.6%**（423833ms） | 随后 08:13 / 10:13 / 12:13 又连续 3 轮 error |
| **11-10 14:13** | **98.0%**（588131ms） | 16:23 / 18:23 / 20:23 / 22:14 / 00:23 又连续 **5 轮** error（其中 22:14 是网关重启中断） |

⇒ **耗时占比是症状，不是病因**：占比一路下降（76.3% → 53.5%）而恢复从未发生；
占比反弹到 87.7% 也仍不是恢复；**占比再创新高到 98.0%（几乎贴满上限）依旧不是恢复**。
**占比既不是恢复的充分条件，也不是必要条件，恢复前后都可能取任意值。**
占比只回答「这一轮有没有余量」，永远不回答「根因是否已修」。

**作业失效有三种形态，只统计两种会漏掉最彻底的那种**

| 形态 | 日志特征 | 统计口径 |
|------|---------|---------|
| 跑了并成功 | status=ok | ok 计数 |
| 跑了但失败 | status=error | error 计数 |
| **压根没跑** | **runs 里没有这一轮** | **「计划轮次 − 实际记录条数」的差值** |

只按 status 比例构造的健康指标对第三种形态**完全无感**——未启动是最彻底的失败，
却不计入 error、不产生任何 summary，最容易被漏判成「今天很健康」。

11-09 网关重启（`runs/e12bc525-*.jsonl` ts=11-09 21:02:07，`error='cron: job interrupted by gateway restart'`）前后实测：

| 作业 | 计划轮次 | 实测 | 性质 |
|------|---------|------|------|
| 主动消息 `760a13d0` | 11-09 21:00 | runs 里无 21:00 轮（连 error 都没有），最近两轮 18:03 与 **22:49** | 轮次被静默丢弃 |
| 快照同步 `e12bc525` | 11-09 18:33/19:33/20:33 | 三轮全部不存在；紧接 21:02 那轮 error `durationMs=3511161`（**58.5 分钟**） | 未启动 + 长挂起 |
| 采集 `924a5d1a` | 11-09 18:13 | 该轮不存在；20:13 轮拖到 20:50 才启动、21:02 以 error 收场 | 未启动 + 延迟启动 |

⇒ 高频作业必须同时登记**计划轮次表**与**实际记录条数**，不等时输出差值清单；
「未启动」与「失败」分开统计，不能合并成 error 率。
轮次被基础设施事件吞掉时**不留任何痕迹**，事后只看日志无法与「本来就没有内容可发」区分——
必须靠计划轮次表反查。
⚠️ 产物正常会**掩盖轮次缺失**：本工作区「待办快照同步」(`e12bc525`，每小时 :30) 11-09 丢了 18:33/19:33/20:33 三轮，
但 `data/todo_snapshot.json` 因 hourly 兜底仍在 00:33 更新 ⇒ 单看快照文件会以为一切正常。

**长挂起是独立故障类别**
某轮 `durationMs` 相对自身 p99 放大两个数量级（快照同步常态 10~36s，那轮 3511161ms = 58.5 分钟）
应作为**独立故障类别**告警，而不是等基础设施重启把它连带杀掉。
`error` 文案写「被重启中断」会掩盖「它自己挂了」这个真实原因——
判断归属要看该轮 `runAtMs` 与 fin 的差值。

**停摆形态序列（截至 11-11）**
交替 → 连续全停摆 → 孤立 ok(76.3%) → 连续全停摆 → 孤立 ok(53.5%) → 连续全停摆(8 轮) →
孤立 ok(87.7%) → 连续全停摆 → 孤立 ok(70.6%) → 连续全停摆(3 轮) → 孤立 ok(98.0%) → 连续全停摆(5 轮)。
⇒ **11-10 单日之内出现了两次孤立 ok**（06:13 与 14:13），两次都紧跟连续 error；
形态已从「长停摆 → 偶发单次 ok」变成「**停摆期内多次插单次 ok**」，比单次 ok 更容易被误读为「快恢复了」。
**每次插单都要报「该轮占比 + 其后连续 error 轮数」，两者缺一即不构成恢复证据。**

**证据**
- 主工作区 `memory/evolution/patterns/agent-ops.md` → A2；`memory/evolution/patterns/cross-workspace-signal.md` §1.6~§1.12（**小助工作区路径**，主工作区无此文件）。
- ⚠️ 主工作区信号 #144 对本轮 600292ms 的归因**有误**（写成「300s 常态预算被整体推翻」），
  真实原因是「排队延迟吃掉预算」，见上条。

---

### [2026-11-07~11-08 归并] status 不代表产出——判产出只看产物落盘

> 由原 2 条归并：`status=error` 不等于零产出 / `status=ok` 也可能零产出。
> 主工作区权威条目：`memory/evolution/patterns/agent-ops.md` → **A1 产物落盘才是完成凭证**、
> **A2 轮次健康三态判定**；本条只保留本地证据细节。

**一句话判据：** `status` 只描述「这一轮有没有在预算内结束」，**既不能证明有产出，也不能证明没产出**。
判产出只看**产物文件的 mtime / 条数变化 / 待综合队列是否减少**——不看 status，不看 summary 文本。

| status | 可能的产出情况 | 判据 |
|--------|--------------|------|
| `ok` | 真产出 / **零产出**（把思考当最终回复） | 目标文件 mtime 是否前移、条目数是否变化 |
| `error` | 真零产出 / **部分产出**（超时前已落盘） | 同上 |

**error 轮要分两问**
1. 这一轮**有没有留下产物**（看目标文件 mtime / 队列 pending 增量）
2. 这一轮**有没有写完**（看 status 与产物完整性）

⇒ 连续 error 且队列完全不动 = **真零产出**（采集端彻底停摆）；
连续 error 但队列仍在长 = **超时边缘写入**（积压是假的，采集端在硬挤）。

**实测反例**
- **error 却有产出**：主队列 10 条 pending 的 ts 换算成 CST 分别是 11-06 06:13（ok 轮）与
  **11-06 14:13（error 轮，`durationMs=600456` 撞满上限）**；队列 mtime = 11-06 14:22:57，
  正落在那轮 error 的运行窗口内（14:13 → 14:23）——**error 轮把信号写进去了，只是没写完**。
- **ok 却零产出**：主工作区 `nightly-review` 11-07 02:39 那轮 status=ok、`durationMs=2382752`（**39.7 分钟**），
  但 `memory/evolution/patterns/` 三文件 mtime 仍停在 **11-06 02:07**，11-07 的 report / experience 全部缺失，
  主队列 **15 条 pending 一条未被综合**；summary 只剩半句英文推理
  （`Let me verify the decisive attribution: which job wrote the Day104 goal values.`）。
- **ok 也可能真产出**：11-09 22:21 那轮 ok 把主队列从 187 行写到 **192 行**
  （新增 5 条 pending，mtime 22:21:39 落在 22:13:00→22:21:46 的运行窗口内）。

⚠️ `timeoutSeconds=0`（无护栏）+ 耗时已达同类作业上限近 4 倍的作业，即使 status=ok 也不能信任；
**先看产物，再谈成功**。

---

## 📌 时间与时区

### [2026-06-23] WSL2 datetime.now() 取到 UTC 日期导致任务 dueDate 偏移一天

**问题** 健身任务 dueDate 全部偏移一天，WSL2 服务器时区为 UTC，`datetime.now()` 返回 UTC 时间。

**原因** UTC 16:00~24:00 = 上海次日 0:00~8:00，用无时区 `datetime.now()` 在上海下午/晚间取到的日期比实际快一天。

**教训** 所有日期相关操作必须显式指定 `Asia/Shanghai` 时区，不能用裸 `datetime.now()`。

**修复** `dida_api.py` 和 `daily_briefing.py` 中统一用 `datetime.now(timezone(timedelta(hours=8)))` 或 `datetime.now().astimezone()`。

> 完整规范与检查清单见 `memory/evolution/patterns/datetime-timezone.md`

---

## 📌 工具使用规范

### [2026-07-08] 比价工具使用时机

**触发场景：** 用户询问商品价格、想购物、比价

**工具：** `shopmind-price-compare`

**命令格式：**
```bash
# 搜索
.venv/bin/python skills/shopmind-price-compare/scripts/main.py search --keyword "商品名称" --source 1

# 获取购买链接和口令
.venv/bin/python skills/shopmind-price-compare/scripts/main.py detail --id <商品ID> --source 1
```

**平台编号：** 0=全部 / 1=淘宝 / 2=京东 / 3=拼多多 / 4=苏宁 / 5=唯品会 / 6=考拉 / 7=抖音 / 8=快手 / 10=1688

**数据解读：**
- `actualPrice` = 券后价（最终价格，无需再减）
- `originalPrice` = 商品原价
- `couponPrice` = 优惠券金额（已包含在 actualPrice 中）

**⚠️ 重要：** 比价后必须给购买链接和口令，不要只给搜索关键词！

> 已验证（2026-07-16）：`calc_savings` 中 `actualPrice` 就是券后价，无重复减法逻辑。

> 通用「先查 TOOLS.md 再决定用 API 还是搜索」原则见 `memory/evolution/patterns/api-first.md`

### [2026-05-10] 找文件先搜本地，不要先查 git remote

**问题** 想找某个文件时第一反应是去 git remote 找，白白浪费对话轮次。

**正确做法** 先在本地工作区搜索（`find` / `grep` / `ls`），本地找不到再考虑 remote。

**适用范围** 任何「帮我找 X 文件 / X 在哪」类请求。

### [2026-07] 艾莉亚页面文件同步

- 源文件在 `workspace/memory/`，viewer 副本在 `skills/isekai-companion/viewer/memory/`
- Linux crontab 每 5 分钟跑 `auto-sync.sh`：对比时间戳 → 有更新才 cp → git commit → push
- ⚠️ 改页面内容要改**源文件**，改 viewer 副本会被同步覆盖

**艾莉亚 state.json 源文件位置（易改错）**

| 文件 | 路径 | 说明 |
|------|------|------|
| 源文件（唯一正确） | `/home/gong/.openclaw/workspace/skills/isekai-companion/state.json` | 改这里 |
| viewer 副本 | `skills/isekai-companion/viewer/state.json` | 只读，会被同步覆盖 |
| 日程数据 | `state.json` 的 `daily_schedule` 字段 | 不是独立文件 |

```bash
python3 -c "import json; print(json.dumps(json.load(open('/home/gong/.openclaw/workspace/skills/isekai-companion/state.json'))['daily_schedule'], ensure_ascii=False, indent=2))"
```

### [2026-07-09] 身份证号 hash 做主键

MD5 理论上够用，但建议 **SHA-256 + 加盐**（合规 + 防彩虹表），不要直接用明文身份证号做主键。

---

### [2026-11-03] 价格记录必须按时间顺序追加，不得插队

**问题** `memory/shopping/wishlist.md` 里 2026-11-02 的比价记录写在 2026-11-01 记录**之前**，
而 11-02 那条正文引用了「较 2026-11-01 记录的京东¥355 上涨约¥44」——引用的记录排在自己后面，读者无法顺读。

**根因** 写入方按「找到同一产品行 → 在行末追加」写入，跨轮并发/乱序到达时，
新记录会插到旧记录前面（11-02 那轮比 11-01 那轮晚落盘，但写入位置被挤到了前面）。

**正确做法**
1. 追加前先扫一遍该产品已有的日期行，新记录的日期必须**晚于**所有已有行
2. 若发现顺序倒置，交换行序而不是覆盖
3. 引用历史值时，引用对象必须出现在**自己之前**

**适用范围** `memory/shopping/wishlist.md`、`memory/games/wishlist.md` 这类「同一产品多条时间线记录」的文件。

## 📌 支付接口规范

> **权威库**：`self-evolution/patterns/payment-specs/README.md`
> 含通华收银宝 POS API（机构版）PDF 与终端读取能力码值表（60.4 域）。
> 本节只留结论，码值表以规范库为准，避免两处维护漂移。

- 终端能力码值 `6`（CUPMobile 现场移动支付，22 域前两位为 96）适用于手机 PAY 场景（Apple Pay、华为 Pay、小米 Pay 等）
- 其他码值（`0` / `2` / `5`）见规范库表格

---

## 📌 知识库维护

- 本文件为 L1 技术知识库；L2 专题见 `memory/evolution/patterns/`（索引：`memory/evolution/patterns/index.md`）
- 空壳/已整合的历史模板统一归档到 `archived.md`，不保留空白占位文件
- 永久原则（P001~P006）存于 `skills/evo-memory/principles.md`，与本文件不重复维护
- 每日夜间整理时同步检查：
  - `memory/evolution/gaps.md`（能力缺口，唯一权威来源）
  - `memory/evolution/todo.md`（复盘改进待办）
  - `memory/evolution/patterns/整理日志/`（写当日日志）
- ⚠️ **信号队列不在本工作区**：本工作区的 `self-evolution/pending.jsonl` 与 `memory/evolution/pending.jsonl` **恒为 0 字节**（无写入方），真正的队列在主工作区 `~/.openclaw/workspace/memory/evolution/pending.jsonl`（由 cron `924a5d1a` 写、`nightly-review` 综合）。**不要把「本工作区队列为空」当成「没有待整理信号」**——那是长期假健康信号。判定方法见 `memory/evolution/patterns/cross-workspace-signal.md`（**该文件只存在于小助工作区**，路径 `~/.openclaw/workspace-xiaozhushou/memory/evolution/patterns/cross-workspace-signal.md`；主工作区 `memory/evolution/patterns/` 下只有 agent-ops.md / memory-system.md / index.md / _lint.py，**同一相对路径在两个工作区指向不同文件**）。
- ⚠️ **队列非空也可能是假健康**（2026-11-05）：采集端可能「成功与超时交替」，此时 `pending>0` 与「写入端不稳定」同时成立。整理日志必须写出上游采集作业最近 4 轮的 status 序列，不能只写最后一次。
- ⚠️ **停摆形态的历次演进（2026-11-06 ~ 11-11）**：观察到的形态序列为
  「交替 → 连续全停摆 → 孤立 ok(76.3%) → 连续全停摆 → 孤立 ok(53.5%) → 连续全停摆(8 轮)
  → 孤立 ok(87.7%) → 连续全停摆 → 孤立 ok(70.6%) → 连续全停摆(3 轮) → 孤立 ok(98.0%) → 连续全停摆(5 轮)」。
  **单次 ok ≠ 恢复**，且 11-10 单日之内出现了两次孤立 ok，比单次 ok 更容易被误读为「快恢复了」。
  每次插单必须报「该轮耗时占比 + 其后连续 error 轮数」两项。
  **完整判据与证据见上方「定时任务与消息推送」的三条归并条目（排查顺序 / 连续 ≥3 轮 ok / status≠产出），
  此处不重复展开。**
- ⚠️ **本作业自身预算余量**（2026-11-08 自检）：11-07 那轮 `durationMs=512361` = 600s 的 **85.4%**，
  连续三轮进入 >70% 区间（11-05 73% → 11-06 81.9% → 11-07 85.4%，**逐轮恶化**）。
  11-07 日志定的「压到 60% 以内」目标尚未达成。必须**压缩单轮工作量**
  （少读全量文件、少做重复扫描、只读差异部分），不能靠提 timeout 硬撑。
  **2026-11-10 复盘**：11-08 那轮 371051ms（61.8%）达标，11-09 那轮 `durationMs=600301` **撞满上限零落盘**
  ⇒ 「偶发一次达标」不算修好，余量问题会周期性复发。
  **2026-11-11 复盘**：11-10 那轮 377780ms（**63.0%**）再次达标，但上一轮的教训未消除；
  仍须**结构性减负**（跨工作区取证一次性用结构化脚本取指标，不重读全文）。
  自身余量的权威条目在主工作区 `memory/evolution/patterns/agent-ops.md` A3（输入侧无界），本地只留指针。
- ⚠️ **跨工作区的相对路径引用会断链**（2026-11-11，据主队列信号）：
  `self-evolution/patterns/technical.md` 里引用的 `memory/evolution/patterns/cross-workspace-signal.md`
  **只存在于小助工作区**；主工作区 `memory/evolution/patterns/` 下只有 agent-ops.md / memory-system.md / index.md / _lint.py。
  ⇒ 同一相对路径在两个工作区指向不同文件，**从主工作区解析即断链**。
  本文件的跨工作区引用已统一标注为「小助工作区路径」并给出绝对路径。
  ⚠️ 主工作区 `patterns/index.md:212` 写着「`self-evolution/patterns/` 降级为历史归档、不再新增」——
  这句话**只对主工作区成立**（那里确实自 2026-05 起停更），**小助工作区同名目录仍是活跃写入方**（本文件 mtime 2026-11-11）。
  该索引声明的修正由主工作区 `nightly-review` 负责，本作业不代改。
- ⚠️ **本工作区的 pattern 库不在主工作区 `_lint.py` 的校验范围内**（2026-11-11，据主队列信号）：
  `_lint.py` 的 SCOPE 只含主工作区 `agent-ops.md`（A1~A11）与 `memory-system.md`（B1~B10），
  且其「旧式平行条目」正则要求 `### 标题 (YYYY-MM-DD)` 形态，
  对本工作区 `technical.md` 的 `### [YYYY-MM-DD] 标题` 形态**匹配率为 0**。
  ⇒ 主库校验通过**不能代表本工作区合规**，两个工作区必须各自跑各自的校验器。
  ✅ **2026-11-11 已补上门禁**：新建 `self-evolution/patterns/_lint_local.py`，
  5 条规则——条目标题去重 / 管道健康条目须带「归并」标记与主库指针且本地不超过 3 条 /
  跨工作区引用须标注所属工作区 / 引用的 A~B 编号须在主库现行 21 条主题内 /
  `gaps.md` 开放条数须与 `MEMORY.md` 记载一致；
  并已写入 cron `291bcec3` 的 prompt 作为收工门禁（exit 非 0 不许收工）。
  今后本工作区 pattern 写完必须跑 `python3 self-evolution/patterns/_lint_local.py`。
  ⚠️ 校验脚本自身也受同一纪律约束：不得为了让校验通过而删检查项或放宽阈值。
- 本作业的调度槽位必须避开 `nightly-review`（`0 2 * * *`、`timeout=0` 不限时）；当前为 `0 1 * * *`（2026-11-05 调整，备份 `cron/jobs.json.bak.20261105`）
- 同一事实只存一处：细节存 pattern 文件，MEMORY.md 只留索引与一行摘要


---

*最后整理：2026-11-11*
