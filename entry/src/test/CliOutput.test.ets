// CliOutput 单测 —— CLI 命令输出块检测/解析/合并/格式化纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 CodeHighlight.test / TerminalToolDisplay.test 范式：同步断言。
//   覆盖 isCliOutputText（sentFrom+标签矩阵，严格 AND 门控防误判）+
//   has*Tag 检测 + parseCliSegments（多标签/前导纯文本/无闭合）+
//   buildCliOutput（zh-CN 标签 + 分段拼接）+ extractCommandName（首非空行）+
//   mergeCliOutputBlocks（相邻同源合并/分隔符/不合并分支）。

import { describe, it, expect } from '@ohos/hypium';
import { setTranslateLocale } from '../main/ets/i18n/Translate';
import {
  isCliOutputText,
  hasCliOutputTags,
  hasCommandNameTag,
  hasLocalCommandStdoutTag,
  parseCliSegments,
  buildCliOutput,
  extractCommandName,
  mergeCliOutputBlocks,
  CliSegment
} from '../main/ets/chat/CliOutput';
import { ChatBlock } from '../main/ets/chat/ChatBlock';

// 辅助：判段数组中第 idx 段是否为某 tag（避 .find 的 | undefined 类型坑）
function isTagSegment(segs: CliSegment[], idx: number, tag: string): boolean {
  return segs[idx].isTag && segs[idx].tag === tag;
}

// 辅助：取第 idx 段内容
function segContent(segs: CliSegment[], idx: number): string {
  return segs[idx].content;
}

export default function cliOutputTest(): void {
  // 全程 zh-CN：buildCliOutput 的标签走 t() 查表（命令/标准输出/…）。
  setTranslateLocale('zh-CN');

  // —— isCliOutputText：sentFrom + 标签矩阵（严格 AND）——
  describe('CliOutput — isCliOutputText 严格 AND 门控', () => {
    it('sentFrom=cli + command-name → true', 0, () => {
      expect(isCliOutputText('<command-name>npm install</command-name>', 'cli')).assertTrue();
    });
    it('sentFrom=cli + local-command-stdout → true', 0, () => {
      expect(isCliOutputText('<local-command-stdout>ok</local-command-stdout>', 'cli')).assertTrue();
    });
    it('sentFrom=cli + command-args → true', 0, () => {
      expect(isCliOutputText('<command-args>--foo</command-args>', 'cli')).assertTrue();
    });
    it('sentFrom=cli 但无标签 → false（普通文本）', 0, () => {
      expect(isCliOutputText('hello world', 'cli')).assertFalse();
    });
    it('有标签但 sentFrom 非 cli → false（防普通 agent 文本误判）', 0, () => {
      expect(isCliOutputText('<command-name>npm</command-name>', '')).assertFalse();
      expect(isCliOutputText('<command-name>npm</command-name>', 'agent')).assertFalse();
    });
    it('无标签且 sentFrom 非 cli → false', 0, () => {
      expect(isCliOutputText('plain', '')).assertFalse();
    });
  });

  // —— 标签检测原语 ——
  describe('CliOutput — has*Tag 检测', () => {
    it('hasCliOutputTags 命中已知标签', 0, () => {
      expect(hasCliOutputTags('<command-name>x</command-name>')).assertTrue();
      expect(hasCliOutputTags('<local-command-stderr>err</local-command-stderr>')).assertTrue();
    });
    it('hasCliOutputTags 未命中未知标签', 0, () => {
      expect(hasCliOutputTags('<unknown-tag>x</unknown-tag>')).assertFalse();
      expect(hasCliOutputTags('plain')).assertFalse();
    });
    it('hasCommandNameTag / hasLocalCommandStdoutTag', 0, () => {
      expect(hasCommandNameTag('<command-name>x</command-name>')).assertTrue();
      expect(hasCommandNameTag('<local-command-stdout>x</local-command-stdout>')).assertFalse();
      expect(hasLocalCommandStdoutTag('<local-command-stdout>x</local-command-stdout>')).assertTrue();
      expect(hasLocalCommandStdoutTag('<command-name>x</command-name>')).assertFalse();
    });
  });

  // —— parseCliSegments：多标签混合 ——
  describe('CliOutput — parseCliSegments', () => {
    it('command-name + stdout 连续两段', 0, () => {
      const segs = parseCliSegments('<command-name>npm</command-name><local-command-stdout>added</local-command-stdout>');
      expect(segs.length).assertEqual(2);
      expect(isTagSegment(segs, 0, 'command-name')).assertTrue();
      expect(segContent(segs, 0)).assertEqual('npm');
      expect(isTagSegment(segs, 1, 'local-command-stdout')).assertTrue();
      expect(segContent(segs, 1)).assertEqual('added');
    });
    it('前导纯文本作为非标签段', 0, () => {
      const segs = parseCliSegments('Running command\n<command-name>build</command-name>');
      expect(segs.length).assertEqual(2);
      expect(segs[0].isTag).assertFalse();
      expect(segs[0].content).assertEqual('Running command');
      expect(isTagSegment(segs, 1, 'command-name')).assertTrue();
    });
    it('无闭合标签：< 作普通字符跳过，整段降级为纯文本段', 0, () => {
      // 上游 matchAll 仅匹配成对标签；未闭合的 <command-name> 不成对 →
      //   扫描器跳过该 '<'，原文（含字面标签）作为尾部纯文本段返回（不崩溃）。
      const segs = parseCliSegments('<command-name>no close');
      expect(segs.length).assertEqual(1);
      expect(segs[0].isTag).assertFalse();
      expect(segs[0].content).assertEqual('<command-name>no close');
    });
    it('command-args 段也解析', 0, () => {
      const segs = parseCliSegments('<command-args>--release</command-args>');
      expect(segs.length).assertEqual(1);
      expect(isTagSegment(segs, 0, 'command-args')).assertTrue();
      expect(segContent(segs, 0)).assertEqual('--release');
    });
  });

  // —— buildCliOutput：zh-CN 标签 + 拼接 ——
  describe('CliOutput — buildCliOutput（zh-CN）', () => {
    it('单 command-name → 命令: + 内容', 0, () => {
      expect(buildCliOutput('<command-name>npm test</command-name>')).assertEqual('命令:\nnpm test');
    });
    it('stdout → 标准输出: + 内容', 0, () => {
      expect(buildCliOutput('<local-command-stdout>ok</local-command-stdout>')).assertEqual('标准输出:\nok');
    });
    it('空内容标签 → 仅 标签:', 0, () => {
      expect(buildCliOutput('<command-name></command-name>')).assertEqual('命令:');
    });
    it('两段用空行分隔', 0, () => {
      const out = buildCliOutput('<command-name>npm</command-name><local-command-stdout>added</local-command-stdout>');
      expect(out).assertEqual('命令:\nnpm\n\n标准输出:\nadded');
    });
    it('无标签 → 归一化原文本', 0, () => {
      expect(buildCliOutput('hello')).assertEqual('hello');
    });
  });

  // —— extractCommandName：命令名取首个非空行 ——
  describe('CliOutput — extractCommandName', () => {
    it('单行命令名', 0, () => {
      expect(extractCommandName('<command-name>git status</command-name>')).assertEqual('git status');
    });
    it('多行取首非空行（trim）', 0, () => {
      expect(extractCommandName('<command-name>\n  npm\n  run\n</command-name>')).assertEqual('npm');
    });
    it('无 command-name 标签 → 空串', 0, () => {
      expect(extractCommandName('<local-command-stdout>ok</local-command-stdout>')).assertEqual('');
    });
    it('空内容 → 空串', 0, () => {
      expect(extractCommandName('<command-name></command-name>')).assertEqual('');
    });
  });

  // —— mergeCliOutputBlocks：相邻同源合并 ——
  describe('CliOutput — mergeCliOutputBlocks', () => {
    it('同源 command-name + stdout 相邻 → 合并', 0, () => {
      const prev = ChatBlock.cliOutput('a', 1, '<command-name>npm</command-name>', 'user');
      const cur = ChatBlock.cliOutput('b', 2, '<local-command-stdout>added</local-command-stdout>', 'user');
      const merged = mergeCliOutputBlocks([prev, cur]);
      expect(merged.length).assertEqual(1);
      expect(merged[0].text).assertEqual('<command-name>npm</command-name>\n<local-command-stdout>added</local-command-stdout>');
    });
    it('不同源 → 不合并（各自保留）', 0, () => {
      const prev = ChatBlock.cliOutput('a', 1, '<command-name>npm</command-name>', 'user');
      const cur = ChatBlock.cliOutput('b', 2, '<local-command-stdout>added</local-command-stdout>', 'assistant');
      const merged = mergeCliOutputBlocks([prev, cur]);
      expect(merged.length).assertEqual(2);
    });
    it('prev 已有 stdout → 不合并', 0, () => {
      const prev = ChatBlock.cliOutput('a', 1, '<command-name>npm</command-name><local-command-stdout>x</local-command-stdout>', 'user');
      const cur = ChatBlock.cliOutput('b', 2, '<local-command-stdout>y</local-command-stdout>', 'user');
      const merged = mergeCliOutputBlocks([prev, cur]);
      expect(merged.length).assertEqual(2);
    });
    it('cur 无 stdout → 不合并', 0, () => {
      const prev = ChatBlock.cliOutput('a', 1, '<command-name>npm</command-name>', 'user');
      const cur = ChatBlock.cliOutput('b', 2, '<command-name>build</command-name>', 'user');
      const merged = mergeCliOutputBlocks([prev, cur]);
      expect(merged.length).assertEqual(2);
    });
    it('非 cli-output 块穿插不参与合并', 0, () => {
      const prev = ChatBlock.cliOutput('a', 1, '<command-name>npm</command-name>', 'user');
      const agent = ChatBlock.agentText('m', 2, 'hi');
      const cur = ChatBlock.cliOutput('b', 3, '<local-command-stdout>added</local-command-stdout>', 'user');
      const merged = mergeCliOutputBlocks([prev, agent, cur]);
      expect(merged.length).assertEqual(3);
    });
    it('分隔符：prev 末尾换行则不加额外分隔', 0, () => {
      const prev = ChatBlock.cliOutput('a', 1, '<command-name>npm</command-name>\n', 'user');
      const cur = ChatBlock.cliOutput('b', 2, '<local-command-stdout>added</local-command-stdout>', 'user');
      const merged = mergeCliOutputBlocks([prev, cur]);
      expect(merged.length).assertEqual(1);
      expect(merged[0].text).assertEqual('<command-name>npm</command-name>\n<local-command-stdout>added</local-command-stdout>');
    });
  });
}
