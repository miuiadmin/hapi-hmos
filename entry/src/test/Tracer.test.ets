// Tracer 单测 —— sidechain 子代理消息追踪与归组纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 Reducer.test / SessionGrouping.test 范式：同步断言（assertEqual）。
//   覆盖 traceAndGroup：Task 发起 + sidechain 根(prompt 匹配) + 子(parentUuid 链) → 归组；
//     prompt 不匹配 + 无 parentUuid → 兜底入 root；孤儿先到后解析（processOrphans 回捞）；
//     多 Task 不同 prompt → 不同组；永不解析孤儿丢弃；非 sidechain 恒在 root。
//   对照上游 chat/tracer.ts:traceMessages 语义。

import { describe, it, expect } from '@ohos/hypium';
import { traceAndGroup, TracedResult } from '../main/ets/chat/Tracer';
import { ChatMessage } from '../main/ets/models/Message';
import { NormalizedAgentContent } from '../main/ets/chat/NormalizedContent';

// Task/Agent 发起消息：含 isSubagentToolName 工具块 + input.prompt。
function taskSpawnMsg(id: string, toolId: string, prompt: string, createdAt: number): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.id = id;
  m.role = 'agent';
  m.createdAt = createdAt;
  m.status = 'sent';
  const b: NormalizedAgentContent = new NormalizedAgentContent();
  b.type = 'tool-call';
  b.id = toolId;
  b.name = 'Task';
  const input: Record<string, Object> = {};
  input['prompt'] = prompt;
  b.input = input;
  m.blocks = [b];
  return m;
}

// sidechain 根（被注入的子代理 prompt）：isSidechain + sidechainPrompt + uuid（无可见 block）。
function sidechainRoot(id: string, uuid: string, prompt: string, createdAt: number): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.id = id;
  m.role = 'agent';
  m.createdAt = createdAt;
  m.status = 'sent';
  m.isSidechain = true;
  m.uuid = uuid;
  m.sidechainPrompt = prompt;
  m.text = '';
  m.blocks = [];
  return m;
}

// sidechain 子（parentUuid 链回根）：isSidechain + parentUuid + 可选 blocks。
function sidechainChild(id: string, uuid: string, parentUuid: string, createdAt: number,
  blocks: NormalizedAgentContent[]): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.id = id;
  m.role = 'agent';
  m.createdAt = createdAt;
  m.status = 'sent';
  m.isSidechain = true;
  m.uuid = uuid;
  m.parentUuid = parentUuid;
  m.blocks = blocks;
  return m;
}

function textBlock(text: string): NormalizedAgentContent {
  const b: NormalizedAgentContent = new NormalizedAgentContent();
  b.type = 'text';
  b.text = text;
  return b;
}

// root 消息 id 串（原序，逗号分隔）。
function rootIds(res: TracedResult): string {
  const ids: string[] = [];
  for (let i = 0; i < res.root.length; i++) {
    ids.push(res.root[i].id);
  }
  return ids.join(',');
}

// 指定组的消息 id 串（原序）；组不存在 → 空串。
function groupIds(res: TracedResult, key: string): string {
  const g: ChatMessage[] | undefined = res.groups.get(key);
  if (g === undefined) {
    return '';
  }
  const ids: string[] = [];
  for (let i = 0; i < g.length; i++) {
    ids.push(g[i].id);
  }
  return ids.join(',');
}

export default function tracerTest(): void {
  describe('Tracer — 基础归组（Task 发起 + sidechain 根 + 子）', () => {
    it('root 含 Task 发起消息；group[m-task] 含 root+child（原序）', 0, () => {
      const msgs: ChatMessage[] = [
        taskSpawnMsg('m-task', 't1', 'research foo', 100),
        sidechainRoot('s-root', 'su1', 'research foo', 200),
        sidechainChild('s-child', 'su2', 'su1', 300, [textBlock('did stuff')]),
      ];
      const res: TracedResult = traceAndGroup(msgs);
      expect(rootIds(res)).assertEqual('m-task');
      expect(groupIds(res, 'm-task')).assertEqual('s-root,s-child');
    });
  });

  describe('Tracer — prompt 不匹配 + 无 parentUuid → 兜底入 root', () => {
    it('sidechain 无匹配 prompt 且无 parentUuid → root；无组', 0, () => {
      const msgs: ChatMessage[] = [
        sidechainRoot('s-orphan', 'su9', 'no matching prompt', 100),
      ];
      const res: TracedResult = traceAndGroup(msgs);
      expect(rootIds(res)).assertEqual('s-orphan');
      expect(res.groups.size).assertEqual(0);
    });
  });

  describe('Tracer — parentUuid 链式归组（含孙）', () => {
    it('child + grandchild 经 parentUuid 链挂到 root 所在组（原序）', 0, () => {
      const msgs: ChatMessage[] = [
        taskSpawnMsg('m-task', 't1', 'do thing', 100),
        sidechainRoot('s-root', 'su1', 'do thing', 200),
        sidechainChild('s-child', 'su2', 'su1', 300, []),
        sidechainChild('s-grand', 'su3', 'su2', 400, []),
      ];
      const res: TracedResult = traceAndGroup(msgs);
      expect(rootIds(res)).assertEqual('m-task');
      expect(groupIds(res, 'm-task')).assertEqual('s-root,s-child,s-grand');
    });
  });

  describe('Tracer — 孤儿先到后解析（processOrphans 回捞）', () => {
    it('child 先到（父未解析→orphan），root 后到匹配 → 回捞入组', 0, () => {
      const msgs: ChatMessage[] = [
        taskSpawnMsg('m-task', 't1', 'do thing', 100),
        sidechainChild('s-child', 'su2', 'su1', 200, []),
        sidechainRoot('s-root', 'su1', 'do thing', 300),
      ];
      const res: TracedResult = traceAndGroup(msgs);
      expect(rootIds(res)).assertEqual('m-task');
      expect(groupIds(res, 'm-task')).assertEqual('s-root,s-child');
    });
  });

  describe('Tracer — 多 Task 不同 prompt → 不同组', () => {
    it('两个 Task 各自归到自己的组', 0, () => {
      const msgs: ChatMessage[] = [
        taskSpawnMsg('m-a', 't1', 'prompt A', 100),
        taskSpawnMsg('m-b', 't2', 'prompt B', 110),
        sidechainRoot('s-a-root', 'ua1', 'prompt A', 200),
        sidechainRoot('s-b-root', 'ub1', 'prompt B', 210),
      ];
      const res: TracedResult = traceAndGroup(msgs);
      expect(rootIds(res)).assertEqual('m-a,m-b');
      expect(groupIds(res, 'm-a')).assertEqual('s-a-root');
      expect(groupIds(res, 'm-b')).assertEqual('s-b-root');
    });
  });

  describe('Tracer — 永不解析的孤儿 sidechain 丢弃', () => {
    it('child 父永不出现 → 既不在 root 也不在任何组', 0, () => {
      const msgs: ChatMessage[] = [
        sidechainChild('s-lost', 'suX', 'su-missing', 100, []),
      ];
      const res: TracedResult = traceAndGroup(msgs);
      expect(rootIds(res)).assertEqual('');
      expect(res.groups.size).assertEqual(0);
    });
  });

  describe('Tracer — 非 sidechain 消息恒在 root', () => {
    it('普通 user/agent 消息进 root，不受 sidechain 影响', 0, () => {
      const u: ChatMessage = new ChatMessage();
      u.id = 'u1'; u.role = 'user'; u.createdAt = 1; u.status = 'sent';
      const msgs: ChatMessage[] = [
        u,
        taskSpawnMsg('m-task', 't1', 'p', 100),
        sidechainRoot('s-r', 'su1', 'p', 200),
      ];
      const res: TracedResult = traceAndGroup(msgs);
      expect(rootIds(res)).assertEqual('u1,m-task');
      expect(groupIds(res, 'm-task')).assertEqual('s-r');
    });
  });
}
