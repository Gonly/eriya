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
| [📌 定时任务与消息推送](#-定时任务与消息推送) | 多条消息拆分、cron 调参 |
| [📌 时间与时区](#-时间与时区) | WSL2 UTC 偏移 |
| [📌 工具使用规范](#-工具使用规范) | 比价、文件同步、主键设计 |

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

### 比价工具使用时机

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

### [2026-07] 艾莉亚页面文件同步

- 源文件在 `workspace/memory/`，viewer 副本在 `skills/isekai-companion/viewer/memory/`
- Linux crontab 每 5 分钟跑 `auto-sync.sh`：对比时间戳 → 有更新才 cp → git commit → push
- ⚠️ 改页面内容要改**源文件**，改 viewer 副本会被同步覆盖

### [2026-07-09] 身份证号 hash 做主键

MD5 理论上够用，但建议 **SHA-256 + 加盐**（合规 + 防彩虹表），不要直接用明文身份证号做主键。

---

*最后整理：2026-10-22*
