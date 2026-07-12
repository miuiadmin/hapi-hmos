// SlashCommands 纯逻辑单测 —— 斜杠命令补全（对照 shared/src/slashCommands.ts + web getSuggestions）
//
// 覆盖：内置命令表（claude 8 / codex / gemini / opencode-cursor 空 / 未知回退 claude）、
//       Levenshtein 距离（经典 kitten→sitting=3）、getSuggestions 评分（精确/前缀/包含/空→全部/排序/无匹配）。

import { describe, it, expect } from '@ohos/hypium';
import {
  getBuiltinSlashCommands,
  slashCommandSuggestions,
  levenshteinDistance,
  SlashCommand
} from '../main/ets/chat/SlashCommands';

function findByName(list: SlashCommand[], name: string): SlashCommand | null {
  for (let i = 0; i < list.length; i++) {
    if (list[i].name === name) { return list[i]; }
  }
  return null;
}

export default function slashCommandsTest(): void {
  describe('getBuiltinSlashCommands — 内置表', () => {
    it('claude 8 条且含 clear 描述', 0, () => {
      const list = getBuiltinSlashCommands('claude');
      expect(list.length).assertEqual(8);
      const clear = findByName(list, 'clear');
      expect(clear !== null).assertTrue();
      expect(clear!.description).assertEqual('Clear conversation history and free up context');
      expect(clear!.source).assertEqual('builtin');
    });
    it('codex / gemini 非空；opencode / cursor 空（靠 RPC）', 0, () => {
      expect(getBuiltinSlashCommands('codex').length > 0).assertTrue();
      expect(getBuiltinSlashCommands('gemini').length > 0).assertTrue();
      expect(getBuiltinSlashCommands('opencode').length).assertEqual(0);
      expect(getBuiltinSlashCommands('cursor').length).assertEqual(0);
    });
    it('未知 agent 回退 claude（对照上游 ?? claude）', 0, () => {
      expect(getBuiltinSlashCommands('foobar').length).assertEqual(8);
    });
    it('返回拷贝：改返回值不影响后续', 0, () => {
      const a = getBuiltinSlashCommands('claude');
      a[0].name = 'mutated';
      const b = getBuiltinSlashCommands('claude');
      expect(b[0].name).assertEqual('clear');
    });
  });

  describe('levenshteinDistance', () => {
    it('相同=0；空串=对端长度', 0, () => {
      expect(levenshteinDistance('abc', 'abc')).assertEqual(0);
      expect(levenshteinDistance('', 'abc')).assertEqual(3);
      expect(levenshteinDistance('abc', '')).assertEqual(3);
    });
    it('经典 kitten→sitting=3；cat→cut=1', 0, () => {
      expect(levenshteinDistance('kitten', 'sitting')).assertEqual(3);
      expect(levenshteinDistance('cat', 'cut')).assertEqual(1);
    });
  });

  describe('slashCommandSuggestions — 评分', () => {
    const claude = getBuiltinSlashCommands('claude');

    it('空查询 → 全部', 0, () => {
      expect(slashCommandSuggestions(claude, '').length).assertEqual(8);
      expect(slashCommandSuggestions(claude, '/').length).assertEqual(8);
    });
    it('精确匹配 score0 排首（/clear）', 0, () => {
      const r = slashCommandSuggestions(claude, '/clear');
      expect(r.length > 0).assertTrue();
      expect(r[0].name).assertEqual('clear');
    });
    it('前缀 /cl → 仅 clear（compact 非 cl 前缀）', 0, () => {
      const r = slashCommandSuggestions(claude, '/cl');
      expect(r.length).assertEqual(1);
      expect(r[0].name).assertEqual('clear');
    });
    it('前缀 /c → clear/compact/context/cost（均 score1，原序）', 0, () => {
      const r = slashCommandSuggestions(claude, '/c');
      expect(r.length).assertEqual(4);
      expect(r[0].name).assertEqual('clear');
      expect(r[1].name).assertEqual('compact');
      expect(r[2].name).assertEqual('context');
      expect(r[3].name).assertEqual('cost');
    });
    it('前缀 /stat → stats/status', 0, () => {
      const r = slashCommandSuggestions(claude, '/stat');
      const names = r.map((c: SlashCommand): string => c.name);
      expect(names.indexOf('stats') >= 0).assertTrue();
      expect(names.indexOf('status') >= 0).assertTrue();
    });
    it('无匹配 → 空（/zzz 编辑距超限）', 0, () => {
      expect(slashCommandSuggestions(claude, '/zzz').length).assertEqual(0);
    });
    it('精确(0) 优先于 前缀(1)：/stats', 0, () => {
      const r = slashCommandSuggestions(claude, '/stats');
      expect(r[0].name).assertEqual('stats');   // 精确 0
    });
  });
}
