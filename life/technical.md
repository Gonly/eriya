# Technical Patterns

> 个人技术知识库，记录踩坑经验和解决方案。

---

## 技术栈概览

| 分类 | 说明 |
|------|------|
| 工作环境 | 内网环境，文件加密 |
| 主要技术 | nginx 版本演进、Spring Boot 开发 |
| 技术方向 | 技术选型 / 问题排查 / 个人学习 |

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

## 📌 前端与资源访问

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

---

## 📌 Activiti 工作流

### [2026-08-24] conditionExpression 多条件判断写法

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

## 📌 日期时间踩坑

### [2026-06-23] WSL2 datetime.now() 取到 UTC 日期导致任务 dueDate 偏移一天

**问题** 健身任务 dueDate 全部偏移一天，WSL2 服务器时区为 UTC，`datetime.now()` 返回 UTC 时间。

**原因** UTC 16:00~24:00 = 上海次日 0:00~8:00，用无时区 `datetime.now()` 在上海下午/晚间取到的日期比实际快一天。

**教训** 所有日期相关操作必须显式指定 `Asia/Shanghai` 时区，不能用裸 `datetime.now()`。

**修复** `dida_api.py` 和 `daily_briefing.py` 中统一用 `datetime.now(timezone(timedelta(hours=8)))` 或 `datetime.now().astimezone()`。

---

*最后整理：2026-08-22*
