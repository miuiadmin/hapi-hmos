// ChatSearch 纯逻辑单测 —— 对话内消息搜索过滤（blockMatchesQuery / blockSearchText）
//
// 覆盖：文本块命中正文（子串、大小写不敏感）、reasoning 命中思考正文、
//       工具卡命中 名 / 描述 / 入参(JSON) / 结果(字符串与对象)、空查询与空白查询不匹配。

import { describe, it, expect } from '@ohos/hypium';
import { blockMatchesQuery, blockSearchText } from '../main/ets/chat/ChatSearch';
import { ChatBlock, ChatToolCall, ChatBlockKind } from '../main/ets/chat/ChatBlock';

// —— 块构造器 ——

function textBlockOf(kind: ChatBlockKind, text: string): ChatBlock {
  const b: ChatBlock = new ChatBlock();
  b.kind = kind;
  b.text = text;
  return b;
}

function toolBlock(name: string): ChatBlock {
  const b: ChatBlock = new ChatBlock();
  b.kind = 'tool-call';
  const tool: ChatToolCall = new ChatToolCall();
  tool.name = name;
  b.tool = tool;
  return b;
}

export default function chatSearchTest(): void {
  describe('blockMatchesQuery — 文本块', () => {
    it('子串命中（agent 正文）', 0, () => {
      const b: ChatBlock = textBlockOf('agent-text', 'flaky tests failed again');
      expect(blockMatchesQuery(b, 'flaky')).assertTrue();
      expect(blockMatchesQuery(b, 'tests failed')).assertTrue();
    });

    it('大小写不敏感', 0, () => {
      const b: ChatBlock = textBlockOf('agent-text', 'Running Tests');
      expect(blockMatchesQuery(b, 'running tests')).assertTrue();
      expect(blockMatchesQuery(b, 'RUNNING')).assertTrue();
    });

    it('不相关查询不命中', 0, () => {
      const b: ChatBlock = textBlockOf('user-text', 'how are you');
      expect(blockMatchesQuery(b, 'weather')).assertFalse();
    });

    it('reasoning 块命中思考正文', 0, () => {
      const b: ChatBlock = textBlockOf('reasoning', 'I should check the database first');
      expect(blockMatchesQuery(b, 'database')).assertTrue();
    });

    it('空查询不匹配', 0, () => {
      const b: ChatBlock = textBlockOf('agent-text', 'hello');
      expect(blockMatchesQuery(b, '')).assertFalse();
    });

    it('纯空白查询不匹配', 0, () => {
      const b: ChatBlock = textBlockOf('agent-text', 'hello');
      expect(blockMatchesQuery(b, '   ')).assertFalse();
    });

    it('查询前后空白被忽略', 0, () => {
      const b: ChatBlock = textBlockOf('agent-text', 'deploy the server');
      expect(blockMatchesQuery(b, '  deploy  ')).assertTrue();
    });
  });

  describe('blockMatchesQuery — 工具卡', () => {
    it('按工具名命中', 0, () => {
      const b: ChatBlock = toolBlock('Bash');
      expect(blockMatchesQuery(b, 'bash')).assertTrue();
    });

    it('按描述命中', 0, () => {
      const b: ChatBlock = toolBlock('Edit');
      if (b.tool !== null) {
        b.tool.description = 'edit the config file';
      }
      expect(blockMatchesQuery(b, 'config file')).assertTrue();
    });

    it('按入参(JSON 值)命中', 0, () => {
      const b: ChatBlock = toolBlock('Edit');
      if (b.tool !== null) {
        const input: Record<string, Object> = { 'file_path': '/src/index.ts' };
        b.tool.input = input;
      }
      expect(blockMatchesQuery(b, 'index.ts')).assertTrue();
    });

    it('按字符串结果命中', 0, () => {
      const b: ChatBlock = toolBlock('Bash');
      if (b.tool !== null) {
        b.tool.result = 'build succeeded with 0 errors';
      }
      expect(blockMatchesQuery(b, 'succeeded')).assertTrue();
    });

    it('按对象结果(字段值)命中', 0, () => {
      const b: ChatBlock = toolBlock('Bash');
      if (b.tool !== null) {
        const result: Record<string, string> = { 'error': 'permission denied' };
        b.tool.result = result;
      }
      expect(blockMatchesQuery(b, 'permission')).assertTrue();
    });

    it('工具卡空字段（无名/无描述/无入参/无结果）→ 空串可搜索文本', 0, () => {
      const b: ChatBlock = new ChatBlock();
      b.kind = 'tool-call';   // tool=null
      expect(blockSearchText(b)).assertEqual('');
      expect(blockMatchesQuery(b, 'anything')).assertFalse();
    });
  });

  describe('blockSearchText — 扁平化', () => {
    it('文本块返回正文原值', 0, () => {
      const b: ChatBlock = textBlockOf('user-text', 'plain text');
      expect(blockSearchText(b)).assertEqual('plain text');
    });

    it('工具卡拼接 名+描述+入参+结果', 0, () => {
      const b: ChatBlock = toolBlock('Bash');
      if (b.tool !== null) {
        b.tool.description = 'run tests';
        const input: Record<string, Object> = { 'cmd': 'npm test' };
        b.tool.input = input;
        b.tool.result = 'ok';
      }
      const s: string = blockSearchText(b);
      expect(s.includes('Bash')).assertTrue();
      expect(s.includes('run tests')).assertTrue();
      expect(s.includes('npm test')).assertTrue();
      expect(s.includes('ok')).assertTrue();
    });
  });
}
