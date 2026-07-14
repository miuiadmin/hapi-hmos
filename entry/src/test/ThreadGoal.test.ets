// ThreadGoal 单测 —— 顶部状态行 goal chip 的解析管线纯逻辑（零 @kit，LocalUnit 可加载）。
//   对照 web/src/chat/reducer.ts:36-58 getLatestThreadGoal。覆盖：无 goal→null；
//   updated→返 goal；cleared→null；complete + 其后非 /goal user→null（抑制）；
//   complete + 其后仅 /goal user→返 goal；active/paused/budgetLimited 不被普通 user 清掉；
//   /goal 命令不置 sawNewer；未触发定时 user 不计入活动；纯 event（goal===null）继续反向。

import { describe, it, expect } from '@ohos/hypium';
import { ChatMessage } from '../main/ets/models/Message';
import { ThreadGoal } from '../main/ets/models/Types';
import { getLatestThreadGoal } from '../main/ets/chat/ThreadGoal';

function mkGoal(status: string): ThreadGoal {
  const g: ThreadGoal = new ThreadGoal();
  g.threadId = 't1';
  g.objective = 'ship it';
  g.status = status;
  return g;
}

function mkUser(text: string, scheduledAt: number = 0, invokedAt: number = 0): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = 'user';
  m.text = text;
  m.scheduledAt = scheduledAt;
  m.invokedAt = invokedAt;
  return m;
}

function mkGoalEvent(goal: ThreadGoal): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = 'event';
  m.goal = goal;
  return m;
}

function mkClearedEvent(): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = 'event';
  m.goalCleared = true;
  return m;
}

// role:'event' 但 goal===null 且非 cleared（如 token_count 用量事件）—— 不应阻断反向遍历。
function mkBareEvent(): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.role = 'event';
  return m;
}

export default function threadGoalTest(): void {
  describe('ThreadGoal — getLatestThreadGoal', () => {
    it('空列表 → null', 0, () => {
      expect(getLatestThreadGoal([])).assertNull();
    });
    it('无 goal/cleared 事件 → null', 0, () => {
      expect(getLatestThreadGoal([mkUser('hi'), mkUser('hello')])).assertNull();
    });
    it('最新 goal-updated（active）→ 返该 goal', 0, () => {
      const r = getLatestThreadGoal([mkGoalEvent(mkGoal('active')), mkUser('/goal ship it')]);
      expect(r).assertNotNull();
      expect(r!.status).assertEqual('active');
      expect(r!.objective).assertEqual('ship it');
    });
    it('goal-updated 后再 cleared → null', 0, () => {
      const r = getLatestThreadGoal([mkGoalEvent(mkGoal('active')), mkClearedEvent()]);
      expect(r).assertNull();
    });
    it('cleared 后又 updated → 返新 goal（反向遇 updated 先于 cleared）', 0, () => {
      const r = getLatestThreadGoal([mkClearedEvent(), mkGoalEvent(mkGoal('active'))]);
      expect(r).assertNotNull();
      expect(r!.status).assertEqual('active');
    });
    it('complete + 其后有普通非 /goal user 消息 → null（抑制）', 0, () => {
      const r = getLatestThreadGoal([mkGoalEvent(mkGoal('complete')), mkUser('继续干活')]);
      expect(r).assertNull();
    });
    it('complete + 其后仅 /goal 命令 user 消息 → 返 goal（/goal 不置 sawNewer）', 0, () => {
      const r = getLatestThreadGoal([mkGoalEvent(mkGoal('complete')), mkUser('/goal check status')]);
      expect(r).assertNotNull();
      expect(r!.status).assertEqual('complete');
    });
    it('active goal 不被其后的普通 user 消息清掉（仅 complete 才抑制）', 0, () => {
      const r = getLatestThreadGoal([mkGoalEvent(mkGoal('active')), mkUser('随便说点')]);
      expect(r).assertNotNull();
      expect(r!.status).assertEqual('active');
    });
    it('paused / budgetLimited 不被普通 user 消息清掉', 0, () => {
      let r = getLatestThreadGoal([mkGoalEvent(mkGoal('paused')), mkUser('继续')]);
      expect(r).assertNotNull();
      expect(r!.status).assertEqual('paused');
      r = getLatestThreadGoal([mkGoalEvent(mkGoal('budgetLimited')), mkUser('继续')]);
      expect(r).assertNotNull();
      expect(r!.status).assertEqual('budgetLimited');
    });
    it('未触发定时 user 消息不计入活动（complete 仍返回，不被定时消息抑制）', 0, () => {
      const r = getLatestThreadGoal([mkGoalEvent(mkGoal('complete')), mkUser('定时的话', 1000, 0)]);
      expect(r).assertNotNull();
      expect(r!.status).assertEqual('complete');
    });
    it('bare event（goal===null、非 cleared）→ 不阻断反向，继续找更早 goal', 0, () => {
      const r = getLatestThreadGoal([mkGoalEvent(mkGoal('active')), mkBareEvent()]);
      expect(r).assertNotNull();
      expect(r!.status).assertEqual('active');
    });
  });

  describe('ThreadGoal — /goal 斜杠命令判定（经 complete 抑制间接验证）', () => {
    // complete goal 后跟该 user 文本：判为 /goal 命令 → sawNewer 不置 → 返 goal；
    //   非命令 → 置 sawNewer → 返 null。上游正则 /^\s*\/goal(?:\s|$)/i。
    it('/goal、/goal ship it、/GOAL、前导空白 → 判为 goal 命令', 0, () => {
      expect(getLatestThreadGoal([mkGoalEvent(mkGoal('complete')), mkUser('/goal')])).assertNotNull();
      expect(getLatestThreadGoal([mkGoalEvent(mkGoal('complete')), mkUser('/goal ship it')])).assertNotNull();
      expect(getLatestThreadGoal([mkGoalEvent(mkGoal('complete')), mkUser('/GOAL')])).assertNotNull();
      expect(getLatestThreadGoal([mkGoalEvent(mkGoal('complete')), mkUser('  /goal')])).assertNotNull();
    });
    it('/goals、/goal-x、/goalx、非 / 开头、/goal 不在开头 → 非命令（抑制）', 0, () => {
      expect(getLatestThreadGoal([mkGoalEvent(mkGoal('complete')), mkUser('/goals')])).assertNull();
      expect(getLatestThreadGoal([mkGoalEvent(mkGoal('complete')), mkUser('/goal-x')])).assertNull();
      expect(getLatestThreadGoal([mkGoalEvent(mkGoal('complete')), mkUser('/goalx')])).assertNull();
      expect(getLatestThreadGoal([mkGoalEvent(mkGoal('complete')), mkUser('goal')])).assertNull();
      expect(getLatestThreadGoal([mkGoalEvent(mkGoal('complete')), mkUser('看看 /goal')])).assertNull();
    });
  });
}
