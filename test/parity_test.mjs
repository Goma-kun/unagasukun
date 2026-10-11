// 拡張機能の extension/logic.js と、iOS/Mac 用に移した ios/Sources/UnagasukunCore/Logic.swift が
// **同じ入力に同じ答えを返すか**を実際に突き合わせる。
//
// 場面の生成は parity_cases.mjs（Android 版の parity_android.mjs と共用）。
//
// 実行: node test/parity_test.mjs（プロジェクトルートから）
//       事前に swift build --package-path ios が要る

import { execFileSync } from 'node:child_process';
import { join } from 'node:path';
import { payload, root, compare } from './parity_cases.mjs';

// ---- Swift側を出す ----
let swiftOut;
try {
  swiftOut = execFileSync(join(root, 'ios', '.build', 'debug', 'uk-probe'), {
    input: payload, maxBuffer: 64 * 1024 * 1024,
  }).toString();
} catch (err) {
  console.error('NG: uk-probe を実行できません。先に `swift build --package-path ios` を実行してください。');
  console.error(err.message);
  process.exit(1);
}
const swiftResults = JSON.parse(swiftOut).results;

// ---- 突き合わせ ----
process.exit(compare(swiftResults, 'Swift') ? 1 : 0);
