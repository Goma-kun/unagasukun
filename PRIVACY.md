# うながすくん プライバシーポリシー / Unagasukun Privacy Policy

最終更新日 / Last updated: 2026-08-14

## 日本語

**うながすくん**（以下「本拡張機能」）は、ユーザーのプライバシーを最優先に設計されています。

### データの収集について

本拡張機能は、**いかなるデータも収集・送信しません**。

- 登録した予定（時刻・やること・曜日）、実績の記録、「実際は」のメモは、すべてお使いのブラウザ内（`chrome.storage.local`）にのみ保存されます
- 外部サーバーへの通信は一切ありません
- 開発者を含む第三者が、ユーザーのデータにアクセスすることはできません
- アクセス解析・トラッキングは行いません
- 閲覧履歴・閲覧中のページ内容には一切アクセスしません（そのための権限を持っていません）

### 使用する権限とその理由

| 権限 | 理由 |
|---|---|
| `storage` | 予定と記録をブラウザ内に保存するため |
| `alarms` | 設定した時刻に通知を出すタイマーのため |
| `notifications` | 「いまは○○の時間です」の通知を表示するため |
| `sidePanel` | 予定の管理画面をサイドパネルに表示するため |

### データの削除

本拡張機能をアンインストールすると、保存されたデータはすべて削除されます。

### お問い合わせ

GitHub Issues: https://github.com/Goma-kun/unagasukun/issues

提供者：ニシラ（個人事業主）

---

## English

**Unagasukun** ("this extension") is designed with user privacy as the top priority.

### Data Collection

This extension does **not collect or transmit any data**.

- Your plans (time, task, days), completion records, and "Actually" notes are stored only inside your browser (`chrome.storage.local`)
- There is no communication with any external server
- No third party, including the developer, can access your data
- No analytics or tracking
- The extension never accesses your browsing history or page content (it has no permission to do so)

### Permissions and Why They Are Needed

| Permission | Reason |
|---|---|
| `storage` | To save your plans and records inside your browser |
| `alarms` | To schedule the timers that trigger notifications |
| `notifications` | To show "It's time for ..." notifications |
| `sidePanel` | To show the management screen in the side panel |

### Data Deletion

Uninstalling the extension deletes all stored data.

### Contact

GitHub Issues: https://github.com/Goma-kun/unagasukun/issues

Provider: Nishira (sole proprietor)
