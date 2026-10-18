# うながすくん Android 版

iPhone 版（`../ios/`）と同じ機能・同じ見た目の考え方で動く Android アプリ（Kotlin + Jetpack Compose）。
拡張機能 `../extension/logic.js` の判定ロジックを Kotlin に移してあり、**JS 版と同じ答えを返すことを `../test/parity_android.mjs` で突き合わせる**。

## 中身

| | |
|---|---|
| `core/` | 純 Kotlin/JVM。Android に依存しない判定ロジック（Logic / Today / NotificationPlan / LookBack / Cheer / Describe）と保存形式（Store）。`src/main/kotlin/.../probe/UkProbe.kt` が答え合わせの入口 |
| `app/` | Compose の画面（今日／カレンダー／登録フォーム／設定／ラベル編集）と通知（AlarmManager） |
| `play-assets/` | Play Console 用のアイコン（512） |

保存先は `filesDir/Unagasukun/snapshot.json`。iOS・拡張機能と同じ形なので、「データを書き出す／取り込む」で相互に読める。

## 環境

- JDK: Android Studio 同梱の JBR（`/Applications/Android Studio.app/Contents/jbr/Contents/Home`）を `JAVA_HOME` に
- SDK: `~/Library/Android/sdk`（`local.properties` の `sdk.dir`。無ければ作る）。`platforms;android-36` `build-tools;36.0.0` `platform-tools` が要る
- Gradle 9.5.1（wrapper）・AGP 8.13.2・Kotlin 2.3.21・Compose BOM 2026.06.01。**Gradle を 9.6 以降に上げると AGP 8.x が動かない**（AGP 9 へ上げるときに一緒に）
- compileSdk / targetSdk 36・minSdk 26。パッケージ名 `jp.nishira.unagasukun`

```
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
cd android
```

## ビルドとテスト

```
./gradlew :app:assembleDebug          # デバッグ APK → app/build/outputs/apk/debug/app-debug.apk
./gradlew :core:test                  # core のユニットテスト（Swift のテストを移したもの）
./gradlew :core:installDist           # 答え合わせ用 uk-probe → core/build/install/uk-probe/bin/uk-probe
node ../test/parity_android.mjs       # JS 版との突き合わせ（プロジェクトルートからは node test/parity_android.mjs）
```

`parity_android.mjs` は `test/parity_cases.mjs` で機械的に作った場面（1762 件）を JS 版と Kotlin 版の両方に食わせて答えを 1 件ずつ比べる。
**`logic.js` を直したら、必ず Swift 版・Kotlin 版の両方の突き合わせを走らせる。**

## エミュレータ

```
export ANDROID_HOME=$HOME/Library/Android/sdk
# 初回だけ（AVD を作る）。cmdline-tools は ~/Library/Android/sdk/cmdline-tools/latest に置いたものを使う
$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager create avd -n uk_pixel \
  -k "system-images;android-35;google_apis;arm64-v8a" -d pixel_8
$ANDROID_HOME/emulator/emulator -avd uk_pixel -no-snapshot -no-boot-anim &
$ANDROID_HOME/platform-tools/adb install -r app/build/outputs/apk/debug/app-debug.apk
$ANDROID_HOME/platform-tools/adb shell am start -n jp.nishira.unagasukun/.MainActivity
$ANDROID_HOME/platform-tools/adb exec-out screencap -p > shot.png
```

- 言語の切り替え: `adb shell "setprop persist.sys.locale ja-JP; setprop ctl.restart zygote"`（または設定アプリ）
- 暗い表示: `adb shell cmd uimode night yes` / `no`
- 見本データを入れる（デバッグ版だけ）: `adb push seed.json /data/local/tmp/seed.json` →
  `adb shell "run-as jp.nishira.unagasukun sh -c 'mkdir -p files/Unagasukun && cp /data/local/tmp/seed.json files/Unagasukun/snapshot.json'"` → アプリを起動し直す
- 通知の許可: `adb shell pm grant jp.nishira.unagasukun android.permission.POST_NOTIFICATIONS`

## AAB（Google Play 用）

```
./gradlew :app:bundleRelease          # → app/build/outputs/bundle/release/app-release.aab
```

署名は **upload key**（Play App Signing 用。アプリ署名鍵は Google が持つ）。鍵とパスワードはリポジトリに入れない。

- 鍵: `~/Keys/android/unagasukun-upload.jks`（alias `upload`）
- パスワード: キーチェーンの「unagasukun-android-upload-key」（`security find-generic-password -s unagasukun-android-upload-key -w`）
- Gradle は `~/.gradle/gradle.properties` の `UNAGASUKUN_UPLOAD_STORE_FILE` / `_STORE_PASSWORD` / `_KEY_ALIAS` / `_KEY_PASSWORD` を読む。
  無い Mac では debug 署名に落ちる（その AAB は Play に出せない）
- 確かめ方: `keytool -printcert -jarfile app/build/outputs/bundle/release/app-release.aab` の所有者が `CN=NISHIRA`

版は 1.0.0 (1)。上げるときは `app/build.gradle.kts` の `versionCode` を必ず増やす（Play は同じ番号を受け付けない）。

## 通知のしくみ

iOS は 64 件をまとめて予約するが、Android では AlarmManager に「次の 1 件」だけを張り、鳴ったら保存データから計画を作り直して次を張る（`notify/Scheduler.kt`）。
張り直しのきっかけはアプリ起動・記録や予定の変更・再起動（BOOT_COMPLETED）・時刻や時間帯の変更・アプリの更新。
正確な時刻のアラームには Android 12 以降「アラームとリマインダー」の許可が要る（無ければ `setAndAllowWhileIdle` で近似し、画面で案内する）。
