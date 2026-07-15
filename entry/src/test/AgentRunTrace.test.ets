// AgentRunTrace 纯逻辑单测 —— 对照 web/src/chat/reducerTimeline.ts（agent-run 段 + normalizeTraceMessage）
// 零 @kit：仅 import 被测纯层（chat/AgentRunTrace）+ 模型（ChatBlock/ChatToolCall、Message、NormalizedContent）。
//   覆盖：id 前缀、status→ToolState 映射、cardId 解析/fallback、显示 patch、指纹、孤儿/噪声判定、trace 展开。

import { describe, it, expect } from '@ohos/hypium';
import {
  prefixAgentTraceId,
  mapAgentRunStatusToToolState,
  isTerminalAgentRunState,
  isNonTerminalAgentRunState,
  getAgentRunCardId,
  isFallbackAgentRunCardId,
  getAgentRunStartedAt,
  getAgentRunCompletedAt,
  getAgentRunDisplayPatch,
  getAgentRunFingerprint,
  isAgentNotFoundUpdate,
  isAgentToolOnlyUpdate,
  isCloseAgentCleanupUpdate,
  shouldIgnoreAgentRunNonTerminalUpdateAfterTerminal,
  shouldIgnoreAgentRunCloseCleanupAfterTerminal,
  isOrphanAgentRunBlock,
  normalizeTraceMessage
} from '../main/ets/chat/AgentRunTrace';
import { ChatBlock, ChatToolCall } from '../main/ets/chat/ChatBlock';
import { ChatMessage } from '../main/ets/models/Message';
import { NormalizedAgentContent } from '../main/ets/chat/NormalizedContent';

// 构造一个 tool-call ChatBlock（给定 state/input/result/children），供孤儿/噪声判定测。
function toolCallBlock(state: string, input: Record<string, Object> | null,
  result: Object | null, childrenLen: number): ChatBlock {
  const b: ChatBlock = new ChatBlock();
  b.kind = 'tool-call';
  b.id = 'card1';
  const tool: ChatToolCall = new ChatToolCall();
  tool.id = 'card1';
  tool.name = 'CodexAgent';
  tool.state = state;
  tool.input = input;
  tool.result = result;
  b.tool = tool;
  // children 默认 []；测试按需塞占位块凑长度
  for (let i = 0; i < childrenLen; i++) {
    b.children.push(new ChatBlock());
  }
  return b;
}

function ev(data: Record<string, Object>): Record<string, Object> {
  return data;
}

export default function agentRunTraceTest(): void {
  describe('prefixAgentTraceId', () => {
    it('加 `codex-agent:${agentId}:${kind}:` 前缀', 0, () => {
      expect(prefixAgentTraceId('A', 'trace', 'tr1')).assertEqual('codex-agent:A:trace:tr1');
      expect(prefixAgentTraceId('A', 'call', 'c1')).assertEqual('codex-agent:A:call:c1');
    });
    it('已带前缀 → 原样返回（幂等）', 0, () => {
      expect(prefixAgentTraceId('A', 'trace', 'codex-agent:A:trace:tr1')).assertEqual('codex-agent:A:trace:tr1');
    });
  });

  describe('mapAgentRunStatusToToolState', () => {
    it('completed → completed', 0, () => {
      expect(mapAgentRunStatusToToolState('completed')).assertEqual('completed');
    });
    it('failed/error/canceled/cancelled/notFound/not_found → error', 0, () => {
      expect(mapAgentRunStatusToToolState('failed')).assertEqual('error');
      expect(mapAgentRunStatusToToolState('error')).assertEqual('error');
      expect(mapAgentRunStatusToToolState('canceled')).assertEqual('error');
      expect(mapAgentRunStatusToToolState('cancelled')).assertEqual('error');
      expect(mapAgentRunStatusToToolState('notFound')).assertEqual('error');
      expect(mapAgentRunStatusToToolState('not_found')).assertEqual('error');
    });
    it('pending → pending', 0, () => {
      expect(mapAgentRunStatusToToolState('pending')).assertEqual('pending');
    });
    it('缺省 / running / 未知 → running', 0, () => {
      expect(mapAgentRunStatusToToolState('')).assertEqual('running');
      expect(mapAgentRunStatusToToolState('running')).assertEqual('running');
      expect(mapAgentRunStatusToToolState('weird')).assertEqual('running');
    });
  });

  describe('isTerminal / isNonTerminal agent-run state', () => {
    it('终态：completed / error', 0, () => {
      expect(isTerminalAgentRunState('completed')).assertTrue();
      expect(isTerminalAgentRunState('error')).assertTrue();
      expect(isTerminalAgentRunState('running')).assertFalse();
    });
    it('非终态：running / pending', 0, () => {
      expect(isNonTerminalAgentRunState('running')).assertTrue();
      expect(isNonTerminalAgentRunState('pending')).assertTrue();
      expect(isNonTerminalAgentRunState('completed')).assertFalse();
    });
  });

  describe('getAgentRunCardId / isFallbackAgentRunCardId', () => {
    it('cardId 命中 → 原值（camel/snake 双读）', 0, () => {
      expect(getAgentRunCardId(ev({ 'cardId': 'C1' }), 'fb')).assertEqual('C1');
      expect(getAgentRunCardId(ev({ 'card_id': 'C2' }), 'fb')).assertEqual('C2');
    });
    it('cardId 缺 → fallback', 0, () => {
      expect(getAgentRunCardId(ev({}), 'fb')).assertEqual('fb');
    });
    it('fallback 判定：cardId === `codex-agent:${agentId}`', 0, () => {
      expect(isFallbackAgentRunCardId('codex-agent:A', 'A')).assertTrue();
      expect(isFallbackAgentRunCardId('named-1', 'A')).assertFalse();
      expect(isFallbackAgentRunCardId('codex-agent:A', '')).assertFalse(); // 无 agentId 恒非 fallback
    });
  });

  describe('getAgentRunStartedAt / CompletedAt', () => {
    it('camel 优先，snake 次之，缺省 0', 0, () => {
      expect(getAgentRunStartedAt(ev({ 'startedAt': 100 }))).assertEqual(100);
      expect(getAgentRunStartedAt(ev({ 'started_at': 200 }))).assertEqual(200);
      expect(getAgentRunStartedAt(ev({}))).assertEqual(0);
      expect(getAgentRunCompletedAt(ev({ 'completedAt': 300 }))).assertEqual(300);
      expect(getAgentRunCompletedAt(ev({ 'completed_at': 400 }))).assertEqual(400);
    });
  });

  describe('getAgentRunDisplayPatch', () => {
    it('仅透传非空字段', 0, () => {
      const patch: Record<string, Object> = getAgentRunDisplayPatch(
        ev({ 'summary': 's1', 'activity': '', 'activityKind': 'running' }));
      expect(patch['summary']).assertEqual('s1');
      expect(patch['activityKind']).assertEqual('running');
      expect(patch['activity'] === undefined).assertTrue();
    });
    it('皆空 → 空 patch', 0, () => {
      expect(Object.keys(getAgentRunDisplayPatch(ev({}))).length).assertEqual(0);
    });
  });

  describe('getAgentRunFingerprint', () => {
    it('summary 优先（原样，不压缩）', 0, () => {
      expect(getAgentRunFingerprint(ev({ 'summary': 'my summary' }))).assertEqual('my summary');
    });
    it('无 summary → input.message（压缩空白）', 0, () => {
      const input: Record<string, Object> = { 'message': '  hello   world  ' } as Record<string, Object>;
      expect(getAgentRunFingerprint(ev({ 'input': input }))).assertEqual('hello world');
    });
    it('无 summary/message → input.prompt', 0, () => {
      const input: Record<string, Object> = { 'prompt': 'do\tit' } as Record<string, Object>;
      expect(getAgentRunFingerprint(ev({ 'input': input }))).assertEqual('do it');
    });
    it('无 summary/message/prompt → input.items[].text join \\n\\n（压缩）', 0, () => {
      const items: Object[] = [
        { 'text': 'a' } as Record<string, Object>,
        { 'text': 'b  c' } as Record<string, Object>
      ];
      const input: Record<string, Object> = { 'items': items } as Record<string, Object>;
      expect(getAgentRunFingerprint(ev({ 'input': input }))).assertEqual('a\n\nb c');
    });
    it('皆缺 → 空', 0, () => {
      expect(getAgentRunFingerprint(ev({}))).assertEqual('');
    });
  });

  describe('isAgentNotFoundUpdate / isAgentToolOnlyUpdate', () => {
    it('notFound 状态或 activityKind → notFound 命中', 0, () => {
      expect(isAgentNotFoundUpdate(ev({ 'status': 'notFound' }))).assertTrue();
      expect(isAgentNotFoundUpdate(ev({ 'status': 'not_found' }))).assertTrue();
      expect(isAgentNotFoundUpdate(ev({ 'activityKind': 'not_found' }))).assertTrue();
      expect(isAgentNotFoundUpdate(ev({ 'status': 'running' }))).assertFalse();
    });
    it('工具型 activityKind（wait/send_input/resume/close/notFound）命中', 0, () => {
      expect(isAgentToolOnlyUpdate(ev({ 'activityKind': 'wait_agent' }))).assertTrue();
      expect(isAgentToolOnlyUpdate(ev({ 'activityKind': 'send_input' }))).assertTrue();
      expect(isAgentToolOnlyUpdate(ev({ 'activityKind': 'resume_agent' }))).assertTrue();
      expect(isAgentToolOnlyUpdate(ev({ 'activityKind': 'close_agent' }))).assertTrue();
      expect(isAgentToolOnlyUpdate(ev({ 'activityKind': 'running' }))).assertFalse();
    });
  });

  describe('isCloseAgentCleanupUpdate', () => {
    it('activityKind close_agent / closed 命中', 0, () => {
      expect(isCloseAgentCleanupUpdate(ev({ 'activityKind': 'close_agent' }))).assertTrue();
      expect(isCloseAgentCleanupUpdate(ev({ 'activityKind': 'closed' }))).assertTrue();
    });
    it('canceled + Closed 文案 + result.previous_status 命中', 0, () => {
      const result: Record<string, Object> = { 'previous_status': { 'state': 'completed' } } as Record<string, Object>;
      expect(isCloseAgentCleanupUpdate(
        ev({ 'activityKind': 'canceled', 'activity': 'Closed', 'result': result }))).assertTrue();
    });
    it('canceled 无 Closed 文案 → 不命中', 0, () => {
      expect(isCloseAgentCleanupUpdate(ev({ 'activityKind': 'canceled', 'activity': 'Running' }))).assertFalse();
    });
  });

  describe('shouldIgnoreAgentRun*AfterTerminal', () => {
    it('终态块 + 非终态下次 + wait_agent → 忽略', 0, () => {
      const block: ChatBlock = toolCallBlock('completed', null, null, 0);
      expect(shouldIgnoreAgentRunNonTerminalUpdateAfterTerminal(
        block, 'running', ev({ 'activityKind': 'wait_agent' }))).assertTrue();
    });
    it('终态块 + 终态下次 → 不忽略（允许终态刷新）', 0, () => {
      const block: ChatBlock = toolCallBlock('completed', null, null, 0);
      expect(shouldIgnoreAgentRunNonTerminalUpdateAfterTerminal(
        block, 'error', ev({ 'activityKind': 'wait_agent' }))).assertFalse();
    });
    it('非终态块 → 不忽略', 0, () => {
      const block: ChatBlock = toolCallBlock('running', null, null, 0);
      expect(shouldIgnoreAgentRunNonTerminalUpdateAfterTerminal(
        block, 'running', ev({ 'activityKind': 'wait_agent' }))).assertFalse();
    });
    it('终态块 + close 清扫 + 非 failed/error status → 忽略', 0, () => {
      const block: ChatBlock = toolCallBlock('completed', null, null, 0);
      expect(shouldIgnoreAgentRunCloseCleanupAfterTerminal(
        block, 'canceled', ev({ 'activityKind': 'close_agent' }))).assertTrue();
    });
    it('终态块 + close 清扫 + failed status → 不忽略', 0, () => {
      const block: ChatBlock = toolCallBlock('completed', null, null, 0);
      expect(shouldIgnoreAgentRunCloseCleanupAfterTerminal(
        block, 'failed', ev({ 'activityKind': 'close_agent' }))).assertFalse();
    });
  });

  describe('isOrphanAgentRunBlock', () => {
    it('有 children → 非孤儿', 0, () => {
      expect(isOrphanAgentRunBlock(toolCallBlock('running', null, null, 1))).assertFalse();
    });
    it('有 result → 非孤儿', 0, () => {
      expect(isOrphanAgentRunBlock(toolCallBlock('running', null, 'done', 0))).assertFalse();
    });
    it('终态 → 非孤儿', 0, () => {
      expect(isOrphanAgentRunBlock(toolCallBlock('completed', null, null, 0))).assertFalse();
    });
    it('input 带 agentId → 非孤儿', 0, () => {
      const input: Record<string, Object> = { 'agentId': 'A' } as Record<string, Object>;
      expect(isOrphanAgentRunBlock(toolCallBlock('running', input, null, 0))).assertFalse();
    });
    it('running + 无 children/result/agentId → 孤儿', 0, () => {
      const input: Record<string, Object> = { 'message': 'x' } as Record<string, Object>;
      expect(isOrphanAgentRunBlock(toolCallBlock('running', input, null, 0))).assertTrue();
    });
    it('tool 为 null → 孤儿', 0, () => {
      const b: ChatBlock = new ChatBlock();
      b.kind = 'tool-call';
      b.tool = null;
      expect(isOrphanAgentRunBlock(b)).assertTrue();
    });
  });

  describe('normalizeTraceMessage', () => {
    it('message（字符串）→ 1 条 agent 消息 + text 块，id 加 trace 前缀', 0, () => {
      const data: Record<string, Object> = {
        'type': 'message', 'id': 'tr1', 'message': 'working'
      } as Record<string, Object>;
      const out: ChatMessage[] = normalizeTraceMessage('A', data, 'src1', 100);
      expect(out.length).assertEqual(1);
      expect(out[0].role).assertEqual('agent');
      expect(out[0].id).assertEqual('codex-agent:A:trace:tr1');
      expect(out[0].createdAt).assertEqual(100);
      expect(out[0].blocks.length).assertEqual(1);
      expect(out[0].blocks[0].type).assertEqual('text');
      expect(out[0].blocks[0].text).assertEqual('working');
    });
    it('data.id 缺 → 用 sourceId:trace 兜底', 0, () => {
      const data: Record<string, Object> = { 'type': 'message', 'message': 'hi' } as Record<string, Object>;
      const out: ChatMessage[] = normalizeTraceMessage('A', data, 'src1', 100);
      expect(out[0].id).assertEqual('codex-agent:A:trace:src1:trace');
    });
    it('reasoning → reasoning 块（streamId=traceId）', 0, () => {
      const data: Record<string, Object> = {
        'type': 'reasoning', 'id': 'tr2', 'message': 'thinking'
      } as Record<string, Object>;
      const out: ChatMessage[] = normalizeTraceMessage('A', data, 'src1', 100);
      expect(out[0].blocks[0].type).assertEqual('reasoning');
      expect(out[0].blocks[0].text).assertEqual('thinking');
      expect(out[0].blocks[0].streamId).assertEqual('codex-agent:A:trace:tr2');
    });
    it('tool-call → tool-call 块（callId 加 call 前缀；name 缺省 unknown）', 0, () => {
      const data: Record<string, Object> = {
        'type': 'tool-call', 'id': 'tr3', 'callId': 'c1', 'name': 'shell',
        'input': { 'command': 'ls' } as Record<string, Object>
      } as Record<string, Object>;
      const out: ChatMessage[] = normalizeTraceMessage('A', data, 'src1', 100);
      const b: NormalizedAgentContent = out[0].blocks[0];
      expect(b.type).assertEqual('tool-call');
      expect(b.id).assertEqual('codex-agent:A:call:c1');
      expect(b.name).assertEqual('shell');
      expect(b.input !== null).assertTrue();
      if (b.input !== null) {
        expect(b.input['command']).assertEqual('ls');
      }
    });
    it('tool-call 无 callId → []（无法配对）', 0, () => {
      const data: Record<string, Object> = { 'type': 'tool-call', 'id': 'tr', 'name': 'x' } as Record<string, Object>;
      expect(normalizeTraceMessage('A', data, 'src1', 100).length).assertEqual(0);
    });
    it('tool-call-result → tool-result 块（同前缀 callId，is_error 透传）', 0, () => {
      const data: Record<string, Object> = {
        'type': 'tool-call-result', 'id': 'tr4', 'callId': 'c1', 'output': 'file.txt', 'is_error': false
      } as Record<string, Object>;
      const out: ChatMessage[] = normalizeTraceMessage('A', data, 'src1', 100);
      const b: NormalizedAgentContent = out[0].blocks[0];
      expect(b.type).assertEqual('tool-result');
      expect(b.id).assertEqual('codex-agent:A:call:c1');
      expect(b.isError).assertFalse();
      expect(b.content).assertEqual('file.txt');
    });
    it('token_count / ready / task_complete / 未知 type → []（端口简化丢弃）', 0, () => {
      const types: string[] = ['token_count', 'ready', 'task_complete', 'mystery'];
      for (let i = 0; i < types.length; i++) {
        const data: Record<string, Object> = { 'type': types[i] } as Record<string, Object>;
        expect(normalizeTraceMessage('A', data, 'src1', 100).length).assertEqual(0);
      }
    });
    it('非对象 message / 无 type → []', 0, () => {
      expect(normalizeTraceMessage('A', null, 'src1', 100).length).assertEqual(0);
      const noType: Record<string, Object> = { 'id': 'x' } as Record<string, Object>;
      expect(normalizeTraceMessage('A', noType, 'src1', 100).length).assertEqual(0);
    });
  });
}
