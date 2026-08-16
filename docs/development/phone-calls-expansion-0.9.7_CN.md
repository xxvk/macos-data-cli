# mpia-cli 0.9.7：Phone Calls 功能扩充

状态：`planned`

本文只记录未来实施计划，不代表 0.9.7 已实现、已验证或已授权发布。
当前 `VERSION` 不因本计划变更；实施、版本提升、提交、tag、push 与发布需要分别授权。

0.9.7 依赖稳定完成的 0.9.5 原生授权宿主和 0.9.6 通讯身份投影。共享身份和隐私规则见
[Messages 0.9.6 计划](messages-expansion-0.9.6_CN.md)。

## 目标

将 Phone Calls 从只有 `permission + recent` 的最小只读 adapter，扩展为完整的本机
通话历史数据面，支持筛选、详情、未接队列、联系人聚合、趋势统计、骚扰分类和来源分析。

0.9.7 保持完全只读：不拨号、不控制实时通话、不打开 Phone/FaceTime、不修改
Call History 数据库。

交付范围同时覆盖：

- REST-style CLI
- Manifest 和 JSON Schema
- OpenAPI 与三语文档
- 0.9.5 SwiftUI GUI 的生成式 route 页面
- Phone Calls 领域化历史和分析界面

## 身份与隐私

复用 0.9.6 的 `CommunicationIdentityProjection`：

```text
counterpartyId
contactId?
displayName?
maskedHandle
handleKind
matchStatus: matched | ambiguous | unavailable
```

- 有 Contacts 权限时返回联系人显示名和 opaque contact ID。
- 无匹配或无权限时，只返回遮罩号码或邮箱。
- 原始 `ZADDRESS`、`ZHANDLE.ZVALUE`、`ZNORMALIZEDVALUE`、`ZNAME`、数据库 ID 和 UUID
  不得离开 adapter。
- counterparty/source ID 使用机器本地 HMAC 生成，不保证跨机一致。
- 多个联系人匹配时返回 `ambiguous`，不得猜测。
- 原始号码、邮箱、设备名和 provider 不进入日志、state 或诊断包。

## Public Routes

保留并增强：

```text
OPTIONS /phone-calls/permission
GET     /phone-calls/recent
```

新增：

```text
GET /phone-calls/history
GET /phone-calls/detail
GET /phone-calls/missed
GET /phone-calls/counterparties
GET /phone-calls/analytics
GET /phone-calls/classifications
GET /phone-calls/sources
```

`OPTIONS /phone-calls/permission` 除 Full Disk Access 和 schema 状态外，还需报告：

- Contacts authorization
- basic history capability
- identity resolution capability
- group participant capability
- classification capability
- source metadata capability
- analytics capability

高级字段采用按功能分级的 capability gate；单个高级列缺失不得禁用基础 recent/history。

## History and Detail

`GET /phone-calls/history` 支持：

- from / to
- incoming / outgoing
- audio / video
- answered / missed
- read / unread
- contactId / counterpartyId
- blocked / junk
- sourceId
- limit / cursor

每条记录最多返回：

- opaque call ID
- `CommunicationIdentityProjection`
- direction / kind
- start time / duration
- answered / missed / read
- participant count
- FaceTime metadata
- blocked/junk classification
- translation-used 状态
- opaque source ID 和来源类别

`GET /phone-calls/detail` 使用 opaque call ID 获取单条详情。群呼参与者仅返回身份投影；
若 schema 或联系人匹配不明确，则只返回 participant count 和 limitation。

所有列表单页最多 200 条。cursor 绑定 schema fingerprint 与全部筛选条件，数据库或条件
变化后必须返回 stale cursor 错误。

## Missed and Counterparty Views

`GET /phone-calls/missed` 提供有界未接队列，支持日期、read 状态、联系人和来源筛选。

`GET /phone-calls/counterparties` 按 opaque counterparty 聚合：

- 联系人显示名或遮罩身份
- total / incoming / outgoing / missed count
- total / average duration
- answered rate
- first / last call time
- audio / video count

不得把 HMAC counterparty ID 当成跨设备永久标识。

## Analytics

`GET /phone-calls/analytics` 支持：

```text
groupBy = day | week | month | contact | direction | kind
```

返回：

- call count
- total / average duration
- answered / missed rate
- incoming / outgoing ratio
- audio / video ratio
- 高频联系人变化

默认分析最近 90 天；全历史必须显式 `scope=all`。日期换算需要显式 timezone，默认使用
系统时区并在响应中回显。SQLite progress handler 强制 deadline；超时返回稳定错误，
不得输出不一致的部分聚合。

## Classification and Sources

`GET /phone-calls/classifications` 只读汇总：

- blocked-by-extension count
- junk confidence/category
- filtered-out reason
- verification status
- emergency call count

不得执行拉黑、取消拉黑或修改分类。

`GET /phone-calls/sources` 聚合：

- opaque source ID
- source category
- call count
- last call time
- provider category

完整设备名、账号、local participant UUID 和 provider 原文默认不输出。

## SwiftUI GUI

Phone Calls 领域页提供：

- 通话历史表格
- 未接队列
- 联系人和遮罩身份分组
- 日期、方向、类型和状态筛选
- 日、周、月趋势图
- 时长、接通率和未接率卡片
- junk/blocked/source 只读诊断
- 单条通话详情

全部新增 route 必须同时具有 Manifest 生成的基础表单；领域化图表和页面只消费同一
route/schema，不得维护第二套统计逻辑。

## macOS Public API Boundary

- 当前 Xcode 27 Beta 5 macOS SDK 将 `CXCallController` 明确标记为 macOS unavailable。
- CallKit 服务于 App 自己的 VoIP provider，不能作为系统 Phone/FaceTime 历史控制面。
- 0.9.7 不使用 `tel:`、`facetime:` 或 UI automation。
- 0.9.7 不声称可以观察、接听、挂断、静音或控制实时系统通话。

## 明确不做

- 不拨号、不打开 Phone 或 FaceTime。
- 不删除通话记录、不标记已读。
- 不拉黑或取消拉黑。
- 不处理 voicemail。
- 不录音、不转录、不读取通话内容。
- 不观察或控制实时通话。
- 不直接写 `CallHistory.storedata`。
- 不允许输入或输出 raw 电话号码和邮箱。
- 0.9.7 route 不自动加入 0.9.4 公网 Demo allowlist。

## TDD 与验收

- 合成 Call History fixture 覆盖呼入、呼出、未接、视频、群呼、read、junk、blocked、
  translation 和多来源。
- 覆盖 Contacts denied、limited、ambiguous、重复号码和 store change。
- 覆盖日期边界、DST、timezone、分页、cursor 漂移和大型数据库 deadline。
- 覆盖 day/week/month/contact/direction/kind 聚合与统计精度。
- 覆盖未知 call type、未知 classification、缺失高级列和部分 capability 降级。
- 验证 raw 号码、邮箱、姓名、设备名、provider、数据库 ID 和 UUID 不进入输出或日志。
- live smoke 只输出聚合计数、capability 和 schema fingerprint。
- 新 route 全部进入 Manifest、OpenAPI、CLI help、三语文档和 SwiftUI GUI。
- 完整 Swift tests、CLI contracts、GUI tests、schema generation、Release build 和
  `git diff --check` 必须通过。

## 版本完成条件

- 0.9.5 已稳定完成，SwiftUI App 是权限和执行宿主。
- 0.9.6 的共享通讯身份投影已经稳定并经过隐私验收。
- 现有 `recent` contract 保持兼容；新增字段只能是兼容性 optional 字段。
- Phone Calls 领域页和全部新增 GUI route 已完成真实本机验收。
- `VERSION` 只在所有门禁通过后提升为 0.9.7。
- commit、tag、push、Release 与 Homebrew 更新分别授权。
