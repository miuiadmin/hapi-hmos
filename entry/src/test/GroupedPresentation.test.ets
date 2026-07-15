// GroupedPresentation 单测 —— 对照 web/src/components/ToolCard/groupedPresentation.ts
//   覆盖：inferGroupedSummaryIntent（Read/LS→inspect；Grep/Glob→search；Edit/Write→modify；
//   WebFetch→open-web；Bash 命令词命中 ls/cat→inspect、grep→search，否则 run-project-command；余→generic-tool）、
//   getPrimaryIntent（plurality + 首现优先 tiebreak）、formatGroupedHeaderTitle（plurality label / 全 generic→兜底）、
//   formatGroupedHeaderSubtitle（command·search·read·mutation·web 顺序；空→''）。
//   文案随 i18n locale——显式 setTranslateLocale('zh-CN') 钉死断言中文。
//   input 用 JSON.parse(json) as Record<string,Object> 构造（避嵌套字面量类型坑）。

import { describe, it, expect } from '@ohos/hypium';
import { ChatBlock, ChatToolCall, ToolGroupSummary } from '../main/ets/chat/ChatBlock';
import {
  inferGroupedSummaryIntent,
  getPrimaryIntent,
  formatGroupedHeaderTitle,
  formatGroupedHeaderSubtitle
} from '../main/ets/chat/GroupedPresentation';
import { setTranslateLocale } from '../main/ets/i18n/Translate';

function rec(json: string): Record<string, Object> {
  return JSON.parse(json) as Record<string, Object>;
}

function mkTool(name: string, input: Record<string, Object> | null): ChatToolCall {
  const tool: ChatToolCall = new ChatToolCall();
  tool.name = name;
  tool.input = input;
  return tool;
}

function mkBlock(name: string, input: Record<string, Object> | null): ChatBlock {
  const tool: ChatToolCall = mkTool(name, input);
  const b: ChatBlock = new ChatBlock();
  b.kind = 'tool-call';
  b.id = name;
  b.tool = tool;
  return b;
}

function mkSummary(read: number, search: number, command: number, mutation: number, web: number, other: number): ToolGroupSummary {
  const s: ToolGroupSummary = new ToolGroupSummary();
  s.counts.read = read;
  s.counts.search = search;
  s.counts.command = command;
  s.counts.mutation = mutation;
  s.counts.web = web;
  s.counts.other = other;
  return s;
}

export default function groupedPresentationTest(): void {
  setTranslateLocale('zh-CN');

  describe('GroupedPresentation — inferGroupedSummaryIntent', () => {
    it('Read/LS/NotebookRead → inspect-files', 0, () => {
      expect(inferGroupedSummaryIntent(mkTool('Read', null))).assertEqual('inspect-files');
      expect(inferGroupedSummaryIntent(mkTool('LS', null))).assertEqual('inspect-files');
      expect(inferGroupedSummaryIntent(mkTool('NotebookRead', null))).assertEqual('inspect-files');
    });
    it('Grep/Glob → search-content', 0, () => {
      expect(inferGroupedSummaryIntent(mkTool('Grep', null))).assertEqual('search-content');
      expect(inferGroupedSummaryIntent(mkTool('Glob', null))).assertEqual('search-content');
    });
    it('Edit/Write/CodexPatch → modify-files', 0, () => {
      expect(inferGroupedSummaryIntent(mkTool('Edit', null))).assertEqual('modify-files');
      expect(inferGroupedSummaryIntent(mkTool('Write', null))).assertEqual('modify-files');
      expect(inferGroupedSummaryIntent(mkTool('CodexPatch', null))).assertEqual('modify-files');
    });
    it('WebFetch/WebSearch → open-web', 0, () => {
      expect(inferGroupedSummaryIntent(mkTool('WebFetch', null))).assertEqual('open-web');
    });
    it('Bash ls/cat → inspect-files；grep → search-content；其余 → run-project-command', 0, () => {
      expect(inferGroupedSummaryIntent(mkTool('Bash', rec('{"command":"ls -la"}')))).assertEqual('inspect-files');
      expect(inferGroupedSummaryIntent(mkTool('Bash', rec('{"command":"cat file"}')))).assertEqual('inspect-files');
      expect(inferGroupedSummaryIntent(mkTool('Bash', rec('{"command":"grep foo ."}')))).assertEqual('search-content');
      expect(inferGroupedSummaryIntent(mkTool('Bash', rec('{"command":"make build"}')))).assertEqual('run-project-command');
      expect(inferGroupedSummaryIntent(mkTool('CodexBash', rec('{"command":"rg pattern"}')))).assertEqual('search-content');
    });
    it('未知/子代理工具 → generic-tool', 0, () => {
      expect(inferGroupedSummaryIntent(mkTool('Task', null))).assertEqual('generic-tool');
      expect(inferGroupedSummaryIntent(mkTool('Whatever', null))).assertEqual('generic-tool');
    });
  });

  describe('GroupedPresentation — getPrimaryIntent', () => {
    it('plurality：2 Read + 1 Edit → inspect-files', 0, () => {
      const tools: ChatBlock[] = [mkBlock('Read', null), mkBlock('Read', null), mkBlock('Edit', null)];
      expect(getPrimaryIntent(tools)).assertEqual('inspect-files');
    });
    it('plurality：2 Edit + 1 Read → modify-files', 0, () => {
      const tools: ChatBlock[] = [mkBlock('Edit', null), mkBlock('Edit', null), mkBlock('Read', null)];
      expect(getPrimaryIntent(tools)).assertEqual('modify-files');
    });
    it('tiebreak：1 Read + 1 Edit（首现优先）→ inspect-files', 0, () => {
      const tools: ChatBlock[] = [mkBlock('Read', null), mkBlock('Edit', null)];
      expect(getPrimaryIntent(tools)).assertEqual('inspect-files');
    });
  });

  describe('GroupedPresentation — formatGroupedHeaderTitle', () => {
    it('plurality inspect → 「检查文件」', 0, () => {
      const tools: ChatBlock[] = [mkBlock('Read', null), mkBlock('Read', null)];
      expect(formatGroupedHeaderTitle(tools)).assertEqual('检查文件');
    });
    it('全 generic-tool → 兜底「命令」', 0, () => {
      const tools: ChatBlock[] = [mkBlock('Task', null), mkBlock('Skill', null)];
      expect(formatGroupedHeaderTitle(tools)).assertEqual('命令');
    });
  });

  describe('GroupedPresentation — formatGroupedHeaderSubtitle', () => {
    it('command·search·read 顺序拼接（search=0 跳过）', 0, () => {
      // command=2, search=0, read=1 → '2 条命令 · 1 次读取'
      const s: ToolGroupSummary = mkSummary(1, 0, 2, 0, 0, 0);
      expect(formatGroupedHeaderSubtitle(s)).assertEqual('2 条命令 · 1 次读取');
    });
    it('全 0 → 空串', 0, () => {
      expect(formatGroupedHeaderSubtitle(mkSummary(0, 0, 0, 0, 0, 0))).assertEqual('');
    });
    it('仅 other（无他部）→ 空串（other 仅当已有他部才追加）', 0, () => {
      expect(formatGroupedHeaderSubtitle(mkSummary(0, 0, 0, 0, 0, 3))).assertEqual('');
    });
    it('他部 + other → other 追加末尾', 0, () => {
      // read=1, other=2 → '1 次读取 · 2 项其他'
      const s: ToolGroupSummary = mkSummary(1, 0, 0, 0, 0, 2);
      expect(formatGroupedHeaderSubtitle(s)).assertEqual('1 次读取 · 2 项其他');
    });
  });
}
