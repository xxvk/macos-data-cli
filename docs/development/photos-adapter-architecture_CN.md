# Photos adapter 0.5 架构

## 结论与目标

PhotoKit 可以作为 macOS Photos adapter 的公开 Framework 基础。0.5 先实现只读：权限、
album、有限范围 asset query、单条 get、metadata 和 opaque reference。导出独立进入第二阶段，
因为 metadata 可见不代表原始文件已在本机。导入、修改和删除不进入第一阶段 runtime。

## 公共 API 与权限边界

- 使用 `PHPhotoLibrary` 读取和请求 `.readWrite` 权限。
- 使用 `PHAsset`、`PHAssetCollection`、`PHCollectionList`、`PHFetchOptions` 和
  `PHFetchResult` 查询。
- 只有显式 export 可使用 `PHAssetResource`/`PHAssetResourceManager`；metadata query
  不得请求媒体字节。
- 不读取 Photos SQLite、library package、cache 或私有 Framework，也不做 Photos.app
  坐标自动化。

`photos permission` 返回 `not_determined`、`restricted`、`denied`、`limited` 或
`authorized`。limited 是有效但不完整的视图，响应必须 `complete: false`，不能把空结果说成
完整照片库为空。CLI 不静默打开 limited picker。Info.plist 必须包含
`NSPhotoLibraryUsageDescription`；add-only 权限不能满足读取。

## 资源、身份和读取模型

统一资源 kind 为 `photos_library`，provider 为 `photos`。PhotoKit 呈现一个可同时包含本机和
iCloud-backed asset 的用户照片库，不把它伪装成可选择的 iCloud account/container。

asset、album、cursor ID 都是 adapter 管理的 opaque 值。内部可以绑定 `localIdentifier`，
但调用方不得解析或假设能跨 Mac、照片库、恢复、删除再导入保持。album 标题可以重名，query
必须用 opaque album ID；discovery 保留用户 folder/album 层级并区分 smart album。

初始 payload 包含媒体类型/subtype、尺寸、视频时长、可用的创建/修改时间、favorite、hidden、
burst、Live Photo；只有 `--include-location` 才返回精确位置。metadata-only MVP 的
`contentAvailability` 为 `unknown`。query/get 不调用媒体 manager，也不触发 iCloud 下载；
hidden asset 默认排除。

```bash
mpia GET "/agent/manifest"
```

0.9.3 可执行 route 请从 manifest 获取；完整示例见 `docs/usage_CN.md`。

query 使用 creation date，start 必须早于 end，并设置跨度上限。默认 50、最大 200；按 creation
date 降序和 opaque ID 排序。分页使用绑定过滤条件的 opaque anchor cursor。

## 导出和延后写入

export 第一版每次一个 asset，必须指定输出路径，不向 JSON/stdout 写 binary，也不覆盖文件。
默认禁止网络；iCloud-only 原件返回 `content_not_local`，只有 `--allow-network` 才下载。必须
区分 original、Live Photo 配对资源、adjustment 和 rendered/current。先写私有临时文件，
成功后原子移动，失败删除残片。

已实现 variant：`original`、`current`、`paired-video`、`adjustment-data`。`current` 优先选择
full-size adjusted resource，不存在时回退 original，并在结果中报告实际 resource kind。同一
优先级存在多个资源时返回 `PHOTOS_EXPORT_VARIANT_AMBIGUOUS`，不猜测。输出权限为 `0600`；
拒绝已存在文件和 stdout，成功 JSON 也不回显目标路径。

import、favorite/hidden/location/date 修改、album 修改和删除必须各自经过 TDD，并使用
`--dry-run|--apply`。删除还需要准确确认短语和 Recently Deleted 语义。真实测试只能导入
一次性 fixture 并证明清理。

## 隐私与验收

日志不得记录文件名、位置、local identifier、album 名、输出路径或媒体字节；read smoke 只打印
权限和聚合数量。测试覆盖 permission/Info.plist、opaque ID、metadata mapper、location opt-in、
hidden、重名 album/hierarchy、query/order/pagination/cursor、limited `complete: false`、CLI contract
和 release/regression。开发顺序为：权限 → album → query/get → network opt-in 单条 export →
重新评估窄范围写入；删除最后考虑。

真实 album gate 只使用 `scripts/run_photos_read_smoke.sh`：仅输出权限、album kind 聚合数量、
complete 和 truncated；权限不可读时必须在 fetch 前停止。

当 agent shell 是 responsible process 时，macOS 可能把 PhotoKit 请求归因到 agent sandbox，
而不是 CLI app。有效的本机 TCC gate 必须把当前 bundle 安装到稳定路径，并使用
`MPIA_APP=/path/to/mpia-debug.app` 运行 smoke。脚本通过 LaunchServices 和临时
stdout/stderr 文件保留 app 身份，且不会暴露 album title 或 identifier。沙箱内直接执行得到的
denied 不能作为 app 本身被拒绝的证据。

签名 app 必须保留 `com.apple.security.personal-information.photos-library`。release gate
检查签名 bundle 内的实际 entitlement，而不是只检查源 plist。ad-hoc 重建会改变 code
requirement；需要无扩展属性地复制到稳定路径、在该路径重签名，必要时只重置这个 bundle 的
Photos 条目，并通过 LaunchServices 请求权限。

2026-08-14 本机 full-access gate 已通过：34 个集合（11 user、23 smart、0 folder）、未截断，
并完成有界 30 天 asset query/get sample（query 达到 5 条上限，opaque-ID get 1 条成功）。对外仅打印聚合数量；asset 和 collection JSON
只进入 smoke 的私有临时目录，并在结束时删除。

`scripts/run_photos_export_smoke.sh` 在私有临时目录执行真实默认离线 gate。2026-08-14 抽样的
5 个资源均为 iCloud-only；全部返回 `PHOTOS_CONTENT_NOT_LOCAL`，未开启网络，未留下输出。
同日，在用户明确批准后，`--allow-network` 从同一有界 sample 成功导出 1 个 original，验证
非零 byte 与 `0600` 权限，并删除私有临时输出。普通回归仍不得自动启用网络；下载
iCloud-backed resource 每次都必须获得新的明确批准。

`scripts/run_photos_metadata_smoke.sh` 将有界 query/get gate 标准化：最多读取 5 条近期 asset，
一个 opaque ID 只在私有临时目录内部传递，对外仅输出 schema 和数量断言。
