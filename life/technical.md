# Technical Patterns

## 工作技术栈
- 内网环境，文件加密
- nginx 相关（曾有版本演进需求）
- Spring Boot 开发经验（踩坑记录见下）

## 个人技术兴趣
- 技术选型/排查
- 个人技术学习

## Spring Boot @Component 类名大写前缀问题（2026-07-22）

### 问题描述
类名前三位连续大写时（如 ABCService），@Component 标注的 Bean 可能无法正常注册或装配。

### 原因
Spring 默认使用 Introspector.decapitalize() 转换 Bean 名称：
- `AbcService` → `abcService`（正常）
- `ABCService` → `ABCService`（保持全大写，异常）

全大写名称在 @Autowired 注入时可能匹配失败。

### 常见踩坑案例
- ABCService、URLHelper、APIConfig、HTMLParser

### 解决方法
1. 显式指定 Bean 名称：`@Component("abcService")`
2. 修改类名，避免前三位连续大写
3. 使用 @Named 注解

### 排查技巧
启动时加 `--debug` 看日志，或用 `ApplicationContext.getBeanDefinitionNames()` 检查实际注册的 Bean 名称。

## 前端不能直接访问 OSS 地址（2026-08-06）

### 问题描述
今天上线时遇到的问题，前端直接访问 OSS 资源地址失败。

### 原因
生产环境的 OSS 有白名单限制，只有指定的服务器/IP才能访问，前端浏览器不在白名单内。

### 正确做法
**前端通过后端接口获取图片等资源，不要直接访问 OSS 地址。**

后端作为代理去 OSS 取资源返回给前端，或者使用后端生成的带有时效性的签名URL。

### 适用范围
- 图片、文件等静态资源
- 任何存储在 OSS/OBS/S3 等对象存储上的资源

---

## Spring Bean 注入前提条件（2026-08-03）

### 问题描述
在排查信用卡 MQ 消息监听问题时，发现消息能获取到但没被处理。

### 原因
处理类没有加 `@Component`（或 `@Service`、`@Bean` 等），导致它本身不是 Spring Bean，因此无法通过 `@Autowired` 或 `@Resource` 等注解注入其他 Bean。

### 关键点
**一个类想要通过注解注入其他 Bean，它自己必须也是一个 Bean。**

### 常见踩坑场景
- MQ 消息监听器类忘记加 `@Component`
- 工具类、业务类忘记加注解
- 新增的处理类忘记注册为 Bean

### 解决方法
在处理类上添加合适的注解（`@Component`、`@Service`、`@Configuration` 等），将其注册为 Spring Bean。

### 排查技巧
1. 检查处理类是否有 `@Component` 系列注解
2. 确认包扫描路径是否包含该类
3. 启动时加 `--debug` 查看 Bean 注册日志

---

## OSS 更新同名图片后 CDN 缓存不生效（2026-08-07）

### 问题描述
OSS 上传同名文件覆盖后，前端访问到的还是旧图片。

### 原因
OSS 上传同名文件会直接覆盖，但 CDN 会缓存旧文件，不会自动更新。

### 解决方法
手动刷新 CDN 缓存，让它重新回源拉取最新的 OSS 文件。

### 适用场景
- 图片、静态资源更新后不生效
- OSS + CDN 架构的项目

---
*2026-08-06 夜间整理检查：technical.md 内容完整，无空模板，无重复条目，pending.jsonl 为空（0行），workflow/communication/lifestyle 均为备份状态已整合至 MEMORY.md*
