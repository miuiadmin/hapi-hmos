// SessionAttention 纯逻辑单测 —— 会话注意力分级（对照 web lib/sessionAttention.ts classifySessionAttention）
//
// 覆盖优先级链：selected/thinking→null ＞ permission ＞ input ＞ active+后台 ＞ unread ＞ null。

import { describe, it, expect } from '@ohos/hypium';
import { classifySessionAttention } from '../main/ets/services/SessionAttention';
import { SessionSummary } from '../main/ets/models/Types';

// 最小可用会话快照（默认无任何注意力信号）
function fresh(): SessionSummary {
  const s = new SessionSummary();
  s.id = 's1';
  s.active = false;
  s.thinking = false;
  s.updatedAt = 1000;
  s.backgroundTaskCount = 0;
  s.pendingRequestKinds = [];
  return s;
}

export default function sessionAttentionTest(): void {
  describe('classifySessionAttention — 抑制', () => {
    it('thinking → null（即使有待审批）', 0, () => {
      const s = fresh();
      s.thinking = true;
      s.pendingRequestKinds = ['permission'];
      expect(classifySessionAttention(s, false, 0)).assertNull();
    });
    it('selected → null（即使有待审批）', 0, () => {
      const s = fresh();
      s.pendingRequestKinds = ['permission'];
      expect(classifySessionAttention(s, true, 0)).assertNull();
    });
    it('无任何信号 → null', 0, () => {
      expect(classifySessionAttention(fresh(), false, 9999)).assertNull();
    });
  });

  describe('classifySessionAttention — 分级', () => {
    it('permission 优先（含 permission 即琥珀）', 0, () => {
      const s = fresh();
      s.pendingRequestKinds = ['permission', 'input'];
      expect(classifySessionAttention(s, false, 0)).assertEqual('permission');
    });
    it('仅 input → input', 0, () => {
      const s = fresh();
      s.pendingRequestKinds = ['input'];
      expect(classifySessionAttention(s, false, 0)).assertEqual('input');
    });
    it('active + 后台任务 → background（无待审批时）', 0, () => {
      const s = fresh();
      s.active = true;
      s.backgroundTaskCount = 3;
      expect(classifySessionAttention(s, false, 0)).assertEqual('background');
    });
    it('后台但非 active → 不算 background（落为 unread/null）', 0, () => {
      const s = fresh();
      s.active = false;
      s.backgroundTaskCount = 3;
      s.updatedAt = 100;
      expect(classifySessionAttention(s, false, 200)).assertNull();   // 非活跃且已看
    });
    it('permission 优先于 background（即便后台跑着）', 0, () => {
      const s = fresh();
      s.active = true;
      s.backgroundTaskCount = 5;
      s.pendingRequestKinds = ['permission'];
      expect(classifySessionAttention(s, false, 0)).assertEqual('permission');
    });
    it('updatedAt > lastSeenAt → unread（无更高优先级时）', 0, () => {
      const s = fresh();
      s.updatedAt = 5000;
      expect(classifySessionAttention(s, false, 1000)).assertEqual('unread');
    });
    it('updatedAt <= lastSeenAt → null（已看，无新活动）', 0, () => {
      const s = fresh();
      s.updatedAt = 1000;
      expect(classifySessionAttention(s, false, 1000)).assertNull();
      expect(classifySessionAttention(s, false, 2000)).assertNull();
    });
  });
}
