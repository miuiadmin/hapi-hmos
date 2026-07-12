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
  cloneMessage
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
}
