// TerminalToolDisplay 单测 —— 终端工具卡片显示模式纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 GeneratedImageCacheUtils.test / Translate.test 范式：同步断言（assertEqual / === ）。
//   覆盖 parse / isTerminalRelatedToolName / isSubagentToolName / shouldUseCompactTerminalToolCard /
//   shouldShowInlineToolCardBody / getTerminalToolDisplayModeOptions，对照上游 ToolCard.test.ts 语义。

import { describe, it, expect } from '@ohos/hypium';
import {
  TerminalToolDisplayMode,
  DEFAULT_TERMINAL_TOOL_DISPLAY_MODE,
  parseTerminalToolDisplayMode,
  isTerminalRelatedToolName,
  isSubagentToolName,
  shouldUseCompactTerminalToolCard,
  shouldShowInlineToolCardBody,
  getTerminalToolDisplayModeOptions
} from '../main/ets/chat/TerminalToolDisplay';

export default function terminalToolDisplayTest(): void {
  describe('TerminalToolDisplay — 默认值', () => {
    it('DEFAULT = compact', 0, () => {
      expect(DEFAULT_TERMINAL_TOOL_DISPLAY_MODE).assertEqual('compact');
    });
  });

  describe('TerminalToolDisplay — parseTerminalToolDisplayMode', () => {
    it('compact → compact', 0, () => {
      expect(parseTerminalToolDisplayMode('compact')).assertEqual('compact');
    });
    it('detailed → detailed', 0, () => {
      expect(parseTerminalToolDisplayMode('detailed')).assertEqual('detailed');
    });
    it('空串 → DEFAULT(compact)', 0, () => {
      expect(parseTerminalToolDisplayMode('')).assertEqual('compact');
    });
    it('非法值 → DEFAULT(compact)', 0, () => {
      expect(parseTerminalToolDisplayMode('garbage')).assertEqual('compact');
    });
    it('大小写敏感：Compact(大写 C) → DEFAULT（严格 ===）', 0, () => {
      expect(parseTerminalToolDisplayMode('Compact')).assertEqual('compact');
    });
  });

  describe('TerminalToolDisplay — isTerminalRelatedToolName', () => {
    it('Bash / CodexBash / shell_command / run_shell_command → true', 0, () => {
      expect(isTerminalRelatedToolName('Bash')).assertEqual(true);
      expect(isTerminalRelatedToolName('CodexBash')).assertEqual(true);
      expect(isTerminalRelatedToolName('shell_command')).assertEqual(true);
      expect(isTerminalRelatedToolName('run_shell_command')).assertEqual(true);
    });
    it('Read / Edit / Task / 空串 → false', 0, () => {
      expect(isTerminalRelatedToolName('Read')).assertEqual(false);
      expect(isTerminalRelatedToolName('Edit')).assertEqual(false);
      expect(isTerminalRelatedToolName('Task')).assertEqual(false);
      expect(isTerminalRelatedToolName('')).assertEqual(false);
    });
  });

  describe('TerminalToolDisplay — isSubagentToolName', () => {
    it('Task / Agent → true', 0, () => {
      expect(isSubagentToolName('Task')).assertEqual(true);
      expect(isSubagentToolName('Agent')).assertEqual(true);
    });
    it('Agent:xxx / Task:xxx 前缀变体 → true', 0, () => {
      expect(isSubagentToolName('Agent:Explore')).assertEqual(true);
      expect(isSubagentToolName('Task:general-purpose')).assertEqual(true);
    });
    it('Bash / Read / 空串 → false', 0, () => {
      expect(isSubagentToolName('Bash')).assertEqual(false);
      expect(isSubagentToolName('Read')).assertEqual(false);
      expect(isSubagentToolName('')).assertEqual(false);
    });
  });

  describe('TerminalToolDisplay — shouldUseCompactTerminalToolCard', () => {
    it('终端类 + compact → true', 0, () => {
      expect(shouldUseCompactTerminalToolCard('Bash', 'compact')).assertEqual(true);
      expect(shouldUseCompactTerminalToolCard('shell_command', 'compact')).assertEqual(true);
    });
    it('终端类 + detailed → false', 0, () => {
      expect(shouldUseCompactTerminalToolCard('Bash', 'detailed')).assertEqual(false);
    });
    it('非终端类 + compact → false', 0, () => {
      expect(shouldUseCompactTerminalToolCard('Read', 'compact')).assertEqual(false);
      expect(shouldUseCompactTerminalToolCard('TodoWrite', 'compact')).assertEqual(false);
    });
  });

  describe('TerminalToolDisplay — shouldShowInlineToolCardBody', () => {
    // 终端类
    it('Bash + minimal=true + compact → false（默认仅 header）', 0, () => {
      expect(shouldShowInlineToolCardBody('Bash', true, 'compact')).assertEqual(false);
    });
    it('Bash + minimal=true + detailed → true（detailed 内联命令预览，绕过 minimal）', 0, () => {
      expect(shouldShowInlineToolCardBody('Bash', true, 'detailed')).assertEqual(true);
    });
    it('Bash + minimal=false + compact → false（终端类 compact 恒不内联，minimal 不影响）', 0, () => {
      expect(shouldShowInlineToolCardBody('Bash', false, 'compact')).assertEqual(false);
    });
    it('shell_command + detailed → true', 0, () => {
      expect(shouldShowInlineToolCardBody('shell_command', true, 'detailed')).assertEqual(true);
    });
    // 非终端类：由 minimal 决定
    it('Read + minimal=true → false（!minimal=false）', 0, () => {
      expect(shouldShowInlineToolCardBody('Read', true, 'compact')).assertEqual(false);
    });
    it('Read + minimal=false → true（!minimal）', 0, () => {
      expect(shouldShowInlineToolCardBody('Read', false, 'compact')).assertEqual(true);
    });
    it('TodoWrite + minimal=false → true（清单内联体不受 mode 影响）', 0, () => {
      expect(shouldShowInlineToolCardBody('TodoWrite', false, 'compact')).assertEqual(true);
      expect(shouldShowInlineToolCardBody('TodoWrite', false, 'detailed')).assertEqual(true);
    });
    // 子代理工具：恒不内联（即使 minimal=false / detailed）
    it('Task + minimal=false + detailed → false（子代理首判拦截）', 0, () => {
      expect(shouldShowInlineToolCardBody('Task', false, 'detailed')).assertEqual(false);
    });
    it('Agent:foo + minimal=false + detailed → false', 0, () => {
      expect(shouldShowInlineToolCardBody('Agent:foo', false, 'detailed')).assertEqual(false);
    });
  });

  describe('TerminalToolDisplay — getTerminalToolDisplayModeOptions', () => {
    it('恰好两选项', 0, () => {
      expect(getTerminalToolDisplayModeOptions().length).assertEqual(2);
    });
    it('[0] = compact / .compact labelKey', 0, () => {
      const opts = getTerminalToolDisplayModeOptions();
      expect(opts[0].value).assertEqual('compact');
      expect(opts[0].labelKey).assertEqual('settings.chat.terminalToolDisplay.compact');
    });
    it('[1] = detailed / .detailed labelKey', 0, () => {
      const opts = getTerminalToolDisplayModeOptions();
      expect(opts[1].value).assertEqual('detailed');
      expect(opts[1].labelKey).assertEqual('settings.chat.terminalToolDisplay.detailed');
    });
  });
}
