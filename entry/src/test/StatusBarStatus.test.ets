// StatusBarStatus 单测 —— 顶部状态行决策纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 NetworkBannerResolve.test 范式：同步断言。
//   pickVibingMessage：取模 + 小写 + '…'；resolveStatusBarState：四态优先级（offline→permission→thinking→online）+ 色值。

import { describe, it, expect } from '@ohos/hypium';
import { pickVibingMessage, resolveStatusBarState, VIBING_MESSAGES } from '../main/ets/chat/StatusBarStatus';

export default function statusBarStatusTest(): void {
  describe('pickVibingMessage', () => {
    it('index 0 → 首词小写 + …', 0, () => {
      expect(pickVibingMessage(0)).assertEqual('accomplishing…');
    });
    it('末位 index → 末词小写 + …', 0, () => {
      expect(pickVibingMessage(VIBING_MESSAGES.length - 1)).assertEqual('wrangling…');
    });
    it('越界 index 取模回绕到首词', 0, () => {
      expect(pickVibingMessage(VIBING_MESSAGES.length)).assertEqual('accomplishing…');
    });
    it('负 index 归一化（-1 → 末词）', 0, () => {
      expect(pickVibingMessage(-1)).assertEqual('wrangling…');
    });
  });

  describe('resolveStatusBarState — offline（最高优先级）', () => {
    it('设备离线 → offline（灰 #999999），压制其余信号', 0, () => {
      const s = resolveStatusBarState(false, false, true, true, 0);
      expect(s.kind).assertEqual('offline');
      expect(s.color).assertEqual('#999999');
      expect(s.label).assertEqual('离线');
    });
    it('设备在线但 SSE 未 open → offline', 0, () => {
      const s = resolveStatusBarState(true, false, false, false, 0);
      expect(s.kind).assertEqual('offline');
    });
  });

  describe('resolveStatusBarState — permission（次优先级）', () => {
    it('有 pending 权限 → permission（橙 #FF9500），压过 thinking', 0, () => {
      const s = resolveStatusBarState(true, true, true, true, 0);
      expect(s.kind).assertEqual('permission');
      expect(s.color).assertEqual('#FF9500');
      expect(s.label).assertEqual('需要权限');
    });
    it('有 pending 权限 + 非思考 → permission', 0, () => {
      const s = resolveStatusBarState(true, true, true, false, 0);
      expect(s.kind).assertEqual('permission');
    });
  });

  describe('resolveStatusBarState — thinking / online', () => {
    it('思考中 → thinking（蓝 #007AFF）+ 随机 vibing 动词', 0, () => {
      const s = resolveStatusBarState(true, true, false, true, 5);
      expect(s.kind).assertEqual('thinking');
      expect(s.color).assertEqual('#007AFF');
      expect(s.label).assertEqual(pickVibingMessage(5));
    });
    it('空闲 → online（绿 #34C759）', 0, () => {
      const s = resolveStatusBarState(true, true, false, false, 0);
      expect(s.kind).assertEqual('online');
      expect(s.color).assertEqual('#34C759');
      expect(s.label).assertEqual('在线');
    });
  });
}
