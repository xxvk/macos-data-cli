# Phone 适配器架构决策（0.9.2）

## 决策

0.9.2 交付一个**只读**的 `phone-calls` 适配器，数据源为本机通话历史的 Core Data
SQLite 库 `~/Library/Application Support/CallHistoryDB/CallHistory.storedata`，
沿用 Mail 0.2 与 Messages 0.9.1 已验证的 fail-closed 快速路径模式。读取通话历史
没有公开框架可用；适配器只读一个「运行时校验过 schema 指纹、immutable 连接」的
SQLite 视图，返回方向、时间、时长与未接状态——绝不返回对方号码原文或账号标识。

## 为什么是 0.9.2 的方向

- **没有公开读取 API。** `Phone.app` / `FaceTime.app` 没有通话历史的 AppleScript
  脚本字典，CallKit 仅限 iOS，也没有其他可读历史通话的公开 macOS 框架。
- **`CallHistory.storedata` 是唯一读取路径。** 它是 Core Data SQLite 库
  （`ZCALLRECORD` / `ZHANDLE` 及关联表），schema 由 Core Data 版本化
  （`DatabaseVersionPerm`），因此必须按 macOS 版本做指纹，不匹配即 fail-closed。
- **复用 Messages/Mail 架构。** Mail 0.2 与 Messages 0.9.1 已建立所需门禁：Full
  Disk Access、运行时 schema 指纹、immutable 只读连接、有界查询、deadline、
  fail-closed。Phone 直接继承该模式。

## 基线与本机观测到的 schema（macOS 27）

已在本机 macOS 27 上以严格只读（`mode=ro`）打开确认。
`com.apple.callhistory.databaseInfo.plist` 报告 `DatabaseVersionPerm = 46`。

观测到的表：

- `ZCALLRECORD` — 每条通话记录一行。0.9.2 用到的关键列：
  - `Z_PK` — 整型主键（不透明 ID 依据）。
  - `ZDATE` — TIMESTAMP，**Apple 纪元秒**带小数（`unix = ZDATE + 978307200`）。
    与 Messages `chat.db` 不同，这里**不是**纳秒。
  - `ZDURATION` — FLOAT，时长（秒），未接/未接通为 0。
  - `ZORIGINATED` — INTEGER，方向：`0` = 呼入，`1` = 呼出。
  - `ZANSWERED` — INTEGER，**呼入**是否已接听。
  - `ZCALLTYPE` — INTEGER，通话类型：`1` = 音频，`8` = 视频。
  - `ZHANDLE_TYPE` — INTEGER，参与者句柄类型：`1` = 电话，`2` = 邮箱。
  - `ZUNIQUE_ID` — TEXT，UUID（长度 36）。
  - 参与者 PII（永不读取）：`ZADDRESS`（号码/地址）、`ZNAME`、`ZLOCATION`、
    `ZISO_COUNTRY_CODE`、`ZSERVICE_PROVIDER`、`ZLOCALPARTICIPANTUUID`、
    `ZOUTGOINGLOCALPARTICIPANTUUID`、`ZPARTICIPANTGROUPUUID`。
- `ZHANDLE` — 参与者句柄（`ZVALUE`、`ZNORMALIZEDVALUE`）。永不 join 或读取；
  0.9.2 绝不返回对方号码。
- `Z_2REMOTEPARTICIPANTHANDLES` — 群呼句柄的多对多关联表。
- `ZCALLDBPROPERTIES`、`ZEMERGENCYMEDIAITEM`、`ZSAINTDAVIDSCOUNTS` — 超出范围。
- Core Data 记账：`Z_METADATA`、`Z_MODELCACHE`、`Z_PRIMARYKEY`（映射 `Z_ENT` →
  实体名）。

未接语义（在 272 行真实数据上确认）：

- 呼入（`ZORIGINATED = 0`）+ `ZANSWERED = 0` ⇒ **未接**；这些行 `ZDURATION` 全为 0。
- 呼出（`ZORIGINATED = 1`）：`ZANSWERED` 不可靠（已接通也为 0），以 `ZDURATION > 0`
  判定「已接通」。

读取器绝不能假设该 schema 永远不变；必须像 Mail 的 `V10` 门禁一样，在运行时探测
并校验一个有界的 schema 指纹，不匹配即 fail-closed。

## 命令面（0.9.2）

- `mpia phone-calls permission` — 状态只读探测：报告 Full Disk Access 与库可读性，
  不弹窗。
- `mpia phone-calls recent [--limit N] [--cursor C]` — 只读「近期通话」，最新在前，
  游标分页。每条返回：不透明本地 ID、方向、类型、已接听、未接、时长、时间。
- 仅只读：不发起通话、不删历史、不标已读、不做任何写入。

## 契约（metadata-first，不含对方 PII）

```json
{
  "ok": true,
  "contractVersion": "0.1",
  "data": {
    "items": [
      {
        "id": "call_8f2c4e",
        "direction": "incoming",
        "kind": "audio",
        "answered": false,
        "missed": true,
        "durationSeconds": 0.0,
        "at": "2026-08-14T09:12:00Z"
      }
    ],
    "nextCursor": "cur_8f2c4e",
    "complete": true,
    "truncated": false,
    "limitations": ["counterparty identifiers are never returned"]
  }
}
```

投影与脱敏规则（不可妥协）：

- 对方号码 / 邮箱 / 姓名 / 位置 / 运营商（`ZADDRESS`、`ZNAME`、`ZLOCATION`、
  `ZISO_COUNTRY_CODE`、`ZSERVICE_PROVIDER`、`ZHANDLE.ZVALUE`、
  `ZHANDLE.ZNORMALIZEDVALUE`）**永不读取或返回**。
- 原始主键与 UUID 绝不离开适配器；跨契约只暴露不透明 item ID（`call_…`）与不透明
  游标（`cur_…`）。
- `durationSeconds` 四舍五入到一位小数；`missed` 由「呼入 + 未接听」推导，
  `answered` 为呼入已接听标记（呼出则以 `duration > 0` 表示「已接通」）。
- live smoke 输出只含聚合（计数、截断、完整性），绝不打印号码、姓名或标识。

## TCC 与授权

- 读 `CallHistory.storedata` 要求 responsible process 具备 Full Disk Access。
  开发期用签名 app bundle（`.build/debug/mpia.app`），发布期用发布 bundle，均需
  授权 Full Disk Access。
- `phone-calls permission` 是状态查询，不弹窗；0.9.2 没有 `--request` 路径。

## 组件设计

- `PhoneStoreLocator` — 解析
  `~/Library/Application Support/CallHistoryDB/CallHistory.storedata`，拒绝符号链接
  和超大/不安全文件，报告发现状态。
- `CallHistoryReader` — 打开 immutable 只读 SQLite 连接，校验 schema 指纹，执行带
  deadline 的有界 `recent` 查询。
- `PhoneOpaqueID` — 把 `Z_PK` 和游标值编码为 `call_` / `cur_` 令牌（与
  `MessagesOpaqueID` 相同的 base64url 方案）。
- `PhonePagination` — 基于 (`ZDATE`, `Z_PK`) 的游标；游标绑定精确库指纹，库变化即
  失效（stale）。

## 稳定数据与隐私规则

- 把通话 ID、句柄、游标当作不透明适配器值。
- 绝不暴露原始 `Z_PK`、`ZUNIQUE_ID`、电话号码、邮箱、姓名或位置。
- 诊断日志绝不打印对方号码、姓名或标识。
- 游标过期或 schema 未知即 fail-closed，绝不自动重试。

## 测试与兼容门禁

- 单元测试只用合成 SQLite fixture（手工构造的 `ZCALLRECORD` schema），绝不读真实
  通话数据。
- 隐私最小化的 live smoke（`scripts/run_phone_calls_read_smoke.sh`）只打印聚合计数
  与截断状态；Full Disk Access 不可用时必须停止、不发起查询。
- 每个新的 macOS 版本都要重新探测 schema 指纹；不匹配即禁用快速路径，绝不猜测。

## 交付顺序

1. 架构决策（本文）+ 中文摘要。
2. `PhoneStoreLocator` + `PhoneOpaqueID` + `PhoneModels`。
3. `CallHistoryReader`（schema 指纹 + 有界 `recent` 查询）。
4. 注册表 + CLI 接线。
5. 合成 fixture 单元测试。
6. live smoke（仅聚合）+ `phone-calls permission` 验证。
7. README / usage / OpenAPI 重新生成。

## 0.9.2 明确不做

- 发起通话、删历史、标已读、voicemail、以及任何写入。
- 对方姓名解析（Contacts join）；通话内容转录；群呼参与者枚举；跨设备保证。
- `kind` 投影之外的 FaceTime 视频细节。
