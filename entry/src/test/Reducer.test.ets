// Reducer 纯逻辑单测 —— 对照 web/src/chat/reducer.test.ts
//
// 重要差异：上游 reducer.test.ts 全部围绕 goal / token-usage（latestGoal / latestUsage），
// 而 ArkTS 端 Reducer.ets 是 MVP——明确「event 消息不渲染」、不维护 goal/usage（见文件头注释）。
// 因此上游那些 goal/usage 用例在 ArkTS 端无可测对象，此处不照搬；
// 改为针对 ArkTS reducer 实际实现的状态机移植/补全用例：
//   - user / agent 文本块、reasoning 思考块产出（非空）、event 跳过
//   - tool-call → running；tool-result 到达合并为 completed / error
//   - 孤儿权限卡：pending / approved / denied / canceled / 未知状态归一
//   - 分页（早于最旧消息的权限不显示）、顺序保序、空输入

import { describe, it, expect } from '@ohos/hypium';
import { reduceChatBlocks, applyTurnDuration, foldApiErrorEvents, dedupeAgentEvents } from '../main/ets/chat/Reducer';
import { ChatBlock, ChatToolCall } from '../main/ets/chat/ChatBlock';
import { ChatMessage } from '../main/ets/models/Message';
import { NormalizedAgentContent } from '../main/ets/chat/NormalizedContent';
import { AgentState, AgentStateRequest, AgentStateCompletedRequest } from '../main/ets/chat/AgentState';
import { AgentEvent } from '../main/ets/models/Types';

// —— 消息 / 内容块构造器（对齐 models，避免每个用例重复样板）——

function userMsg(id: string, text: string, createdAt: number): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.id = id;
  m.role = 'user';
  m.text = text;
  m.createdAt = createdAt;
  m.status = 'sent';
  return m;
}

function agentMsg(id: string, createdAt: number, blocks: NormalizedAgentContent[]): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.id = id;
  m.role = 'agent';
  m.createdAt = createdAt;
  m.status = 'sent';
  m.blocks = blocks;
  return m;
}

function eventMsg(id: string, createdAt: number): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.id = id;
  m.role = 'event';
  m.createdAt = createdAt;
  m.status = 'sent';
  return m;
}

// turn-duration event（role='event' + 携带耗时/目标 id；对照 normalizeAgent.ts:473 system/turn_duration）。
function turnDurationEvent(id: string, createdAt: number, targetId: string, durationMs: number): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.id = id;
  m.role = 'event';
  m.createdAt = createdAt;
  m.status = 'sent';
  m.turnDurationMs = durationMs;
  m.turnDurationTargetId = targetId;
  return m;
}

function textBlock(text: string): NormalizedAgentContent {
  const b: NormalizedAgentContent = new NormalizedAgentContent();
  b.type = 'text';
  b.text = text;
  return b;
}

function reasoningBlock(text: string): NormalizedAgentContent {
  const b: NormalizedAgentContent = new NormalizedAgentContent();
  b.type = 'reasoning';
  b.text = text;
  return b;
}

function reasoningStreamBlock(text: string, streamId: string): NormalizedAgentContent {
  const b: NormalizedAgentContent = new NormalizedAgentContent();
  b.type = 'reasoning';
  b.text = text;
  b.streamId = streamId;
  return b;
}

function summaryBlock(summary: string): NormalizedAgentContent {
  const b: NormalizedAgentContent = new NormalizedAgentContent();
  b.type = 'summary';
  b.summary = summary;
  return b;
}

function toolCall(id: string, name: string): NormalizedAgentContent {
  const b: NormalizedAgentContent = new NormalizedAgentContent();
  b.type = 'tool-call';
  b.id = id;
  b.name = name;
  return b;
}

function toolResult(id: string, isError: boolean, content: Object): NormalizedAgentContent {
  const b: NormalizedAgentContent = new NormalizedAgentContent();
  b.type = 'tool-result';
  b.id = id;
  b.isError = isError;
  b.content = content;
  return b;
}

function generatedImageBlock(imageId: string, fileName: string, mimeType: string): NormalizedAgentContent {
  const b: NormalizedAgentContent = new NormalizedAgentContent();
  b.type = 'generated-image';
  b.imageId = imageId;
  b.fileName = fileName;
  b.mimeType = mimeType;
  return b;
}

// —— AgentState 构造器 ——

function stateWithPending(id: string, tool: string, createdAt: number): AgentState {
  const s: AgentState = new AgentState();
  const req: AgentStateRequest = new AgentStateRequest();
  req.tool = tool;
  req.createdAt = createdAt;
  s.requests[id] = req;
  return s;
}

function stateWithCompleted(id: string, tool: string, status: string, reason: string,
  createdAt: number, completedAt: number): AgentState {
  const s: AgentState = new AgentState();
  const c: AgentStateCompletedRequest = new AgentStateCompletedRequest();
  c.tool = tool;
  c.status = status;
  c.reason = reason;
  c.createdAt = createdAt;
  c.completedAt = completedAt;
  s.completedRequests[id] = c;
  return s;
}

// 取 tool-call 块的非空 tool 引用（测试已知是 tool-call 块；为 null 则属实现 bug，直接抛）
function toolOf(block: ChatBlock): ChatToolCall {
  if (block.tool === null) {
    throw new Error('expected a tool-call block, got null tool');
  }
  return block.tool;
}

export default function reducerTest(): void {
  describe('reduceChatBlocks — text rendering', () => {
    it('renders a user text message as a single user-text block', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks([userMsg('u1', 'hello', 100)], null);
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual('user-text');
      expect(blocks[0].id).assertEqual('u1');
      expect(blocks[0].text).assertEqual('hello');
      expect(blocks[0].createdAt).assertEqual(100);
    });

    it('skips user messages with empty text', 0, () => {
      expect(reduceChatBlocks([userMsg('u1', '', 100)], null).length).assertEqual(0);
    });

    it('renders each agent text block as its own agent-text block with a stable id', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks(
        [agentMsg('a1', 100, [textBlock('hello'), textBlock('world')])], null);
      expect(blocks.length).assertEqual(2);
      expect(blocks[0].kind).assertEqual('agent-text');
      expect(blocks[0].id).assertEqual('a1:0');
      expect(blocks[0].text).assertEqual('hello');
      expect(blocks[1].id).assertEqual('a1:1');
      expect(blocks[1].text).assertEqual('world');
    });

    it('skips empty agent text blocks', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks(
        [agentMsg('a1', 100, [textBlock(''), textBlock('ok')])], null);
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].text).assertEqual('ok');
    });

    it('renders reasoning blocks as reasoning blocks (collapsible thinking)', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks(
        [agentMsg('a1', 100, [reasoningBlock('pondering'), textBlock('answer')])], null);
      expect(blocks.length).assertEqual(2);
      expect(blocks[0].kind).assertEqual('reasoning');
      expect(blocks[0].id).assertEqual('a1:0');
      expect(blocks[0].text).assertEqual('pondering');
      expect(blocks[1].kind).assertEqual('agent-text');
      expect(blocks[1].id).assertEqual('a1:1');
      expect(blocks[1].text).assertEqual('answer');
    });

    it('skips empty reasoning blocks', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks(
        [agentMsg('a1', 100, [reasoningBlock(''), textBlock('answer')])], null);
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual('agent-text');
      expect(blocks[0].text).assertEqual('answer');
    });

    it('skips event messages (MVP does not render events)', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks(
        [eventMsg('e1', 100), userMsg('u1', 'hi', 200)], null);
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual('user-text');
    });
  });

  describe('reduceChatBlocks — tool-call / tool-result merging', () => {
    it('renders a tool-call as a running tool block', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks(
        [agentMsg('a1', 100, [toolCall('t1', 'Bash')])], null);
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual('tool-call');
      const tool: ChatToolCall = toolOf(blocks[0]);
      expect(tool.id).assertEqual('t1');
      expect(tool.name).assertEqual('Bash');
      expect(tool.state).assertEqual('running');
      expect(tool.startedAt).assertEqual(100);
    });

    it('carries tool-call input and description onto the tool block', 0, () => {
      const tc: NormalizedAgentContent = toolCall('t1', 'Edit');
      const input: Record<string, Object> = { 'file_path': '/a.txt' };
      tc.input = input;
      tc.description = 'edit file';
      const blocks: ChatBlock[] = reduceChatBlocks([agentMsg('a1', 100, [tc])], null);
      const tool: ChatToolCall = toolOf(blocks[0]);
      expect(tool.description).assertEqual('edit file');
      expect(tool.input !== null).assertTrue();
      if (tool.input !== null) {
        expect(tool.input['file_path']).assertEqual('/a.txt');
      }
    });

    it('merges a tool-call and a successful tool-result into a completed block', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks([
        agentMsg('a1', 100, [toolCall('t1', 'Bash')]),
        agentMsg('a2', 200, [toolResult('t1', false, 'done output')])
      ], null);
      expect(blocks.length).assertEqual(1);
      const tool: ChatToolCall = toolOf(blocks[0]);
      expect(tool.state).assertEqual('completed');
      expect(tool.completedAt).assertEqual(200);
      expect(tool.result).assertEqual('done output');
    });

    it('marks a tool block as error when the result is an error', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks([
        agentMsg('a1', 100, [toolCall('t1', 'Bash')]),
        agentMsg('a2', 200, [toolResult('t1', true, 'boom')])
      ], null);
      const tool: ChatToolCall = toolOf(blocks[0]);
      expect(tool.state).assertEqual('error');
      expect(tool.result).assertEqual('boom');
    });

    it('creates a completed block from a tool-result with no preceding tool-call', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks(
        [agentMsg('a1', 200, [toolResult('t1', false, 'orphan result')])], null);
      expect(blocks.length).assertEqual(1);
      const tool: ChatToolCall = toolOf(blocks[0]);
      expect(tool.state).assertEqual('completed');
      expect(tool.name).assertEqual('Tool'); // 无 tool-call、无 permission → 占位名
      expect(tool.result).assertEqual('orphan result');
    });

    it('flips a tool-call to running even when a pending permission exists for the same id', 0, () => {
      // tool-call 到达即表示工具已发起；pending permission 不应让卡停留在 pending
      const state: AgentState = stateWithPending('t1', 'Bash', 50);
      const blocks: ChatBlock[] = reduceChatBlocks(
        [agentMsg('a1', 100, [toolCall('t1', 'Bash')])], state);
      const tool: ChatToolCall = toolOf(blocks[0]);
      expect(tool.state).assertEqual('running');
      expect(tool.startedAt).assertEqual(100);
    });
  });

  describe('reduceChatBlocks — Codex reasoning streamId merge + summary + plan_update', () => {
    it('merges reasoning deltas sharing a streamId into one block (snapshot-replace)', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks([
        agentMsg('a1', 100, [reasoningStreamBlock('part-1', 'rs1')]),
        agentMsg('a2', 200, [reasoningStreamBlock('part-1 part-2', 'rs1')])
      ], null);
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual('reasoning');
      expect(blocks[0].text).assertEqual('part-1 part-2');
    });

    it('reasoning without streamId stays separate blocks', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks([
        agentMsg('a1', 100, [reasoningBlock('p1')]),
        agentMsg('a2', 200, [reasoningBlock('p2')])
      ], null);
      expect(blocks.length).assertEqual(2);
      expect(blocks[0].text).assertEqual('p1');
      expect(blocks[1].text).assertEqual('p2');
    });

    it('maps a summary block to an agent-event message gray bar', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks(
        [agentMsg('a1', 100, [summaryBlock('compacted summary')])], null);
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual('agent-event');
      expect(blocks[0].event !== null).assertTrue();
      if (blocks[0].event !== null) {
        expect(blocks[0].event.type).assertEqual('message');
        expect(blocks[0].event.message).assertEqual('compacted summary');
      }
    });

    it('merges a synthesized update_plan tool-call + tool-result into one completed block', 0, () => {
      // 模拟 extractAgentBlocks 对 plan_update 的合成产物（同 id codex-plan-state，一条消息内两块）
      const planArr: Object[] = [
        { 'step': 'A', 'status': 'completed' } as Record<string, Object>,
        { 'step': 'B', 'status': 'pending' } as Record<string, Object>
      ];
      const tc: NormalizedAgentContent = new NormalizedAgentContent();
      tc.type = 'tool-call'; tc.id = 'codex-plan-state'; tc.name = 'update_plan';
      tc.input = { 'plan': planArr, 'source': 'codex' } as Record<string, Object>;
      const tr: NormalizedAgentContent = new NormalizedAgentContent();
      tr.type = 'tool-result'; tr.id = 'codex-plan-state'; tr.isError = false;
      tr.content = { 'plan': planArr, 'source': 'codex', 'status': 'updated' } as Record<string, Object>;
      const blocks: ChatBlock[] = reduceChatBlocks([agentMsg('a1', 100, [tc, tr])], null);
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual('tool-call');
      const tool: ChatToolCall = toolOf(blocks[0]);
      expect(tool.id).assertEqual('codex-plan-state');
      expect(tool.name).assertEqual('update_plan');
      expect(tool.state).assertEqual('completed');
    });
  });

  describe('reduceChatBlocks — orphan permission cards', () => {
    it('renders an orphan pending permission as a pending block', 0, () => {
      const state: AgentState = stateWithPending('p1', 'Bash', 500);
      const blocks: ChatBlock[] = reduceChatBlocks([], state);
      expect(blocks.length).assertEqual(1);
      const tool: ChatToolCall = toolOf(blocks[0]);
      expect(tool.id).assertEqual('p1');
      expect(tool.state).assertEqual('pending');
      expect(tool.name).assertEqual('Bash');
      expect(tool.permission !== null).assertTrue();
      if (tool.permission !== null) {
        expect(tool.permission.status).assertEqual('pending');
      }
    });

    it('renders an orphan approved permission as a completed block with an Approved result', 0, () => {
      const state: AgentState = stateWithCompleted('a1', 'Bash', 'approved', '', 500, 600);
      const blocks: ChatBlock[] = reduceChatBlocks([], state);
      const tool: ChatToolCall = toolOf(blocks[0]);
      expect(tool.state).assertEqual('completed');
      expect(tool.result).assertEqual('Approved');
      expect(tool.completedAt).assertEqual(600);
    });

    it('renders an orphan denied permission as an error block carrying the reason', 0, () => {
      const state: AgentState = stateWithCompleted('d1', 'Bash', 'denied', 'not allowed', 500, 600);
      const blocks: ChatBlock[] = reduceChatBlocks([], state);
      const tool: ChatToolCall = toolOf(blocks[0]);
      expect(tool.state).assertEqual('error');
      expect(tool.result !== null).assertTrue();
      if (tool.result !== null) {
        const result: Record<string, Object> = tool.result as Record<string, Object>;
        expect(result['error']).assertEqual('not allowed');
      }
    });

    it('renders an orphan canceled permission as an error block', 0, () => {
      const state: AgentState = stateWithCompleted('c1', 'Bash', 'canceled', '', 500, 600);
      const blocks: ChatBlock[] = reduceChatBlocks([], state);
      const tool: ChatToolCall = toolOf(blocks[0]);
      expect(tool.state).assertEqual('error');
    });

    it('normalizes an unknown completed status to canceled (error)', 0, () => {
      const state: AgentState = stateWithCompleted('u1', 'Bash', 'weird-status', '', 500, 600);
      const blocks: ChatBlock[] = reduceChatBlocks([], state);
      const tool: ChatToolCall = toolOf(blocks[0]);
      expect(tool.state).assertEqual('error'); // 未知 → canceled → error
      expect(tool.permission !== null).assertTrue();
      if (tool.permission !== null) {
        expect(tool.permission.status).assertEqual('canceled');
      }
    });

    it('falls back to the placeholder name Tool when the tool name is missing', 0, () => {
      const state: AgentState = stateWithPending('p1', '', 500); // 空 tool 名
      const blocks: ChatBlock[] = reduceChatBlocks([], state);
      const tool: ChatToolCall = toolOf(blocks[0]);
      expect(tool.name).assertEqual('Tool');
    });
  });

  describe('reduceChatBlocks — pagination, ordering, emptiness', () => {
    it('skips orphan permissions older than the oldest rendered message (pagination)', 0, () => {
      // 视图最旧消息 createdAt=1000；权限 createdAt=500（更早）→ 不显示（分页加载旧消息时再显示）
      const state: AgentState = stateWithPending('old1', 'Bash', 500);
      const blocks: ChatBlock[] = reduceChatBlocks([userMsg('u1', 'hi', 1000)], state);
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual('user-text');
    });

    it('keeps an orphan permission whose createdAt is within the rendered window', 0, () => {
      const state: AgentState = stateWithPending('p1', 'Bash', 1500);
      const blocks: ChatBlock[] = reduceChatBlocks([userMsg('u1', 'hi', 1000)], state);
      expect(blocks.length).assertEqual(2);
      expect(blocks[1].kind).assertEqual('tool-call');
      expect(toolOf(blocks[1]).state).assertEqual('pending');
    });

    it('preserves block order across messages and content blocks', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks([
        userMsg('u1', 'q', 100),
        agentMsg('a1', 200, [textBlock('intro'), toolCall('t1', 'Bash')]),
        agentMsg('a2', 300, [toolResult('t1', false, 'ok'), textBlock('done')])
      ], null);
      // 期望顺序：user-text → agent-text(intro) → tool-call(已合并为 completed) → agent-text(done)
      expect(blocks.length).assertEqual(4);
      expect(blocks[0].kind).assertEqual('user-text');
      expect(blocks[1].kind).assertEqual('agent-text');
      expect(blocks[1].text).assertEqual('intro');
      expect(blocks[2].kind).assertEqual('tool-call');
      expect(toolOf(blocks[2]).state).assertEqual('completed');
      expect(blocks[3].kind).assertEqual('agent-text');
      expect(blocks[3].text).assertEqual('done');
    });

    it('returns an empty array for no messages and a null agentState', 0, () => {
      expect(reduceChatBlocks([], null).length).assertEqual(0);
    });

    it('returns an empty array for no messages and an empty agentState', 0, () => {
      expect(reduceChatBlocks([], new AgentState()).length).assertEqual(0);
    });
  });

  describe('reduceChatBlocks — generated-image', () => {
    // 对照上游 reducerTimeline.ts:741-753：c.type==='generated-image' → kind='generated-image'，
    //   id 同 agent-text 方案 `${msg.id}:${idx}`；imageId/fileName/mimeType 透传。
    it('maps a generated-image block to a generated-image ChatBlock', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks([
        agentMsg('a1', 200, [generatedImageBlock('img1', 'cat.png', 'image/png')])
      ], null);
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual('generated-image');
      expect(blocks[0].id).assertEqual('a1:0');
      expect(blocks[0].createdAt).assertEqual(200);
      expect(blocks[0].imageId).assertEqual('img1');
      expect(blocks[0].fileName).assertEqual('cat.png');
      expect(blocks[0].mimeType).assertEqual('image/png');
    });

    it('skips a generated-image block with empty imageId', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks([
        agentMsg('a1', 200, [generatedImageBlock('', 'x.png', 'image/png')])
      ], null);
      expect(blocks.length).assertEqual(0);
    });

    it('renders generated-image after a text block in the same message, in order', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks([
        agentMsg('a1', 200, [textBlock('intro'), generatedImageBlock('img1', 'a.png', 'image/png')])
      ], null);
      expect(blocks.length).assertEqual(2);
      expect(blocks[0].kind).assertEqual('agent-text');
      expect(blocks[0].text).assertEqual('intro');
      expect(blocks[1].kind).assertEqual('generated-image');
      expect(blocks[1].id).assertEqual('a1:1');   // 第二块 idx=1
    });
  });

  describe('applyTurnDuration — turn 耗时回填（对照 reducerTimeline.ts:443-468）', () => {
    // 直接构造 ChatBlock 测三段匹配优先级（reduceChatBlocks 集成见下）。
    function agentText(id: string): ChatBlock {
      return ChatBlock.agentText(id, 0, 'x', 0, '', null);
    }
    function toolBlock(blockId: string, toolId: string): ChatBlock {
      const b: ChatBlock = new ChatBlock();
      b.kind = 'tool-call';
      b.id = blockId;
      b.tool = new ChatToolCall();
      b.tool.id = toolId;
      return b;
    }

    it('targetId 精确匹配 → 回填该块', 0, () => {
      const blocks: ChatBlock[] = [agentText('m1:0')];
      applyTurnDuration(blocks, 'm1:0', 1500);
      expect(blocks[0].durationMs).assertEqual(1500);
    });
    it('targetId 前缀匹配（id.startsWith(targetId+\\':\\')) → 回填最后一个命中块', 0, () => {
      const blocks: ChatBlock[] = [agentText('m1:0'), agentText('m1:1')];
      applyTurnDuration(blocks, 'm1', 2300);
      expect(blocks[0].durationMs).assertEqual(-1);     // 非最后命中，不动
      expect(blocks[1].durationMs).assertEqual(2300);   // 最后命中块
    });
    it('id 未命中 → tool-call 块按 tool.id 命中回填', 0, () => {
      // b.id='use_1' 不等 'tool_abc'、不以 'tool_abc:' 开头；step1 落空，step2 tool.id 命中。
      const blocks: ChatBlock[] = [toolBlock('use_1', 'tool_abc')];
      applyTurnDuration(blocks, 'tool_abc', 4200);
      expect(blocks[0].durationMs).assertEqual(4200);
    });
    it('targetId 未命中任何块 → 回退到最后一个 duration-target 块', 0, () => {
      const blocks: ChatBlock[] = [agentText('m1:0'), agentText('m1:1')];
      applyTurnDuration(blocks, 'nonexistent', 9000);
      expect(blocks[0].durationMs).assertEqual(-1);
      expect(blocks[1].durationMs).assertEqual(9000);   // 回退到最后一个 target 块
    });
    it('targetId 为空 → 回退到最后一个 duration-target 块', 0, () => {
      const blocks: ChatBlock[] = [agentText('m1:0')];
      applyTurnDuration(blocks, '', 1000);
      expect(blocks[0].durationMs).assertEqual(1000);
    });
    it('无 duration-target 块（仅 user-text）→ 空操作', 0, () => {
      const blocks: ChatBlock[] = [ChatBlock.userText('u1', 0, 'hi')];
      applyTurnDuration(blocks, '', 1000);
      expect(blocks[0].durationMs).assertEqual(-1);     // user-text 不被回填
    });
    it('空块数组 → 空操作（不抛）', 0, () => {
      const blocks: ChatBlock[] = [];
      applyTurnDuration(blocks, 'm1:0', 1500);
      expect(blocks.length).assertEqual(0);
    });
  });

  describe('reduceChatBlocks — turn-duration event 集成', () => {
    it('agent turn 后的 turn-duration event 回填目标 agent-text 块耗时', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks([
        agentMsg('a1', 100, [textBlock('hi')]),
        turnDurationEvent('e1', 200, 'a1:0', 1500)
      ], null);
      expect(blocks.length).assertEqual(1);            // event 不产块
      expect(blocks[0].durationMs).assertEqual(1500);   // 回填到 a1:0
    });
    it('targetId 为空的 event 回填到最后一个 agent-text 块', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks([
        agentMsg('a1', 100, [textBlock('first'), textBlock('last')]),
        turnDurationEvent('e1', 200, '', 3200)
      ], null);
      expect(blocks.length).assertEqual(2);
      expect(blocks[0].durationMs).assertEqual(-1);
      expect(blocks[1].durationMs).assertEqual(3200);
    });
    it('turnDurationMs<0 的普通 event 不回填、不产块', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks([
        agentMsg('a1', 100, [textBlock('hi')]),
        eventMsg('e1', 200)
      ], null);
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].durationMs).assertEqual(-1);     // 默认哨兵，未被改
    });
  });

  // —— agent 事件构造器（#1 / #4）——
  function apiErrorEvent(retryAttempt: number, maxRetries: number): AgentEvent {
    const e: AgentEvent = new AgentEvent();
    e.type = 'api-error';
    e.retryAttempt = retryAttempt;
    e.maxRetries = maxRetries;
    return e;
  }

  function agentEventMsg(id: string, createdAt: number, event: AgentEvent): ChatMessage {
    const m: ChatMessage = new ChatMessage();
    m.id = id;
    m.role = 'event';
    m.createdAt = createdAt;
    m.status = 'sent';
    m.event = event;
    return m;
  }

  describe('reduceChatBlocks — agent 事件块 + 限额嗅探（#1 / #4）', () => {
    it('event 消息携带 api-error → agent-event 块', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks([agentEventMsg('e1', 100, apiErrorEvent(1, 3))], null);
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual('agent-event');
      if (blocks[0].event !== null) {
        expect(blocks[0].event.type).assertEqual('api-error');
      }
    });
    it('agent 限额文本 → agent-event 块（不产 agent-text）', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks(
        [agentMsg('a1', 100, [textBlock('Claude AI usage limit reached|1700000000000|five_hour')])], null);
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual('agent-event');
      if (blocks[0].event !== null) {
        expect(blocks[0].event.type).assertEqual('limit-reached');
      }
    });
    it('普通 agent 文本不误伤 → agent-text', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks([agentMsg('a1', 100, [textBlock('hello')])], null);
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual('agent-text');
    });
    it('连续 api-error event 消息 → fold 收敛为最新（集成）', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks([
        agentEventMsg('e1', 100, apiErrorEvent(1, 3)),
        agentEventMsg('e2', 110, apiErrorEvent(2, 3))
      ], null);
      expect(blocks.length).assertEqual(1);
      if (blocks[0].event !== null) {
        expect(blocks[0].event.retryAttempt).assertEqual(2);
      }
    });
  });

  describe('foldApiErrorEvents — 连续 api-error 留最新', () => {
    it('两连续 api-error → 1（最新）', 0, () => {
      const blocks: ChatBlock[] = [
        ChatBlock.agentEvent('a', 1, apiErrorEvent(1, 3)),
        ChatBlock.agentEvent('b', 2, apiErrorEvent(2, 3))
      ];
      const out: ChatBlock[] = foldApiErrorEvents(blocks);
      expect(out.length).assertEqual(1);
      if (out[0].event !== null) {
        expect(out[0].event.retryAttempt).assertEqual(2);
      }
    });
    it('api-error / 非 event / api-error → 3（非 event 打断）', 0, () => {
      const blocks: ChatBlock[] = [
        ChatBlock.agentEvent('a', 1, apiErrorEvent(1, 3)),
        ChatBlock.agentText('t', 2, 'hi', 0),
        ChatBlock.agentEvent('c', 3, apiErrorEvent(2, 3))
      ];
      expect(foldApiErrorEvents(blocks).length).assertEqual(3);
    });
    it('非 api-error 事件不折叠（microcompact）', 0, () => {
      const mc1: AgentEvent = new AgentEvent(); mc1.type = 'microcompact'; mc1.tokensSaved = 100;
      const mc2: AgentEvent = new AgentEvent(); mc2.type = 'microcompact'; mc2.tokensSaved = 200;
      const blocks: ChatBlock[] = [ChatBlock.agentEvent('a', 1, mc1), ChatBlock.agentEvent('b', 2, mc2)];
      expect(foldApiErrorEvents(blocks).length).assertEqual(2);
    });
  });

  describe('dedupeAgentEvents — 相邻同键去重', () => {
    it('两相邻同 microcompact → 1', 0, () => {
      const mc1: AgentEvent = new AgentEvent(); mc1.type = 'microcompact'; mc1.tokensSaved = 100;
      const mc2: AgentEvent = new AgentEvent(); mc2.type = 'microcompact'; mc2.tokensSaved = 100;
      const blocks: ChatBlock[] = [ChatBlock.agentEvent('a', 1, mc1), ChatBlock.agentEvent('b', 2, mc2)];
      expect(dedupeAgentEvents(blocks).length).assertEqual(1);
    });
    it('相邻不同 microcompact（tokensSaved 异）→ 2', 0, () => {
      const mc1: AgentEvent = new AgentEvent(); mc1.type = 'microcompact'; mc1.tokensSaved = 100;
      const mc2: AgentEvent = new AgentEvent(); mc2.type = 'microcompact'; mc2.tokensSaved = 200;
      const blocks: ChatBlock[] = [ChatBlock.agentEvent('a', 1, mc1), ChatBlock.agentEvent('b', 2, mc2)];
      expect(dedupeAgentEvents(blocks).length).assertEqual(2);
    });
    it('同事件被非 event 块隔开 → 均保留', 0, () => {
      const mc1: AgentEvent = new AgentEvent(); mc1.type = 'microcompact'; mc1.tokensSaved = 100;
      const mc2: AgentEvent = new AgentEvent(); mc2.type = 'microcompact'; mc2.tokensSaved = 100;
      const blocks: ChatBlock[] = [
        ChatBlock.agentEvent('a', 1, mc1),
        ChatBlock.agentText('t', 2, 'hi', 0),
        ChatBlock.agentEvent('c', 3, mc2)
      ];
      expect(dedupeAgentEvents(blocks).length).assertEqual(3);
    });
  });

  // —— Flow A：sidechain 子代理 children（Reducer 重构 + 递归 reduce 回归）——
  describe('reduceChatBlocks — sidechain 子代理 children（Flow A）', () => {
    it('Task 工具卡 children 含子代理 text（sidechain 归组 → 递归 reduce）', 0, () => {
      // Task 发起（input.prompt）+ sidechain 根（prompt 匹配）+ 子代理 text 块
      const tc: NormalizedAgentContent = toolCall('t1', 'Task');
      const input: Record<string, Object> = {};
      input['prompt'] = 'sub task';
      tc.input = input;
      const root: ChatMessage = new ChatMessage();
      root.id = 's-root'; root.role = 'agent'; root.createdAt = 200; root.status = 'sent';
      root.isSidechain = true; root.uuid = 'su1'; root.sidechainPrompt = 'sub task'; root.blocks = [];
      const child: ChatMessage = new ChatMessage();
      child.id = 's-child'; child.role = 'agent'; child.createdAt = 300; child.status = 'sent';
      child.isSidechain = true; child.uuid = 'su2'; child.parentUuid = 'su1';
      child.blocks = [textBlock('subagent result')];
      const blocks: ChatBlock[] = reduceChatBlocks([
        agentMsg('m-task', 100, [tc]),
        root,
        child
      ], null);
      // 主时间线仅 Task 工具卡（sidechain 已归组进 children，不漏入主时间线）
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual('tool-call');
      // Task 卡 children：根 marker 无 block，子的 text → 1 个 agent-text
      expect(blocks[0].children.length).assertEqual(1);
      expect(blocks[0].children[0].kind).assertEqual('agent-text');
      expect(blocks[0].children[0].text).assertEqual('subagent result');
    });

    it('无 sidechain → 普通 tool-call 卡 children 为空（重构回归）', 0, () => {
      const blocks: ChatBlock[] = reduceChatBlocks(
        [agentMsg('a1', 100, [toolCall('t1', 'Bash')])], null);
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].children.length).assertEqual(0);
    });
  });
}
