// Haptics 单测 —— 触感反馈纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 TerminalToolDisplay.test / SpawnError.test 范式：同步断言（assertEqual / ===）。
//   覆盖 hapticEffectFor（事件→时长）/ normalizeHapticsPref（归一）/ pref↔enabled 互转；
//   不测 @ohos.vibrator（留真机）。

import { describe, it, expect } from '@ohos/hypium';
import {
  DEFAULT_HAPTIC_DURATION_MS,
  DEFAULT_HAPTICS_PREF,
  hapticEffectFor,
  normalizeHapticsPref,
  hapticsPrefToEnabled,
  hapticsEnabledToPref
} from '../main/ets/chat/Haptics';

export default function hapticsTest(): void {
  describe('Haptics — 默认值', () => {
    it('DEFAULT_HAPTIC_DURATION_MS = 10', 0, () => {
      expect(DEFAULT_HAPTIC_DURATION_MS).assertEqual(10);
    });
    it("DEFAULT_HAPTICS_PREF = 'on'（移动端默认开）", 0, () => {
      expect(DEFAULT_HAPTICS_PREF).assertEqual('on');
    });
  });

  describe('Haptics — hapticEffectFor 事件→效果', () => {
    it("send → kind=time, durationMs=10（最轻，频繁触发）", 0, () => {
      const e = hapticEffectFor('send');
      expect(e.kind).assertEqual('time');
      expect(e.durationMs).assertEqual(10);
    });
    it("longPress → durationMs=15", 0, () => {
      expect(hapticEffectFor('longPress').durationMs).assertEqual(15);
    });
    it("success → durationMs=12", 0, () => {
      expect(hapticEffectFor('success').durationMs).assertEqual(12);
    });
    it("delete → durationMs=20", 0, () => {
      expect(hapticEffectFor('delete').durationMs).assertEqual(20);
    });
    it("error → durationMs=30（最重，警示）", 0, () => {
      expect(hapticEffectFor('error').durationMs).assertEqual(30);
    });
    it('所有效果 kind 恒为 time', 0, () => {
      expect(hapticEffectFor('send').kind).assertEqual('time');
      expect(hapticEffectFor('delete').kind).assertEqual('time');
      expect(hapticEffectFor('longPress').kind).assertEqual('time');
      expect(hapticEffectFor('error').kind).assertEqual('time');
      expect(hapticEffectFor('success').kind).assertEqual('time');
    });
    it('错误/警示 > 删除 > 默认轻点（时长递减秩序）', 0, () => {
      // error(30) > delete(20) > longPress(15) > success(12) > send(10=DEFAULT)
      const send = hapticEffectFor('send').durationMs;
      const success = hapticEffectFor('success').durationMs;
      const longPress = hapticEffectFor('longPress').durationMs;
      const del = hapticEffectFor('delete').durationMs;
      const err = hapticEffectFor('error').durationMs;
      expect(err > del).assertTrue();
      expect(del > longPress).assertTrue();
      expect(longPress > success).assertTrue();
      expect(success > send).assertTrue();
      expect(send).assertEqual(DEFAULT_HAPTIC_DURATION_MS);
    });
  });

  describe('Haptics — normalizeHapticsPref', () => {
    it("'on' → 'on'", 0, () => {
      expect(normalizeHapticsPref('on')).assertEqual('on');
    });
    it("'off' → 'off'", 0, () => {
      expect(normalizeHapticsPref('off')).assertEqual('off');
    });
    it('空串 → DEFAULT(on)', 0, () => {
      expect(normalizeHapticsPref('')).assertEqual('on');
    });
    it('非法值 → DEFAULT(on)', 0, () => {
      expect(normalizeHapticsPref('garbage')).assertEqual('on');
    });
    it('大小写敏感：On(大写 O) → DEFAULT（严格 ===）', 0, () => {
      expect(normalizeHapticsPref('On')).assertEqual('on');
    });
  });

  describe('Haptics — pref ↔ enabled 互转', () => {
    it("hapticsPrefToEnabled('on') = true", 0, () => {
      expect(hapticsPrefToEnabled('on')).assertEqual(true);
    });
    it("hapticsPrefToEnabled('off') = false", 0, () => {
      expect(hapticsPrefToEnabled('off')).assertEqual(false);
    });
    it("hapticsEnabledToPref(true) = 'on'", 0, () => {
      expect(hapticsEnabledToPref(true)).assertEqual('on');
    });
    it("hapticsEnabledToPref(false) = 'off'", 0, () => {
      expect(hapticsEnabledToPref(false)).assertEqual('off');
    });
    it('往返一致：enabled→pref→enabled', 0, () => {
      expect(hapticsPrefToEnabled(hapticsEnabledToPref(true))).assertEqual(true);
      expect(hapticsPrefToEnabled(hapticsEnabledToPref(false))).assertEqual(false);
    });
  });
}
