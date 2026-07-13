// Message 纯逻辑单测 —— 对照 web/src/chat/normalize.ts + 上游解包/合并语义
// 覆盖 parseMessage（user/agent 信封解包、tool_use/tool_result/thinking 块、role 归一、
//   备用 {message:{role,content}} 信封、空 content）、parseMessagesResponse（seq/createdAt 排序、
//   非法 JSON、非对象过滤）、mergeMessage（id/localId 替换、追加、优先级、仅乐观消息可被 localId 替换）、
//   cloneMessage（浅拷贝）、isQueued getter。

import { describe, it, expect } from '@ohos/hypium';
import {
  ChatMessage,
  parseMessage,
  parseMessagesResponse,
  parseMessagesPageResponse,
  MessagesPage,
  mergeMessage,
  cloneMessage,
  parseUsage,
  normalizeCodexTokenUsage,
  latestVisibleUsage,
  getContextBudgetTokens,
  formatTokenCount,
  sortQueuedMessages,
  formatScheduledIn,
  parseCancelMessageResponse
} from '../main/ets/models/Message';
import { NormalizedAgentContent } from '../main/ets/chat/NormalizedContent';

// —— JSON → ChatMessage 便捷封装 ——
function parse(json: string): ChatMessage {
  return parseMessage(JSON.parse(json) as Record<string, Object>);
}

// agent 信封：把 data 对象包成 {id,createdAt,content:{role:agent,content:{data:<dataJson>}}}
function agentEnv(id: string, dataJson: string): string {
  return `{"id":"${id}","createdAt":100,"content":{"role":"agent","content":{"data":${dataJson}}}}`;
}

// user 信封：{id,seq,createdAt,invokedAt,content:{role:user,content:{text}}}
function userEnv(id: string, text: string, invokedAt: number): string {
  return `{"id":"${id}","seq":1,"createdAt":100,"invokedAt":${invokedAt},` +
    `"content":{"role":"user","content":{"text":"${text}"}}}`;
}

// 手造消息（mergeMessage / cloneMessage / isQueued 用）
function makeMsg(id: string, localId: string, isOptimistic: boolean, text: string): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.id = id;
  m.localId = localId;
  m.isOptimistic = isOptimistic;
  m.text = text;
  m.role = 'user';
  return m;
}

function textBlock(text: string): NormalizedAgentContent {
  const b: NormalizedAgentContent = new NormalizedAgentContent();
  b.type = 'text';
  b.text = text;
  return b;
}

export default function messageTest(): void {
  describe('parseMessage — user envelope', () => {
    it('parses a user message with text and sets status by invokedAt', 0, () => {
      const m: ChatMessage = parse(userEnv('u1', 'hi', 50));
      expect(m.role).assertEqual('user');
      expect(m.id).assertEqual('u1');
      expect(m.seq).assertEqual(1);
      expect(m.createdAt).assertEqual(100);
      expect(m.invokedAt).assertEqual(50);
      expect(m.text).assertEqual('hi');
      expect(m.status).assertEqual('sent'); // invokedAt>0 → sent
    });

    it('marks a not-yet-invoked user message as queued', 0, () => {
      const m: ChatMessage = parse(userEnv('u2', 'queued', 0));
      expect(m.status).assertEqual('queued'); // invokedAt===0 → queued
      expect(m.isQueued).assertTrue();
    });

    it('accepts the alternate {message:{role,content}} envelope', 0, () => {
      const m: ChatMessage = parse('{"id":"u3","content":{"message":{"role":"user","content":{"text":"alt"}}}}');
      expect(m.role).assertEqual('user');
      expect(m.text).assertEqual('alt');
    });
  });

  describe('parseMessage — agent envelope', () => {
    it('parses a single agent text block', 0, () => {
      const m: ChatMessage = parse(agentEnv('a1', '{"message":{"content":[{"type":"text","text":"hello"}]}}'));
      expect(m.role).assertEqual('agent');
      expect(m.text).assertEqual('hello');
      expect(m.blocks.length).assertEqual(1);
      expect(m.blocks[0].type).assertEqual('text');
      expect(m.blocks[0].text).assertEqual('hello');
    });

    it('parses a plain-string message content as one text block', 0, () => {
      const m: ChatMessage = parse(agentEnv('a1', '{"message":{"content":"simple"}}'));
      expect(m.blocks.length).assertEqual(1);
      expect(m.blocks[0].type).assertEqual('text');
      expect(m.blocks[0].text).assertEqual('simple');
    });

    it('parses text + tool_use + tool_result blocks together', 0, () => {
      const m: ChatMessage = parse(agentEnv('a1',
        '{"message":{"content":[' +
        '{"type":"text","text":"t1"},' +
        '{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}},' +
        '{"type":"tool_result","tool_use_id":"t1","content":"done"}' +
        ']}}'));
      expect(m.blocks.length).assertEqual(3);
      expect(m.blocks[0].type).assertEqual('text');
      expect(m.blocks[1].type).assertEqual('tool-call');
      expect(m.blocks[1].id).assertEqual('t1');
      expect(m.blocks[1].name).assertEqual('Bash');
      expect(m.blocks[1].input !== null).assertTrue();
      if (m.blocks[1].input !== null) {
        expect(m.blocks[1].input['command']).assertEqual('ls');
      }
      expect(m.blocks[2].type).assertEqual('tool-result');
      expect(m.blocks[2].id).assertEqual('t1');
      expect(m.blocks[2].isError).assertEqual(false);
      expect(m.blocks[2].content).assertEqual('done');
    });

    it('defaults a tool_use with no name to Tool', 0, () => {
      const m: ChatMessage = parse(agentEnv('a1',
        '{"message":{"content":[{"type":"tool_use","id":"t2"}]}}'));
      expect(m.blocks.length).assertEqual(1);
      expect(m.blocks[0].name).assertEqual('Tool');
    });

    it('skips a tool_use without an id', 0, () => {
      const m: ChatMessage = parse(agentEnv('a1',
        '{"message":{"content":[{"type":"tool_use","name":"Bash"}]}}'));
      expect(m.blocks.length).assertEqual(0);
    });

    it('carries input.description onto a tool-call block', 0, () => {
      const m: ChatMessage = parse(agentEnv('a1',
        '{"message":{"content":[{"type":"tool_use","id":"t3","name":"Edit",' +
        '"input":{"file_path":"/a","description":"editing"}}]}}'));
      expect(m.blocks[0].description).assertEqual('editing');
    });

    it('marks a tool_result with is_error', 0, () => {
      const m: ChatMessage = parse(agentEnv('a1',
        '{"message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"boom"}]}}'));
      expect(m.blocks[0].type).assertEqual('tool-result');
      expect(m.blocks[0].isError).assertTrue();
    });

    it('skips a tool_result without a tool_use_id', 0, () => {
      const m: ChatMessage = parse(agentEnv('a1',
        '{"message":{"content":[{"type":"tool_result","content":"x"}]}}'));
      expect(m.blocks.length).assertEqual(0);
    });

    it('prefers data.toolUseResult over tool_result.content for the result payload', 0, () => {
      const m: ChatMessage = parse(agentEnv('a1',
        '{"message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"fromblock"}]},' +
        '"toolUseResult":"fromtur"}'));
      expect(m.blocks[0].content).assertEqual('fromtur');
    });

    it('maps a thinking block to a reasoning block', 0, () => {
      const m: ChatMessage = parse(agentEnv('a1',
        '{"message":{"content":[{"type":"thinking","thinking":"ponder"}]}}'));
      expect(m.blocks.length).assertEqual(1);
      expect(m.blocks[0].type).assertEqual('reasoning');
      expect(m.blocks[0].text).assertEqual('ponder');
    });
  });

  describe('parseMessage — role normalization & edge cases', () => {
    it('normalizes an unknown role to agent and still parses blocks', 0, () => {
      const m: ChatMessage = parse('{"id":"x","createdAt":1,' +
        '"content":{"role":"system","content":{"data":{"message":{"content":[{"type":"text","text":"ok"}]}}}}}');
      expect(m.role).assertEqual('agent');
      expect(m.blocks.length).assertEqual(1);
      expect(m.blocks[0].text).assertEqual('ok');
    });

    it('parses an event message as non-rendered (empty text, no blocks)', 0, () => {
      const m: ChatMessage = parse('{"id":"e1","createdAt":1,' +
        '"content":{"role":"event","content":{"type":"message","message":"ready"}}}');
      expect(m.role).assertEqual('event');
      expect(m.text).assertEqual('');
      expect(m.blocks.length).assertEqual(0);
    });

    it('falls back to an empty agent message when content is missing', 0, () => {
      const m: ChatMessage = parse('{"id":"x","createdAt":1}');
      expect(m.role).assertEqual('agent');
      expect(m.text).assertEqual('');
      expect(m.blocks.length).assertEqual(0);
    });

    it('produces no blocks when agent content has no data', 0, () => {
      const m: ChatMessage = parse('{"id":"x","createdAt":1,"content":{"role":"agent","content":{"foo":"bar"}}}');
      expect(m.blocks.length).assertEqual(0);
    });
  });

  describe('parseMessagesResponse', () => {
    it('parses a messages array and sorts ascending by seq', 0, () => {
      const json: string = '{"messages":[' +
        '{"id":"b","seq":2,"createdAt":2,"content":{"role":"user","content":{"text":"second"}}},' +
        '{"id":"a","seq":1,"createdAt":1,"content":{"role":"user","content":{"text":"first"}}}' +
        ']}';
      const list: ChatMessage[] = parseMessagesResponse(json);
      expect(list.length).assertEqual(2);
      expect(list[0].id).assertEqual('a');
      expect(list[1].id).assertEqual('b');
    });

    it('falls back to createdAt ordering when seq is 0', 0, () => {
      const json: string = '{"messages":[' +
        '{"id":"b","seq":0,"createdAt":200,"content":{"role":"user","content":{"text":"b"}}},' +
        '{"id":"a","seq":0,"createdAt":100,"content":{"role":"user","content":{"text":"a"}}}' +
        ']}';
      const list: ChatMessage[] = parseMessagesResponse(json);
      expect(list[0].id).assertEqual('a');
      expect(list[1].id).assertEqual('b');
    });

    it('returns an empty array for invalid JSON', 0, () => {
      expect(parseMessagesResponse('not json').length).assertEqual(0);
    });

    it('returns an empty array when messages is missing or not an array', 0, () => {
      expect(parseMessagesResponse('{"foo":1}').length).assertEqual(0);
      expect(parseMessagesResponse('{"messages":"nope"}').length).assertEqual(0);
    });

    it('filters out non-object entries', 0, () => {
      const json: string = '{"messages":["str",123,null,' +
        '{"id":"ok","content":{"role":"user","content":{"text":"x"}}}]}';
      const list: ChatMessage[] = parseMessagesResponse(json);
      expect(list.length).assertEqual(1);
      expect(list[0].id).assertEqual('ok');
    });
  });

  describe('parseMessagesPageResponse', () => {
    it('parses messages (sorted) + page metadata', 0, () => {
      const json: string = '{"messages":[' +
        '{"id":"b","seq":2,"createdAt":2,"content":{"role":"user","content":{"text":"second"}}},' +
        '{"id":"a","seq":1,"createdAt":1,"content":{"role":"user","content":{"text":"first"}}}' +
        '],"page":{"limit":50,"nextBeforeSeq":1,"nextBeforeAt":1,"hasMore":true}}';
      const page: MessagesPage = parseMessagesPageResponse(json);
      expect(page.messages.length).assertEqual(2);
      expect(page.messages[0].id).assertEqual('a');   // 复用 parseMessagesFromRaw：升序
      expect(page.messages[1].id).assertEqual('b');
      expect(page.hasMore).assertTrue();
      expect(page.nextBeforeAt).assertEqual(1);
      expect(page.nextBeforeSeq).assertEqual(1);
    });

    it('reflects hasMore=false and coerces null cursors to 0', 0, () => {
      const json: string = '{"messages":[],' +
        '"page":{"limit":50,"nextBeforeSeq":null,"nextBeforeAt":null,"hasMore":false}}';
      const page: MessagesPage = parseMessagesPageResponse(json);
      expect(page.hasMore).assertFalse();
      expect(page.nextBeforeAt).assertEqual(0);
      expect(page.nextBeforeSeq).assertEqual(0);
    });

    it('defaults to hasMore=false / cursors 0 when page is absent (messages still parsed)', 0, () => {
      const json: string = '{"messages":[' +
        '{"id":"a","seq":1,"createdAt":1,"content":{"role":"user","content":{"text":"x"}}}' +
        ']}';
      const page: MessagesPage = parseMessagesPageResponse(json);
      expect(page.messages.length).assertEqual(1);
      expect(page.hasMore).assertFalse();
      expect(page.nextBeforeAt).assertEqual(0);
      expect(page.nextBeforeSeq).assertEqual(0);
    });

    it('returns an empty page (defaults) for invalid JSON', 0, () => {
      const page: MessagesPage = parseMessagesPageResponse('not json');
      expect(page.messages.length).assertEqual(0);
      expect(page.hasMore).assertFalse();
      expect(page.nextBeforeAt).assertEqual(0);
      expect(page.nextBeforeSeq).assertEqual(0);
    });

    it('parses page metadata even when messages is missing', 0, () => {
      const json: string = '{"page":{"limit":50,"nextBeforeSeq":3,"nextBeforeAt":5,"hasMore":true}}';
      const page: MessagesPage = parseMessagesPageResponse(json);
      expect(page.messages.length).assertEqual(0);
      expect(page.hasMore).assertTrue();
      expect(page.nextBeforeAt).assertEqual(5);
      expect(page.nextBeforeSeq).assertEqual(3);
    });
  });

  describe('mergeMessage', () => {
    it('replaces an existing message with the same id', 0, () => {
      const list: ChatMessage[] = [makeMsg('a', '', false, 'old')];
      const merged: ChatMessage[] = mergeMessage(list, makeMsg('a', '', false, 'new'));
      expect(merged.length).assertEqual(1);
      expect(merged[0].text).assertEqual('new');
    });

    it('replaces an optimistic message by localId when the incoming id is new', 0, () => {
      const list: ChatMessage[] = [makeMsg('', 'l1', true, 'old')];
      const incoming: ChatMessage = makeMsg('srv1', 'l1', false, 'new');
      const merged: ChatMessage[] = mergeMessage(list, incoming);
      expect(merged.length).assertEqual(1);
      expect(merged[0].id).assertEqual('srv1');
      expect(merged[0].text).assertEqual('new');
    });

    it('appends when neither id nor localId matches', 0, () => {
      const list: ChatMessage[] = [makeMsg('a', '', false, 'x')];
      const merged: ChatMessage[] = mergeMessage(list, makeMsg('b', '', false, 'y'));
      expect(merged.length).assertEqual(2);
      expect(merged[1].id).assertEqual('b');
    });

    it('prefers an id match over a localId match', 0, () => {
      const list: ChatMessage[] = [makeMsg('a', 'l1', true, 'old')];
      const merged: ChatMessage[] = mergeMessage(list, makeMsg('a', 'l1', false, 'new'));
      expect(merged.length).assertEqual(1); // id 命中即替换，不因 localId 再触发
      expect(merged[0].text).assertEqual('new');
    });

    it('appends an incoming message with empty id and empty localId', 0, () => {
      const list: ChatMessage[] = [makeMsg('a', '', false, 'x')];
      const merged: ChatMessage[] = mergeMessage(list, makeMsg('', '', false, 'y'));
      expect(merged.length).assertEqual(2);
    });

    it('does not replace a non-optimistic message by localId', 0, () => {
      const list: ChatMessage[] = [makeMsg('', 'l1', false, 'old')]; // 非乐观
      const merged: ChatMessage[] = mergeMessage(list, makeMsg('', 'l1', false, 'new'));
      expect(merged.length).assertEqual(2); // localId 仅对乐观消息生效 → 追加
    });
  });

  describe('cloneMessage', () => {
    it('produces an equal but distinct instance with shared blocks ref', 0, () => {
      const m: ChatMessage = makeMsg('a', 'l1', true, 'hello');
      m.blocks = [textBlock('b')];
      const c: ChatMessage = cloneMessage(m);
      expect(c === m).assertEqual(false);
      expect(c.id).assertEqual('a');
      expect(c.localId).assertEqual('l1');
      expect(c.isOptimistic).assertTrue();
      expect(c.text).assertEqual('hello');
      expect(c.blocks === m.blocks).assertTrue(); // 浅拷贝：blocks 引用共享
    });
  });

  describe('ChatMessage.isQueued', () => {
    it('is true for a not-yet-invoked user message', 0, () => {
      expect(parse(userEnv('u', 'q', 0)).isQueued).assertTrue();
    });
    it('is false for an already-invoked user message', 0, () => {
      expect(parse(userEnv('u', 'q', 50)).isQueued).assertFalse();
    });
    it('is false for a failed user message even when not invoked', 0, () => {
      const failed: ChatMessage = makeMsg('u', '', false, '');
      failed.invokedAt = 0;
      failed.status = 'failed';
      expect(failed.isQueued).assertFalse();
    });
    it('is false for an agent message', 0, () => {
      const agent: ChatMessage = makeMsg('a', '', false, '');
      agent.role = 'agent';
      expect(agent.isQueued).assertFalse();
    });
  });

  // —— Token / 上下文用量（对照 web UsageData + reducer calculateContextSize + modelConfig getContextBudgetTokens）——
  describe('parseUsage', () => {
    it('returns null when usage is absent', 0, () => {
      expect(parseUsage(JSON.parse('{}') as Record<string, Object>) === null).assertTrue();
    });
    it('returns null when input_tokens is missing', 0, () => {
      expect(parseUsage(JSON.parse('{"usage":{"output_tokens":10}}') as Record<string, Object>) === null).assertTrue();
    });
    it('returns null when output_tokens is missing', 0, () => {
      expect(parseUsage(JSON.parse('{"usage":{"input_tokens":5}}') as Record<string, Object>) === null).assertTrue();
    });
    it('parses required + optional fields', 0, () => {
      const u = parseUsage(JSON.parse('{"usage":{"input_tokens":100,"output_tokens":50,' +
        '"cache_creation_input_tokens":20,"cache_read_input_tokens":80,"context_tokens":150,' +
        '"context_window":200000,"scope_role":"child"}}') as Record<string, Object>);
      expect(u !== null).assertTrue();
      if (u !== null) {
        expect(u.inputTokens).assertEqual(100);
        expect(u.outputTokens).assertEqual(50);
        expect(u.cacheCreation).assertEqual(20);
        expect(u.cacheRead).assertEqual(80);
        expect(u.contextTokens).assertEqual(150);
        expect(u.contextWindow).assertEqual(200000);
        expect(u.scopeRole).assertEqual('child');
      }
    });
    it('defaults optional number fields (cache→0, contextTokens/contextWindow→-1, scopeRole→"")', 0, () => {
      const u = parseUsage(JSON.parse('{"usage":{"input_tokens":1,"output_tokens":2}}') as Record<string, Object>);
      expect(u !== null).assertTrue();
      if (u !== null) {
        expect(u.cacheCreation).assertEqual(0);
        expect(u.cacheRead).assertEqual(0);
        expect(u.contextTokens).assertEqual(-1);
        expect(u.contextWindow).assertEqual(-1);
        expect(u.scopeRole).assertEqual('');
      }
    });
  });

  describe('normalizeCodexTokenUsage', () => {
    it('prefers info.last over info.total', 0, () => {
      const info = JSON.parse('{"last":{"inputTokens":300,"outputTokens":40},' +
        '"total":{"inputTokens":999999,"outputTokens":888888}}') as Record<string, Object>;
      const u = normalizeCodexTokenUsage(info, null);
      expect(u !== null).assertTrue();
      if (u !== null) {
        expect(u.inputTokens).assertEqual(300); // last 胜出
        expect(u.outputTokens).assertEqual(40);
      }
    });
    it('falls back to total when last is absent', 0, () => {
      const info = JSON.parse('{"total":{"inputTokens":5000,"outputTokens":600}}') as Record<string, Object>;
      const u = normalizeCodexTokenUsage(info, null);
      expect(u !== null).assertTrue();
      if (u !== null) { expect(u.inputTokens).assertEqual(5000); }
    });
    it('uses info itself when neither last nor total present', 0, () => {
      const info = JSON.parse('{"inputTokens":7,"outputTokens":3}') as Record<string, Object>;
      const u = normalizeCodexTokenUsage(info, null);
      expect(u !== null).assertTrue();
      if (u !== null) { expect(u.inputTokens).assertEqual(7); }
    });
    it('returns null when input/output missing', 0, () => {
      const info = JSON.parse('{"last":{"inputTokens":5}}') as Record<string, Object>;
      expect(normalizeCodexTokenUsage(info, null) === null).assertTrue();
    });
    it('returns null when info is null', 0, () => {
      expect(normalizeCodexTokenUsage(null, null) === null).assertTrue();
    });
    it('reads scope_role from data and context_window from info', 0, () => {
      const info = JSON.parse('{"last":{"inputTokens":10,"outputTokens":1},"model_context_window":200000}') as Record<string, Object>;
      const data = JSON.parse('{"type":"token_count","scope_role":"child"}') as Record<string, Object>;
      const u = normalizeCodexTokenUsage(info, data);
      expect(u !== null).assertTrue();
      if (u !== null) {
        expect(u.contextWindow).assertEqual(200000);
        expect(u.scopeRole).assertEqual('child');
        expect(u.isVisibleInParent).assertFalse();
      }
    });
  });

  describe('UsageData.contextSize / isVisibleInParent', () => {
    it('contextSize uses context_tokens when present', 0, () => {
      const u = parseUsage(JSON.parse(
        '{"usage":{"input_tokens":10,"output_tokens":0,"context_tokens":999}}') as Record<string, Object>);
      expect(u !== null).assertTrue();
      if (u !== null) { expect(u.contextSize).assertEqual(999); }
    });
    it('contextSize falls back to cache_creation+cache_read+input when context_tokens absent', 0, () => {
      const u = parseUsage(JSON.parse('{"usage":{"input_tokens":100,"output_tokens":0,' +
        '"cache_creation_input_tokens":30,"cache_read_input_tokens":70}}') as Record<string, Object>);
      expect(u !== null).assertTrue();
      if (u !== null) { expect(u.contextSize).assertEqual(200); } // 100+30+70
    });
    it('isVisibleInParent is false for child scope, true otherwise', 0, () => {
      const child = parseUsage(JSON.parse(
        '{"usage":{"input_tokens":1,"output_tokens":1,"scope_role":"child"}}') as Record<string, Object>);
      const parent = parseUsage(JSON.parse(
        '{"usage":{"input_tokens":1,"output_tokens":1}}') as Record<string, Object>);
      expect(child !== null).assertTrue();
      expect(parent !== null).assertTrue();
      if (child !== null) { expect(child.isVisibleInParent).assertFalse(); }
      if (parent !== null) { expect(parent.isVisibleInParent).assertTrue(); }
    });
  });

  describe('latestVisibleUsage', () => {
    it('returns null for an empty list', 0, () => {
      const empty: ChatMessage[] = [];
      expect(latestVisibleUsage(empty) === null).assertTrue();
    });
    it('returns the latest visible usage scanning in reverse', 0, () => {
      const m1 = makeMsg('a', '', false, '');
      m1.usage = parseUsage(JSON.parse('{"usage":{"input_tokens":10,"output_tokens":0}}') as Record<string, Object>);
      const m2 = makeMsg('b', '', false, '');
      m2.usage = parseUsage(JSON.parse('{"usage":{"input_tokens":20,"output_tokens":0}}') as Record<string, Object>);
      const list: ChatMessage[] = [m1, m2];
      const u = latestVisibleUsage(list);
      expect(u !== null).assertTrue();
      if (u !== null) { expect(u.inputTokens).assertEqual(20); } // 最新（m2）
    });
    it('skips child-scope usage and returns the latest parent-visible one', 0, () => {
      const m1 = makeMsg('a', '', false, '');
      m1.usage = parseUsage(JSON.parse('{"usage":{"input_tokens":10,"output_tokens":0}}') as Record<string, Object>);
      const m2 = makeMsg('b', '', false, '');
      m2.usage = parseUsage(JSON.parse(
        '{"usage":{"input_tokens":99,"output_tokens":0,"scope_role":"child"}}') as Record<string, Object>);
      const list: ChatMessage[] = [m1, m2];
      const u = latestVisibleUsage(list);
      expect(u !== null).assertTrue();
      if (u !== null) { expect(u.inputTokens).assertEqual(10); } // 跳过 m2，取 m1
    });
    it('skips messages with null usage', 0, () => {
      const m1 = makeMsg('a', '', false, '');
      m1.usage = parseUsage(JSON.parse('{"usage":{"input_tokens":5,"output_tokens":0}}') as Record<string, Object>);
      const m2 = makeMsg('b', '', false, ''); // usage === null
      const list: ChatMessage[] = [m1, m2];
      const u = latestVisibleUsage(list);
      expect(u !== null).assertTrue();
      if (u !== null) { expect(u.inputTokens).assertEqual(5); }
    });
  });

  describe('getContextBudgetTokens', () => {
    it('returns null for unknown flavor', 0, () => {
      expect(getContextBudgetTokens('whatever', 'gemini')).assertEqual(null);
      expect(getContextBudgetTokens('sonnet', '')).assertEqual(null);
    });
    it('returns codex budget (minus headroom) for codex regardless of model', 0, () => {
      expect(getContextBudgetTokens('', 'codex')).assertEqual(248400); // 258400-10000
    });
    it('returns 200k-minus-headroom for claude presets without [1m]', 0, () => {
      expect(getContextBudgetTokens('sonnet', 'claude')).assertEqual(190000); // 200000-10000
      expect(getContextBudgetTokens('opus', 'claude')).assertEqual(190000);
    });
    it('returns 1M-minus-headroom for [1m] presets', 0, () => {
      expect(getContextBudgetTokens('sonnet[1m]', 'claude')).assertEqual(990000); // 1000000-10000
      expect(getContextBudgetTokens('opus[1m]', 'claude')).assertEqual(990000);
    });
    it('returns 200k-minus-headroom for full claude-* model ids', 0, () => {
      expect(getContextBudgetTokens('claude-sonnet-4-5', 'claude')).assertEqual(190000);
    });
    it('defaults empty model (claude) to 200k', 0, () => {
      expect(getContextBudgetTokens('', 'claude')).assertEqual(190000);
    });
    it('returns null for non-preset non-claude-prefixed model under claude flavor (e.g. haiku)', 0, () => {
      expect(getContextBudgetTokens('haiku', 'claude')).assertEqual(null);
    });
  });

  describe('formatTokenCount', () => {
    it('formats millions with one decimal + M', 0, () => {
      expect(formatTokenCount(1000000)).assertEqual('1.0M');
      expect(formatTokenCount(1200000)).assertEqual('1.2M');
    });
    it('formats thousands with rounded k', 0, () => {
      expect(formatTokenCount(1000)).assertEqual('1k');
      expect(formatTokenCount(12345)).assertEqual('12k');
    });
    it('returns the raw number below 1000', 0, () => {
      expect(formatTokenCount(0)).assertEqual('0');
      expect(formatTokenCount(999)).assertEqual('999');
    });
  });

  describe('parseMessage — agent usage extraction', () => {
    it('extracts usage from data.message.usage', 0, () => {
      const m: ChatMessage = parse(agentEnv('a1',
        '{"message":{"content":[{"type":"text","text":"hi"}],' +
        '"usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":200}}}'));
      expect(m.usage !== null).assertTrue();
      if (m.usage !== null) {
        expect(m.usage.inputTokens).assertEqual(100);
        expect(m.usage.outputTokens).assertEqual(50);
        expect(m.usage.cacheRead).assertEqual(200);
        expect(m.usage.contextSize).assertEqual(300); // 无 context_tokens → 100+0+200
      }
    });
    it('leaves usage null when the agent message has none', 0, () => {
      const m: ChatMessage = parse(agentEnv('a1', '{"message":{"content":[{"type":"text","text":"hi"}]}}'));
      expect(m.usage === null).assertTrue();
    });
  });

  describe('parseMessage — codex token_count event usage', () => {
    it('extracts usage from a token_count event (info.last)', 0, () => {
      const m: ChatMessage = parse('{"id":"e1","createdAt":1,"content":{"role":"event",' +
        '"content":{"type":"token_count","info":{"last":{"inputTokens":300,"outputTokens":40},' +
        '"contextTokens":320,"modelContextWindow":258400}}}}');
      expect(m.role).assertEqual('event');
      expect(m.text).assertEqual('');
      expect(m.usage !== null).assertTrue();
      if (m.usage !== null) {
        expect(m.usage.inputTokens).assertEqual(300);
        expect(m.usage.outputTokens).assertEqual(40);
        expect(m.usage.contextTokens).assertEqual(320);
        expect(m.usage.contextWindow).assertEqual(258400);
        expect(m.usage.cacheCreation).assertEqual(0); // codex 不区分 cache_creation
      }
    });
    it('accepts the hyphenated type token-count and snake_case keys', 0, () => {
      const m: ChatMessage = parse('{"id":"e2","createdAt":1,"content":{"role":"event",' +
        '"content":{"type":"token-count","info":{"last":{"input_tokens":10,"output_tokens":2,' +
        '"cached_input_tokens":5}}}}}');
      expect(m.usage !== null).assertTrue();
      if (m.usage !== null) {
        expect(m.usage.inputTokens).assertEqual(10);
        expect(m.usage.cacheRead).assertEqual(5);
        expect(m.usage.contextTokens).assertEqual(10); // 缺 context_tokens → 回退 inputTokens
        expect(m.usage.contextWindow).assertEqual(-1); // 未提供
      }
    });
    it('leaves usage null for non-token-count events', 0, () => {
      const m: ChatMessage = parse('{"id":"e3","createdAt":1,"content":{"role":"event",' +
        '"content":{"type":"ready","agentId":"codex"}}}');
      expect(m.usage === null).assertTrue();
    });
  });

  describe('cloneMessage — usage', () => {
    it('preserves the usage reference (shallow copy)', 0, () => {
      const m = makeMsg('a', '', false, '');
      m.usage = parseUsage(JSON.parse('{"usage":{"input_tokens":7,"output_tokens":0}}') as Record<string, Object>);
      const c = cloneMessage(m);
      expect(c.usage === m.usage).assertTrue();
    });
  });

  describe('parseMessage — scheduledAt', () => {
    it('extracts scheduledAt epoch-ms', 0, () => {
      const m: ChatMessage = parse('{"id":"u1","content":{"role":"user","content":{"text":"hi"}},"invokedAt":null,"scheduledAt":1700000000000}');
      expect(m.scheduledAt).assertEqual(1700000000000);
    });
    it('defaults to 0 when absent or null', 0, () => {
      expect(parse('{"id":"u1","content":{"role":"user","content":{"text":"hi"}}}').scheduledAt).assertEqual(0);
      expect(parse('{"id":"u1","content":{"role":"user","content":{"text":"hi"}},"scheduledAt":null}').scheduledAt).assertEqual(0);
    });
  });

  describe('sortQueuedMessages', () => {
    it('immediate-queued first by createdAt, scheduled after by scheduledAt asc', 0, () => {
      const imm1: ChatMessage = new ChatMessage(); imm1.id = 'i1'; imm1.role = 'user'; imm1.createdAt = 100; imm1.invokedAt = 0; imm1.scheduledAt = 0;
      const imm2: ChatMessage = new ChatMessage(); imm2.id = 'i2'; imm2.role = 'user'; imm2.createdAt = 200; imm2.invokedAt = 0; imm2.scheduledAt = 0;
      const sch1: ChatMessage = new ChatMessage(); sch1.id = 's1'; sch1.role = 'user'; sch1.createdAt = 150; sch1.invokedAt = 0; sch1.scheduledAt = 5000;
      const sch2: ChatMessage = new ChatMessage(); sch2.id = 's2'; sch2.role = 'user'; sch2.createdAt = 120; sch2.invokedAt = 0; sch2.scheduledAt = 3000;
      const sorted: ChatMessage[] = sortQueuedMessages([sch1, imm2, sch2, imm1]);
      expect(sorted[0].id).assertEqual('i1');
      expect(sorted[1].id).assertEqual('i2');
      expect(sorted[2].id).assertEqual('s2');
      expect(sorted[3].id).assertEqual('s1');
    });
    it('does not mutate the input array', 0, () => {
      const imm: ChatMessage = new ChatMessage(); imm.id = 'i1'; imm.role = 'user'; imm.createdAt = 100;
      const sch: ChatMessage = new ChatMessage(); sch.id = 's1'; sch.role = 'user'; sch.createdAt = 120; sch.scheduledAt = 3000;
      const input: ChatMessage[] = [imm, sch];
      sortQueuedMessages(input);
      expect(input[0].id).assertEqual('i1');
    });
  });

  describe('formatScheduledIn', () => {
    it('empty when no schedule, 已到时间 when past', 0, () => {
      expect(formatScheduledIn(0, 1000)).assertEqual('');
      expect(formatScheduledIn(500, 1000)).assertEqual('已到时间');
    });
    it('minutes / hours / days buckets', 0, () => {
      expect(formatScheduledIn(1000 + 5 * 60000, 1000)).assertEqual('5 分钟后发送');
      expect(formatScheduledIn(1000 + 3 * 3600000, 1000)).assertEqual('3 小时后发送');
      expect(formatScheduledIn(1000 + 2 * 86400000, 1000)).assertEqual('2 天后发送');
    });
  });

  describe('parseCancelMessageResponse', () => {
    it('cancelled branch sets cancelled + localId', 0, () => {
      const r = parseCancelMessageResponse('{"status":"cancelled","localId":"local-1"}');
      expect(r.cancelled).assertTrue();
      expect(r.localId).assertEqual('local-1');
      expect(r.invokedMessage === null).assertTrue();
    });
    it('invoked branch parses the authoritative message', 0, () => {
      const r = parseCancelMessageResponse('{"status":"invoked","message":{"id":"m9","content":{"role":"user","content":{"text":"hi"}},"invokedAt":1700000000000}}');
      expect(r.cancelled).assertFalse();
      const msg: ChatMessage | null = r.invokedMessage;
      expect(msg !== null).assertTrue();
      if (msg !== null) {
        expect(msg.id).assertEqual('m9');
        expect(msg.invokedAt).assertEqual(1700000000000);
      }
    });
    it('cancelled with null localId → empty string; invalid JSON → not cancelled', 0, () => {
      const r1 = parseCancelMessageResponse('{"status":"cancelled","localId":null}');
      expect(r1.cancelled).assertTrue();
      expect(r1.localId).assertEqual('');
      const r2 = parseCancelMessageResponse('not json');
      expect(r2.cancelled).assertFalse();
      expect(r2.invokedMessage === null).assertTrue();
    });
  });
}
