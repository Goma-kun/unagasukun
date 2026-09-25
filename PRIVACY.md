# うながすくん プライバシーポリシー / Unagasukun Privacy Policy

最終更新日 / Last updated: 2026-09-26

このポリシーは、**Chrome 拡張機能版**と **iPhone / Mac アプリ版**の両方に適用されます。
This policy covers both the **Chrome extension** and the **iPhone / Mac app**.

## 日本語

**うながすくん**（以下「本ソフトウェア」）は、ユーザーのプライバシーを最優先に設計されています。

### データの収集について

本ソフトウェアは、**開発者を含む第三者に、いかなるデータも収集・送信しません**。

- 登録した予定（時刻・やること・曜日・詳細メモ）、実績の記録は、お使いの端末の中にのみ保存されます
- 開発者が運用するサーバーはありません。開発者を含む第三者が、ユーザーのデータにアクセスすることはできません
- アクセス解析・トラッキング・広告は行いません
- アカウント登録やログインは不要です

### iPhone / Mac アプリ版について

- **通知**：登録した時刻に「いまは○○の時間です」とお知らせするために、通知の許可をお願いします。許可しなくてもアプリは使えます
- **iCloud 同期（任意）**：設定で「iCloud で同期」をオンにすると、予定と記録が**あなた自身の iCloud（プライベートデータベース）**に保存され、同じ Apple アカウントでサインインした iPhone と Mac の間で揃います。保存先はあなたの iCloud であり、開発者はその内容を読むことも受け取ることもできません。オフにすれば iCloud への書き込みは止まります
- **データの書き出し／取り込み**：Chrome 拡張機能版から書き出した JSON ファイルを取り込む機能があります。ファイルはあなたが選んだものだけを読み、アプリの外には送りません
- アプリ版と Chrome 拡張機能版の間で、データが自動的に共有されることはありません

### Chrome 拡張機能版について

- データは `chrome.storage.local`（ブラウザ内）にのみ保存されます
- 閲覧履歴・閲覧中のページ内容には一切アクセスしません（そのための権限を持っていません）

| 権限 | 理由 |
|---|---|
| `storage` | 予定と記録をブラウザ内に保存するため |
| `alarms` | 設定した時刻に通知を出すタイマーのため |
| `notifications` | 「いまは○○の時間です」の通知を表示するため |
| `sidePanel` | 予定の管理画面をサイドパネルに表示するため |

### データの削除

- アプリ版：アプリを削除すると、端末内のデータはすべて消えます。iCloud 上のデータは、iPhone / Mac の「設定 → Apple アカウント → iCloud → アプリのデータを管理」から削除できます
- 拡張機能版：アンインストールすると、保存されたデータはすべて削除されます

### お問い合わせ

GitHub Issues: https://github.com/Goma-kun/unagasukun/issues

提供者：ニシラ（NISHIRA）

---

## English

**Unagasukun** ("this software") is designed with user privacy as the top priority.

### Data Collection

This software does **not collect or transmit any data to the developer or any third party**.

- Your plans (time, task, days, notes) and completion records are stored only on your device
- There is no server run by the developer. No third party, including the developer, can access your data
- No analytics, tracking, or advertising
- No account or sign-in is required

### iPhone / Mac App

- **Notifications**: the app asks for permission to show "It's time for ..." at the times you set. The app works without it
- **iCloud sync (optional)**: when you turn on "Sync with iCloud" in Settings, your plans and records are stored in **your own iCloud private database** and kept in sync between the iPhone and Mac signed in with the same Apple Account. The data lives in your iCloud; the developer cannot read or receive it. Turning sync off stops writing to iCloud
- **Export / import**: you can import a JSON file exported from the Chrome extension. Only the file you choose is read, and it never leaves the app
- Data is not shared automatically between the app and the Chrome extension

### Chrome Extension

- Data is stored only inside your browser (`chrome.storage.local`)
- The extension never accesses your browsing history or page content (it has no permission to do so)

| Permission | Reason |
|---|---|
| `storage` | To save your plans and records inside your browser |
| `alarms` | To schedule the timers that trigger notifications |
| `notifications` | To show "It's time for ..." notifications |
| `sidePanel` | To show the management screen in the side panel |

### Data Deletion

- App: deleting the app removes all data on the device. Data in iCloud can be removed from Settings → Apple Account → iCloud → Manage app data on your iPhone / Mac
- Extension: uninstalling deletes all stored data

### Contact

GitHub Issues: https://github.com/Goma-kun/unagasukun/issues

Provider: NISHIRA
