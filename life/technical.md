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
| [📌 定时任务与消息推送](#-定时任务与消息推送) | 多条消息拆分、cron 调参、调度槽位碰撞、payload.model 大小写、timeout 预算余量、单次 ok ≠ 恢复、error 轮也可能已落盘、连续 N 轮才算恢复、ok 轮也可能零产出、error 原文四分类（FailoverError 网络故障）、timeout 非硬上限 |
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

### [2026-11-05] 同槽位作业会互相排队，延迟启动会吃掉整个超时预算

**问题** 本作业（`291bcec3` 小助-夜间知识库整理）11-04 那轮 `status=error`、`durationMs=600292`、
**零落盘**（无整理日志、无文件改动）。但这不是「工作量超预算」——11-04 那轮**根本没怎么开始干活**。

**根因（调度层，不是超时层）** 同一个 `0 2 * * *` 槽位上有三个作业：

| 作业 | agentId | timeout |
|------|---------|---------|
| `nightly-review` | main | **0（不限时）** |
| `291bcec3` 小助-夜间知识库整理 | xiaozhushou | 600 |
| `924a5d1a` 进化信号采集（`13 */2 * * *` → 02:13） | main | 600 |

11-04 的 `nightly-review` 跑了 **6368239ms（106 分钟）**，独占调度窗口直到 03:46。
本作业名义 02:00 启动，**实际 03:36:07 才开始跑**，只剩 600s 预算 → 03:46:08 被砍，
整轮调查全部作废（`runs/291bcec3-*.jsonl` 末行 ts 与 `nightly-review` 末行 ts 相差 1ms）。

**关键认知**
1. `timeoutSeconds` 计时从**实际启动**开始，不是从名义调度点开始——所以「延迟 96 分钟启动 + 600s 预算」= 必然零产出。
2. 把 timeout 从 300 提到 600（11-03 已做）**解决不了这类失败**，因为瓶颈是排队延迟而非执行时长。
3. **排查这类零产出必须先算启动延迟**：`start = ts - durationMs`，与 `runAtMs` 相减才是真正的排队时间。
   只看 `durationMs` 会误判成「作业变慢了/工作量变大了」。
4. 同槽位不同 agentId **不会**互相抢锁——调度器照样串行化。

**解决方案**
1. **错开槽位**（首选）：本作业已从 `0 2 * * *` 改为 `0 1 * * *`（01:00 槽位当天无其他作业），
   避开 `nightly-review` 的长尾窗口。改前已备份 `cron/jobs.json.bak.20261105`，改后回读校验。
2. 给长跑作业设上限（`timeoutSeconds`）时，同时确认**同槽位是否有不限时作业**——
   `nightly-review` 的 `timeout=0` 意味着一旦它变慢，整点窗口会被它吃掉。
3. 长作业的**产物必须能被独立观测**：用产物文件 mtime 反推实际运行时刻，
   不要只看 `runs/*.jsonl`（被挤掉的槽位在 runs/ 里不留任何 skipped 标记）。

**适用范围** 所有共用 cron 槽位的作业，尤其是 `nightly-review`（timeout=0）、`dreaming`（03:00）、
本作业（02:00→01:00）这组相邻窗口。

### [2026-11-06] cron payload.model 大小写必须与 allowlist 精确一致

**问题** 采集作业 `924a5d1a` 在 2026-10-24 ~ 10-25 连续 12 轮全部失败，错误信息是：

```
cron payload.model 'minimax/minimax-M2.7' rejected by agents.defaults.models allowlist: minimax/minimax-M2.7
```

**根因** `payload.model` 写成了全小写 `minimax/minimax-M2.7`，而 allowlist 里登记的是
`minimax/MiniMax-M2.7`（**M2.7 的大小写敏感**）。同一天的其他作业用同样的模型能跑通，
所以不是模型不可用，是**大小写不匹配**。

**教训** 排查 cron 作业失败时，**必须先看 error 原文的四类形态**：

| error 形态 | 含义 | 处理方向 |
|-----------|------|---------|
| `rejected by ... allowlist` | 配置问题，模型名与 allowlist 不匹配 | 改 `payload.model` 精确到 allowlist 登记值 |
| `cron: job execution timed out` | 执行预算问题 | 先查启动延迟（见上条），别急着提 timeout |
| `timed out` 但该作业历史上常 ok | 工作量逼近预算上限 | 见下一条「预算余量」 |
| `FailoverError: LLM request failed: network connection error` | **网络/上游 failover**，与预算、配置都无关 | 重试即可；不要改 timeout、不要动 payload |

> 第四类实测（2026-11-08 04:15，`924a5d1a`）：`durationMs=134377`，**远低于 timeout 上限**，
> 是「根本没跑满就被打断」的形态，与超时类形态从耗时上就能一眼区分。
> 判据：**error 轮的 durationMs 明显小于 timeout ⇒ 不是预算问题**（详见 [2026-11-09] 条目）。

**附带教训** 改 `payload.model` / `payload.timeoutSeconds` 都在 `jobs.json` 的 **`payload` 节点**里，
**不在 job 顶层**（顶层没有这两个字段），改错层级会静默无效。

---

### [2026-11-06] timeout 预算余量：ok 轮耗时占上限 >70% 就是定时炸弹

**问题** 采集作业 `924a5d1a`（timeout 600s）在 10-25 ~ 11-04 之间呈现
「成功与超时交替」，容易被误读成「随机抖动 / 环境不稳」。

**真相（实测耗时分布）**

| 时期 | ok 轮耗时 |
|------|----------|
| 10-25 ~ 10-26 | 145s / 203s / 252s / 327s / 467s / 509s |
| 11-02 ~ 11-04 | 253s / 323s / 437s / 443s / 458s / 479s / 495s |

**ok 轮耗时整体在向 timeout 上限（600s）爬**，近期多轮已经占掉 **70%~98%** 的预算。
在这种余量下，任何一次输入变多（多扫几个文件、多读几轮日志）都会把该轮推过 600s，
于是「交替」会自然演化成「持续失败」——**这正是 11-04 之后 13 轮连续超时的走向**。

**判据（新增）**

1. 不能只看 ok/err 比例，要看**成功轮耗时占 timeout 的比例趋势**。
2. ok 耗时中位数 > 0.7×timeout ⇒ 判定为「预算余量不足」，而非「环境不稳」。
3. 处置优先级：**先减工作量（缩小扫描范围 / 增量处理），再考虑提 timeout**——
   单纯提 timeout 只会把失败推迟到下一个更长的输入。
4. 同理适用于本作业自身：11-05 那轮 `291bcec3` 耗时 438195ms（占 600s 的 **73%**），
   同样已进入余量不足区间。

**适用范围** 所有有固定 `payload.timeoutSeconds` 的 agentTurn 型 cron 作业。

---

### [2026-11-07] 单次 ok ≠ 恢复：判据要看「ok 轮耗时占 timeout 的比例」

**问题** 采集作业 `924a5d1a` 在连续 13 轮全超时（11-04 22:23 → 11-06 00:23）之后，
11-06 06:13 突然出现一次 `status=ok`。若只看「最近有 ok 了」就会判定管线已恢复。

**真相** 那一轮的 `durationMs=458061` = 600s 的 **76.3%**，仍落在「预算余量不足」区间。
它不是恢复，是**「勉强挤过线的一轮」**——随后又连续 9 轮全 error（11-06 08:13 → 11-07 00:23）。

**判据（三级）**

| 观察 | 结论 |
|------|------|
| ok 轮耗时 < 40%×timeout | 真恢复（有余量） |
| ok 轮耗时 40%~70%×timeout | 边缘恢复，需继续观察 |
| ok 轮耗时 > 70%×timeout | **假恢复**，根因未解，下轮仍会超时 |

**教训** 「上游恢复了」这个结论，必须带上**恢复轮自身的耗时占比**才成立。
只看 status 序列会把「挤进去的一轮」误判成「已恢复」，从而推迟处置。

**适用范围** 所有有固定 `payload.timeoutSeconds` 的 agentTurn 型 cron 作业。

---

### [2026-11-07] `status=error` 不等于零产出——超时轮可能已把产物写进队列

**问题** 判断上游采集作业是否「有产出」时，容易直接用 `status=error` 当作「这轮什么都没写」。

**实测反例** 主队列 10 条 pending 的 ts 换算到 CST 分别是 11-06 06:13（ok 轮）与
**11-06 14:13（error 轮，`durationMs=600456` 撞满上限）**；队列 mtime = 11-06 14:22:57，
正落在那轮 error 的运行窗口内（14:13 → 14:23）。**error 轮把信号写进去了，只是没写完。**

**正确判据** error 轮要分两问：
1. 这一轮**有没有留下产物**（看目标文件 mtime / 队列 pending 增量）
2. 这一轮**有没有写完**（看 status 与产物完整性）

**含义差异**
- 连续 error 且队列完全不动 → **真零产出**（采集端彻底停摆，见 `cross-workspace-signal.md` §1.1/§1.5）
- 连续 error 但队列仍在长 → **超时边缘写入**（积压是假的，采集端在硬挤，见 §1.8）

**教训** `status` 描述的是「这一轮有没有在预算内结束」，不是「有没有产出」。
判断产出必须独立去看产物文件的 mtime / 行数变化。

---

> 主工作区侧的对应证据见 `memory/evolution/patterns/cross-workspace-signal.md`；
> 交叉引用的主工作区信号 #144 对本轮 600292ms 的归因有误（它写成「300s 常态预算被整体推翻」），
> 真实原因是上面这条「排队延迟吃掉预算」。

---

### [2026-11-08] 「ok 轮耗时占比健康」也不等于恢复——恢复判据必须是**连续 N 轮 ok**

**问题** 采集作业 `924a5d1a` 在 11-07 08:13 那轮 status=ok，`durationMs=320712` = 600s 的 **53.5%**，
落在 11-07 定的三级判据里「40%~70% 边缘恢复」区间，比 11-06 06:13 那轮（76.3%）**明显更健康**。
按直觉应该快恢复了。实际随后 **11-07 10:23 → 11-08 00:23 连续 8 轮全 error**。

**修正（给 11-07 结论划定适用范围）**
三级判据（<40% 真恢复 / 40~70% 边缘 / >70% 假恢复）判的是**单轮的性质**，不是**管线的状态**：

| 孤立 ok 轮 | 耗时占比 | 事后 |
|-----------|---------|------|
| 11-06 06:13 | 76.3% | 又连续 9 轮 error（判「假恢复」，对） |
| 11-07 08:13 | **53.5%** | 又连续 8 轮 error（判据没覆盖到） |

⇒ **耗时占比是症状，不是病因**。占比一路下降（76.3% → 53.5%）而恢复从未发生。

**正确判据（优先级最高）**
1. **恢复 = 连续 ≥3 轮 ok**。单轮 ok 无论占比多低，都只是「一次采样」，不构成恢复证据。
2. 单轮耗时占比只回答「这一轮有没有余量」，不回答「根因是否已修」。
3. 停摆形态序列（截至 11-08）：交替 → 连续全停摆 → 孤立 ok(76.3%) → 连续全停摆 → 孤立 ok(53.5%) → 连续全停摆(8 轮)。
4. 排查顺序不变：**先算启动延迟**（`start = ts - durationMs`）→ **再分类 error 原文** → **再看连续轮数** → **最后才看占比**。

**适用范围** 所有有固定 `payload.timeoutSeconds` 的 agentTurn 型 cron 作业。

---

### [2026-11-08] `status=ok` 也可能零产出——判产出必须看产物，不只看 status

**问题** 主工作区 `nightly-review` 11-07 02:39 那轮 status=ok、`durationMs=2382752`（**39.7 分钟**），
但 `memory/evolution/patterns/` 三文件 mtime 仍停在 **11-06 02:07**，11-07 的 report / experience 全部缺失，
主队列 **15 条 pending 一条未被综合**；summary 只剩半句英文推理
（`Let me verify the decisive attribution: which job wrote the Day104 goal values.`）。

**结论** `status` 只描述「这一轮有没有在预算内结束」——**既不能证明有产出，也不能证明没产出**。
11-07 那条只补了 error 侧，11-08 把 ok 侧对称补齐：

| status | 可能的产出情况 | 判据 |
|--------|--------------|------|
| `ok` | 真产出 / **零产出**（把思考当最终回复） | 目标文件 mtime 是否前移、条目数是否变化 |
| `error` | 真零产出 / **部分产出**（超时前已落盘） | 同上 |

**判产出只看产物**：文件 mtime、行数/条数变化、待综合队列是否减少。
**不看 status，不看 summary 文本**（summary 可以是半句废话而 status 仍是 ok）。

**教训** `timeoutSeconds=0`（无护栏）+ 耗时已达同类作业上限近 4 倍的作业，
即使 status=ok 也不能信任；**先看产物，再谈成功**。

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
- ⚠️ **信号队列不在本工作区**：本工作区的 `self-evolution/pending.jsonl` 与 `memory/evolution/pending.jsonl` **恒为 0 字节**（无写入方），真正的队列在主工作区 `~/.openclaw/workspace/memory/evolution/pending.jsonl`（由 cron `924a5d1a` 写、`nightly-review` 综合）。**不要把「本工作区队列为空」当成「没有待整理信号」**——那是长期假健康信号。判定方法见 `memory/evolution/patterns/cross-workspace-signal.md`。
- ⚠️ **队列非空也可能是假健康**（2026-11-05）：采集端可能「成功与超时交替」，此时 `pending>0` 与「写入端不稳定」同时成立。整理日志必须写出上游采集作业最近 4 轮的 status 序列，不能只写最后一次。
- ⚠️ **停摆形态会演进**（2026-11-06）：11-05 观察到的是「成功与超时交替」，11-06 同一作业已变成
  **连续 13 轮全超时**（最后成功 11-04 20:17）。假空队列会从「交替 → 全停摆」演化，
  判据要写成**连续 N 轮失败**而不是某一轮状态；且队列 mtime 停更是更早的可靠信号。
- ⚠️ **停摆形态还会再演进**（2026-11-07）：13 轮长停摆后出现一次孤立 ok（11-06 06:13），
  但该轮耗时 = 600s 的 **76.3%**，属「挤进去的一轮」，随后又连续 9 轮全 error →
  形态序列是「交替 → 连续全停摆 → 间歇性单次恢复 → 再度全停摆」。
  **单次 ok ≠ 恢复**，必须同时给出该 ok 轮的耗时占比（>70% 即假恢复）。
- ⚠️ **error ≠ 零产出**（2026-11-07）：超时被砍的那一轮，信号可能已写进队列
  （实测：11-06 14:13 的 error 轮写入了 5 条 pending，队列 mtime 14:22:57）。
  判「上游有没有产出」要看产物 mtime / pending 增量，不能只看 status。
- ⚠️ **本作业自身预算余量**（2026-11-08 自检）：11-07 那轮 `durationMs=512361` = 600s 的 **85.4%**，
  连续三轮进入 >70% 区间（11-05 73% → 11-06 81.9% → 11-07 85.4%，**逐轮恶化**）。
  11-07 日志定的「压到 60% 以内」目标尚未达成。必须**压缩单轮工作量**
  （少读全量文件、少做重复扫描、只读差异部分），不能靠提 timeout 硬撑。
- ⚠️ **停摆形态第四次演进**（2026-11-08）：11-07 08:13 出现一次占比仅 **53.5%** 的孤立 ok，
  比 11-06 的 76.3% 更「健康」，但随后又连续 8 轮全 error。**占比下降 ≠ 恢复**，
  恢复判据必须是「连续 ≥3 轮 ok」。详见 `memory/evolution/patterns/cross-workspace-signal.md` §1.9。
- ⚠️ **ok 轮也可能零产出**（2026-11-08）：`nightly-review` 11-07 02:39 那轮 status=ok、耗时 39.7 分钟，
  但主工作区 patterns 三文件 mtime 停在 11-06 02:07、15 条 pending 一条未综合。
  判产出只看产物 mtime / 条数变化，**不看 status、不看 summary 文本**。
- 本作业的调度槽位必须避开 `nightly-review`（`0 2 * * *`、`timeout=0` 不限时）；当前为 `0 1 * * *`（2026-11-05 调整，备份 `cron/jobs.json.bak.20261105`）
- 同一事实只存一处：细节存 pattern 文件，MEMORY.md 只留索引与一行摘要


---

*最后整理：2026-11-08*
