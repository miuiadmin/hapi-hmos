// SessionStatus 纯逻辑单测 —— 会话列表四态判定（paseo 语义 → hapi 字段）
//
// 覆盖优先级链（短路，从高到低）：pending ＞ running ＞ unread ＞ idle。
//   pending  : pendingRequestsCount > 0
//   running  : thinking || backgroundTaskCount > 0
//   unread   : updatedAt > lastSeenAt
//   idle     : 其它

import { describe, it, expect } from '@ohos/hypium';
import { classifySessionStatus } from '../main/ets/chat/SessionStatus';
import { SessionSummary } from '../main/ets/models/Types';

// 最小可用会话快照（默认无任何状态信号；updatedAt=1000 便于未读判定）
function fresh(): SessionSummary {
  const s = new SessionSummary();
  s.id = 's1';
  s.thinking = false;
  s.updatedAt = 1000;
  s.backgroundTaskCount = 0;
  s.pendingRequestsCount = 0;
  return s;
}

export default function sessionStatusTest(): void {
  describe('classifySessionStatus — 四态', () => {
    it('pending：待回复数 > 0', 0, () => {
      const s = fresh();
      s.pendingRequestsCount = 2;
      expect(classifySessionStatus(s, 0)).assertEqual('pending');
    });
    it('running：thinking 进行中', 0, () => {
      const s = fresh();
      s.thinking = true;
      expect(classifySessionStatus(s, 0)).assertEqual('running');
    });
    it('running：后台任务进行中', 0, () => {
      const s = fresh();
      s.backgroundTaskCount = 3;
      expect(classifySessionStatus(s, 0)).assertEqual('running');
    });
    it('unread：有新回复未读（updatedAt > lastSeenAt）', 0, () => {
      const s = fresh();
      s.updatedAt = 5000;
      expect(classifySessionStatus(s, 1000)).assertEqual('unread');
    });
    it('idle：无信号', 0, () => {
      const s = fresh();
      expect(classifySessionStatus(s, 1000)).assertEqual('idle');
    });
  });

  describe('classifySessionStatus — 优先级（高优先短路）', () => {
    it('pending ＞ running（待审批时即使 thinking 也算 pending）', 0, () => {
      const s = fresh();
      s.pendingRequestsCount = 1;
      s.thinking = true;
      s.backgroundTaskCount = 5;
      expect(classifySessionStatus(s, 0)).assertEqual('pending');
    });
    it('running ＞ unread（thinking 时即使有新回复也算 running）', 0, () => {
      const s = fresh();
      s.thinking = true;
      s.updatedAt = 9999;
      expect(classifySessionStatus(s, 1000)).assertEqual('running');
    });
    it('updatedAt <= lastSeenAt → idle（已看，无新活动）', 0, () => {
      const s = fresh();
      s.updatedAt = 1000;
      expect(classifySessionStatus(s, 1000)).assertEqual('idle');
      expect(classifySessionStatus(s, 2000)).assertEqual('idle');
    });
  });
}
