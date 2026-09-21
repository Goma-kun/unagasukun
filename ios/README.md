# うながすくん iOS / Mac（アプリ版の土台）

拡張機能 `extension/logic.js` の判定ロジックを Swift に移した層です。**UI はまだありません。**

アプリ版を作るにあたって最初にここを作ったのは、**拡張と同じ答えを返すことを先に確かめておくため**です。
画面から作ると、あとで挙動が食い違ったときに「UIのせいか判定のせいか」が分からなくなります。

## 中身

| | |
|---|---|
| `Sources/UnagasukunCore/` | 移したロジック本体。`Logic.swift` の関数は `logic.js` と1対1 |
| `Sources/uk-probe/` | JS版と突き合わせるための入口。JSONを受けてJSONを返すだけ。アプリからは使わない |
| `Tests/UnagasukunCoreTests/` | Swift側だけで壊れうるところ（曜日の数え方・月またぎ・時刻の解釈） |

## 確かめかた

```
swift build --package-path ios
node test/parity_test.mjs    # ← これが主役
swift test --package-path ios
```

`parity_test.mjs` は、予定・記録・基準日を機械的に1500通りほど作って、
**JS版と Swift版の両方に同じものを食わせて答えを1件ずつ比べます。**
手で書いたテストは思いついた場面しか見られないので、移植の取りこぼしはこちらで捕まえます。

## 実際に捕まった食い違い（最初の突き合わせで21件）

1. **`isValidEndTime` は時刻の範囲を見ていない。** JS は `/^\d{2}:\d{2}$/` しか見ておらず、
   終了時刻 `"24:00"` を通します（`new Date(...,24,0)` が翌日0時に繰り上がるので、
   結果として「その日の終わり」として正しく動く）。Swift 側で親切に範囲を弾いたら答えが変わりました。
   → `parseTimeParts`（形だけ）と `parseTime`（範囲まで）に分け、
   **範囲を見るのは `nextOccurrence` だけ**に揃えています
2. **日曜の番号。** JS の `getDay()` は日曜=0、Foundation の `weekday` は日曜=1
3. **丸めの括弧。** `(a - b) / DAY` を丸めるつもりが `DAY` を丸めていた（夏時間のある地域で1日ずれる）

**`logic.js` を直したら、必ず `parity_test.mjs` を走らせてください。**
どちらか片方だけ直すと、拡張とアプリで違う日に通知が出ます。
