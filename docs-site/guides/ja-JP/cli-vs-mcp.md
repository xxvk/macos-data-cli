### MCP ではなく CLI を選ぶ理由

mpia では、CLI が安定した唯一の正式インターフェースです。MCP にも用途はありますが、唯一の入口にすると Agent Host、Host ごとの設定、server のライフサイクル、TCC の実行主体に対する依存が増えます。これらの制約は、Agent に依存せず、ローカルファーストで、すぐ使えるという mpia の目標に合いません。

| 比較項目 | CLI<br>*コマンドラインインターフェース* | MCP<br>*モデルコンテキストプロトコル* |
| --- | --- | --- |
| Terminal を使える任意の Agent から呼び出せる | ✅ | ❌<br>*Host が MCP をサポートし、事前設定する必要がある* |
| Codex や Claude など特定クライアントに依存しない | ✅ | ❌<br>*Host ごとに対応状況と設定が異なる* |
| Homebrew インストール後すぐ利用できる | ✅ | ❌<br>*server 登録と Host 設定が残る* |
| 常駐 server のライフサイクルが不要 | ✅<br>*リクエストごとに起動・終了* | ❌<br>*起動、接続、復旧を管理する必要がある* |
| Shell、パイプ、workflow と組み合わせられる | ✅ | ❌<br>*MCP Client または追加のブリッジが必要* |
| Terminal から直接利用・デバッグできる | ✅ | ❌<br>*通常は Agent Host を経由する* |
| 署名済み App と安定した TCC 実行主体 | ✅<br>*権限を mpia App に集中できる* | ❌<br>*Host、server、データ処理プロセスの境界が分かれやすい* |
| 1 回のインストールを複数 Agent で共有 | ✅ | ❌<br>*通常は Host ごとの設定が必要* |
| JSON、Manifest、Schema の検出 | ✅ | ✅ |
| MCP Client 内でのネイティブなツール検出 | ❌<br>*任意の wrapper が必要* | ✅ |

したがって、mpia は CLI を唯一の canonical interface として維持します。将来、同じ Manifest を読み、処理を CLI に委譲する軽量 MCP wrapper を追加できますが、これは任意の適配層に限定し、ビジネスロジックの複製、安全規則の変更、CLI の置き換えを行ってはいけません。
