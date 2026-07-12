// AgentState 纯逻辑单测 —— 对照 shared/src/schemas.ts AgentStateSchema
// 覆盖 parseAgentState（null / 空对象 / controlledByUser / requests / completedRequests
//   含 allowTools+answers+arguments / 非对象字段被忽略）与 isEmpty getter。
// 注意：Reducer.test 已从消费侧间接覆盖 getPermissions；此处直测解析入口。

import { describe, it, expect } from '@ohos/hypium';
import { parseAgentState, AgentState, AgentStateRequest, AgentStateCompletedRequest } from '../main/ets/chat/AgentState';

function rec(json: string): Record<string, Object> {
  return JSON.parse(json) as Record<string, Object>;
}

// 取 requests/completedRequests 中某 id 的键集合（避免直接索引 Record 缺键的类型问题）
function keysOf(map: Record<string, Object>): string[] {
  return Object.keys(map);
}

export default function agentStateTest(): void {
  describe('parseAgentState — emptiness', () => {
    it('returns an empty state for null', 0, () => {
      const s: AgentState = parseAgentState(null);
      expect(s.isEmpty).assertTrue();
    });
    it('returns an empty state for an empty object', 0, () => {
      const s: AgentState = parseAgentState(rec('{}'));
      expect(s.isEmpty).assertTrue();
      expect(s.controlledByUser).assertEqual(false);
    });
    it('is not empty when controlledByUser is true', 0, () => {
      const s: AgentState = parseAgentState(rec('{"controlledByUser":true}'));
      expect(s.controlledByUser).assertTrue();
      expect(s.isEmpty).assertFalse();
    });
  });

  describe('parseAgentState — requests', () => {
    it('parses a pending request with tool, arguments and createdAt', 0, () => {
      const s: AgentState = parseAgentState(rec('{"requests":{"p1":{"tool":"Bash","arguments":{"cmd":"ls"},"createdAt":100}}}'));
      expect(s.isEmpty).assertFalse();
      expect(keysOf(s.requests).length).assertEqual(1);
      expect(keysOf(s.requests)[0]).assertEqual('p1');
      const req = s.requests['p1'];
      expect(req.tool).assertEqual('Bash');
      expect(req.createdAt).assertEqual(100);
      expect(req.arguments !== null).assertTrue();
    });
    it('ignores a non-object request entry', 0, () => {
      const s: AgentState = parseAgentState(rec('{"requests":{"p1":"oops","p2":{"tool":"Edit"}}}'));
      expect(keysOf(s.requests).length).assertEqual(1);
      expect(keysOf(s.requests)[0]).assertEqual('p2');
    });
  });

  describe('parseAgentState — completedRequests', () => {
    it('parses status, reason, mode, decision and timestamps', 0, () => {
      const s: AgentState = parseAgentState(rec(
        '{"completedRequests":{"c1":{"tool":"Bash","status":"approved","reason":"","mode":"whitelist","decision":"approved_for_session","createdAt":1,"completedAt":2}}}'));
      expect(keysOf(s.completedRequests).length).assertEqual(1);
      const c = s.completedRequests['c1'];
      expect(c.tool).assertEqual('Bash');
      expect(c.status).assertEqual('approved');
      expect(c.mode).assertEqual('whitelist');
      expect(c.decision).assertEqual('approved_for_session');
      expect(c.createdAt).assertEqual(1);
      expect(c.completedAt).assertEqual(2);
    });
    it('parses allowTools string array and filters non-strings', 0, () => {
      const s: AgentState = parseAgentState(rec(
        '{"completedRequests":{"c1":{"tool":"Bash","status":"approved","allowTools":["X","Y",123]}}}'));
      const c = s.completedRequests['c1'];
      expect(c.allowTools.length).assertEqual(2);
      expect(c.allowTools[0]).assertEqual('X');
      expect(c.allowTools[1]).assertEqual('Y');
    });
    it('parses answers as a passthrough object', 0, () => {
      const s: AgentState = parseAgentState(rec(
        '{"completedRequests":{"c1":{"tool":"AskUserQuestion","status":"approved","answers":{"0":["optA"]}}}}'));
      const c = s.completedRequests['c1'];
      expect(c.answers !== null).assertTrue();
      if (c.answers !== null) {
        expect(c.answers['0'] !== undefined).assertTrue();
      }
    });
    it('is not empty when only a completed request is present', 0, () => {
      const s: AgentState = parseAgentState(rec('{"completedRequests":{"c1":{"tool":"Bash","status":"denied"}}}'));
      expect(s.isEmpty).assertFalse();
    });
  });

  describe('AgentState.isEmpty', () => {
    it('is false when a request is present', 0, () => {
      const s: AgentState = new AgentState();
      expect(s.isEmpty).assertTrue();
      const req: AgentStateRequest = new AgentStateRequest();
      req.tool = 'Bash';
      s.requests['x'] = req;
      expect(s.isEmpty).assertFalse();
    });
    it('is false when a completed request is present', 0, () => {
      const s: AgentState = new AgentState();
      s.completedRequests['y'] = new AgentStateCompletedRequest();
      expect(s.isEmpty).assertFalse();
    });
    it('is false when controlledByUser is true', 0, () => {
      const s: AgentState = new AgentState();
      s.controlledByUser = true;
      expect(s.isEmpty).assertFalse();
    });
  });
}
