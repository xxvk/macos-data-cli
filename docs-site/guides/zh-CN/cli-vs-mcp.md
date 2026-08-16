### 为什么选用 CLI，而不是 MCP

对 mpia 而言，CLI 是正式、稳定的核心接口。MCP 并非没有价值，但把它作为唯一入口会增加 Agent Host、配置、进程生命周期和 TCC 身份的耦合；这些缺陷与 mpia 追求的跨 Agent、本机优先和开箱即用目标不符。

| 比较维度 | CLI<br>*命令行界面* | MCP<br>*模型上下文协议* |
| --- | --- | --- |
| 任意 Agent 通过 terminal 调用 | ✅ | ❌<br>*Host 必须先支持并配置 MCP* |
| 不依赖 Codex、Claude 等特定客户端 | ✅ | ❌<br>*不同 Host 的支持与配置存在差异* |
| Homebrew 安装后直接使用 | ✅ | ❌<br>*仍需注册 server 和维护 Host 配置* |
| 无常驻 server 生命周期 | ✅<br>*按请求启动并退出* | ❌<br>*必须管理 server 的启动、连接和恢复* |
| Shell、管道和 workflow 组合 | ✅ | ❌<br>*需要 MCP Client 或额外桥接层* |
| 用户可在 Terminal 直接调试 | ✅ | ❌<br>*通常必须经过 Agent Host* |
| 稳定签名 App 与 TCC 身份 | ✅<br>*权限集中于 mpia App* | ❌<br>*Host、server 与实际数据进程容易产生身份边界* |
| 一份安装供多个 Agent 共用 | ✅ | ❌<br>*通常需要为每个 Host 分别配置* |
| JSON、Manifest 与 Schema 发现 | ✅ | ✅ |
| MCP Client 内原生工具发现 | ❌<br>*需要可选包装层* | ✅ |

因此，mpia 保持 CLI 为唯一 canonical interface。未来可以增加一个轻量 MCP wrapper，读取同一份 Manifest 并委托 CLI 执行，但它只能是可选适配层，不能复制业务逻辑、改变安全规则或取代 CLI。
