// SyncResync 单测 —— 前台重同步门控纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 TerminalToolDisplay.test 范式：同步断言。
//   覆盖 RESYNC_THRESHOLD_MS / shouldResync（30s 边界 + lastHideAt=0 永不触发）。
//   注：shouldResync 不自取时间源（now 由调用方传），保持可测。

import { describe, it, expect } from '@ohos/hypium';
import { RESYNC_THRESHOLD_MS, shouldResync } from '../main/ets/chat/SyncResync';

export default function syncResyncTest(): void {
  describe('SyncResync — 常量', () => {
    it('RESYNC_THRESHOLD_MS = 30000（30s）', 0, () => {
      expect(RESYNC_THRESHOLD_MS).assertEqual(30000);
    });
  });

  describe('SyncResync — shouldResync 边界', () => {
    // lastHideAt 固定 100000，now 变化测阈值边界（严格 >）
    const hideAt: number = 100000;
    it('差 29999（< 阈值）→ false', 0, () => {
      expect(shouldResync(hideAt + 29999, hideAt)).assertEqual(false);
    });
    it('差 30000（== 阈值，严格 > 不触发）→ false', 0, () => {
      expect(shouldResync(hideAt + 30000, hideAt)).assertEqual(false);
    });
    it('差 30001（> 阈值）→ true', 0, () => {
      expect(shouldResync(hideAt + 30001, hideAt)).assertEqual(true);
    });
    it('差很大（>1 分钟）→ true', 0, () => {
      expect(shouldResync(hideAt + 120000, hideAt)).assertEqual(true);
    });
    it('now < lastHideAt（时钟回拨 / 负差）→ false', 0, () => {
      expect(shouldResync(hideAt - 5000, hideAt)).assertEqual(false);
    });
  });

  describe('SyncResync — shouldResync lastHideAt=0 永不触发', () => {
    // lastHideAt=0 = 从未切到后台（首次 onForeground）→ 不应触发重同步
    it('lastHideAt=0 + 任意 now → false（未离开过不重同步）', 0, () => {
      expect(shouldResync(999999999, 0)).assertEqual(false);
    });
    it('lastHideAt=0 + now=0 → false', 0, () => {
      expect(shouldResync(0, 0)).assertEqual(false);
    });
  });
}
