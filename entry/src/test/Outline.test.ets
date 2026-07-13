// Outline 纯逻辑单测 —— 对照 web/src/chat/outline.test.ts
//
// 覆盖：buildConversationOutline 只索引 user-text、跳过其它 kind / 未发送 optimistic（非 failed）、
//       truncateOutlineLabel 截断 96 字符 + 折叠空白 + 空回落「空消息」、保序、空数组。

import { describe, it, expect } from '@ohos/hypium';
import { buildConversationOutline, truncateOutlineLabel, MAX_OUTLINE_LABEL_LENGTH } from '../main/ets/chat/Outline';
import { ChatBlock } from '../main/ets/chat/ChatBlock';

// —— 块构造器 ——

function userText(id: string, text: string, createdAt: number): ChatBlock {
  const b: ChatBlock = new ChatBlock();
  b.kind = 'user-text';
  b.id = id;
  b.text = text;
  b.createdAt = createdAt;
  return b;
}

function agentText(id: string, text: string): ChatBlock {
  const b: ChatBlock = new ChatBlock();
  b.kind = 'agent-text';
  b.id = id;
  b.text = text;
  return b;
}

// 未发送的 optimistic user-text（userOptimistic=true；userStatus 默认 ''）
function optimisticUser(id: string, text: string, status: string): ChatBlock {
  const b: ChatBlock = new ChatBlock();
  b.kind = 'user-text';
  b.id = id;
  b.text = text;
  b.userOptimistic = true;
  b.userStatus = status;
  return b;
}

function reasoning(id: string): ChatBlock {
  const b: ChatBlock = new ChatBlock();
  b.kind = 'reasoning';
  b.id = id;
  b.text = '思考内容';
  return b;
}

function generatedImage(id: string): ChatBlock {
  const b: ChatBlock = new ChatBlock();
  b.kind = 'generated-image';
  b.id = id;
  b.imageId = 'img1';
  return b;
}

export default function outlineTest(): void {
  describe('truncateOutlineLabel', () => {
    it('returns short text unchanged (whitespace collapsed + trimmed)', 0, () => {
      expect(truncateOutlineLabel('  hello   world  ')).assertEqual('hello world');
    });

    it('collapses internal whitespace runs to single spaces', 0, () => {
      expect(truncateOutlineLabel('a\t\n b\n\n c')).assertEqual('a b c');
    });

    it('truncates text longer than maxLength with ellipsis', 0, () => {
      const long: string = 'x'.repeat(120);
      const out: string = truncateOutlineLabel(long);
      expect(out.length).assertEqual(MAX_OUTLINE_LABEL_LENGTH);   // (maxLength-3) + '...'
      expect(out.endsWith('...')).assertTrue();
    });

    it('respects custom maxLength', 0, () => {
      const out: string = truncateOutlineLabel('abcdefgh', 5);
      expect(out).assertEqual('ab...');   // 5-3=2 字符 + '...'
    });
  });

  describe('buildConversationOutline — kind filtering', () => {
    it('includes only user-text blocks (skips agent/tool/reasoning/generated-image)', 0, () => {
      const items = buildConversationOutline([
        userText('u1', '第一问', 100),
        agentText('a1', '答'),
        reasoning('r1'),
        generatedImage('g1'),
        userText('u2', '第二问', 200)
      ]);
      expect(items.length).assertEqual(2);
      expect(items[0].blockId).assertEqual('u1');
      expect(items[0].label).assertEqual('第一问');
      expect(items[1].blockId).assertEqual('u2');
    });

    it('returns empty for no user-text blocks', 0, () => {
      expect(buildConversationOutline([agentText('a1', 'x'), reasoning('r1')]).length).assertEqual(0);
    });

    it('returns empty for an empty array', 0, () => {
      expect(buildConversationOutline([]).length).assertEqual(0);
    });
  });

  describe('buildConversationOutline — optimistic / unsent handling', () => {
    it('skips optimistic unsent blocks (sending/queued)', 0, () => {
      const items = buildConversationOutline([
        optimisticUser('o1', '发送中', 'sending'),
        optimisticUser('o2', '排队中', 'queued'),
        userText('u1', '已发', 100)
      ]);
      expect(items.length).assertEqual(1);
      expect(items[0].blockId).assertEqual('u1');
    });

    it('keeps optimistic failed blocks (上游 isLocatableOutlineBlock 保留 failed)', 0, () => {
      const items = buildConversationOutline([
        optimisticUser('f1', '失败', 'failed'),
        userText('u1', '已发', 100)
      ]);
      expect(items.length).assertEqual(2);
      expect(items[0].blockId).assertEqual('f1');
    });
  });

  describe('buildConversationOutline — label / id / order', () => {
    it('uses 空消息 fallback for empty text', 0, () => {
      const items = buildConversationOutline([userText('u1', '   ', 100)]);
      expect(items[0].label).assertEqual('空消息');
    });

    it('builds stable outline id from block id', 0, () => {
      const items = buildConversationOutline([userText('u1', '问', 100)]);
      expect(items[0].id).assertEqual('outline:user-text:u1');
    });

    it('preserves createdAt and order', 0, () => {
      const items = buildConversationOutline([
        userText('u1', '一', 300),
        userText('u2', '二', 100),
        userText('u3', '三', 200)
      ]);
      expect(items.length).assertEqual(3);
      expect(items[0].blockId).assertEqual('u1');
      expect(items[0].createdAt).assertEqual(300);
      expect(items[1].blockId).assertEqual('u2');
      expect(items[2].blockId).assertEqual('u3');
    });
  });
}
