// AskUserQuestion 单测 —— 对照 web/src/components/ToolCard/askUserQuestion.ts。
//   覆盖：hasStructuredAnswers（结果段去重判定；dual-format flat/nested 只看键数）、
//   isAskUserQuestionToolName（工具名判别）、parseAskUserQuestionInput（题目/选项解析回归）。
//   文案/结构随 input —— 用 JSON.parse(json) as Record<string,Object> 构造（避嵌套字面量类型坑）。

import { describe, it, expect } from '@ohos/hypium';
import {
  isAskUserQuestionToolName,
  hasStructuredAnswers,
  parseAskUserQuestionInput
} from '../main/ets/chat/AskUserQuestion';
import { ChatToolCall, ToolPermission } from '../main/ets/chat/ChatBlock';

function rec(json: string): Record<string, Object> {
  return JSON.parse(json) as Record<string, Object>;
}

// 构造带 permission.answers 的 AskUserQuestion 工具（answers 可 null）
function mkWithAnswers(answers: Record<string, Object> | null): ChatToolCall {
  const tool: ChatToolCall = new ChatToolCall();
  tool.name = 'AskUserQuestion';
  const p: ToolPermission = new ToolPermission();
  p.answers = answers;
  tool.permission = p;
  return tool;
}

// 无 permission 的工具（permission=null）
function mkNoPermission(): ChatToolCall {
  const tool: ChatToolCall = new ChatToolCall();
  tool.name = 'AskUserQuestion';
  return tool;
}

export default function askUserQuestionTest(): void {
  describe('AskUserQuestion — isAskUserQuestionToolName', () => {
    it("AskUserQuestion → true", 0, () => {
      expect(isAskUserQuestionToolName('AskUserQuestion')).assertTrue();
    });
    it("ask_user_question → true（CLI 蛇形透传）", 0, () => {
      expect(isAskUserQuestionToolName('ask_user_question')).assertTrue();
    });
    it('其它工具名 → false', 0, () => {
      expect(isAskUserQuestionToolName('Bash')).assertFalse();
      expect(isAskUserQuestionToolName('request_user_input')).assertFalse();
      expect(isAskUserQuestionToolName('')).assertFalse();
    });
  });

  describe('AskUserQuestion — hasStructuredAnswers', () => {
    it('flat answers 有键 → true', 0, () => {
      const tool = mkWithAnswers(rec('{"0":["A","B"]}'));
      expect(hasStructuredAnswers(tool)).assertTrue();
    });
    it('nested answers 有键 → true（dual-format 只看键数）', 0, () => {
      const tool = mkWithAnswers(rec('{"0":{"answers":["A"]}}'));
      expect(hasStructuredAnswers(tool)).assertTrue();
    });
    it('空对象 → false（无键）', 0, () => {
      const tool = mkWithAnswers(rec('{}'));
      expect(hasStructuredAnswers(tool)).assertFalse();
    });
    it('answers null → false', 0, () => {
      const tool = mkWithAnswers(null);
      expect(hasStructuredAnswers(tool)).assertFalse();
    });
    it('permission null → false', 0, () => {
      expect(hasStructuredAnswers(mkNoPermission())).assertFalse();
    });
  });

  describe('AskUserQuestion — parseAskUserQuestionInput（回归）', () => {
    it('单题多选项 → 解析 question/header/multiSelect/options', 0, () => {
      const input = rec('{"questions":[{"header":"范围","question":"选哪些？","multiSelect":true,"options":[{"label":"A","description":"甲"},{"label":"B"}]}]}');
      const qs = parseAskUserQuestionInput(input);
      expect(qs.length).assertEqual(1);
      expect(qs[0].header).assertEqual('范围');
      expect(qs[0].question).assertEqual('选哪些？');
      expect(qs[0].multiSelect).assertTrue();
      expect(qs[0].options.length).assertEqual(2);
      expect(qs[0].options[0].label).assertEqual('A');
      expect(qs[0].options[0].description).assertEqual('甲');
      expect(qs[0].options[1].description).assertEqual('');
    });
    it('空 label 选项丢弃；multiSelect 缺省 false', 0, () => {
      const input = rec('{"questions":[{"question":"q?","options":[{"label":"  "},{"label":"ok"}]}]}');
      const qs = parseAskUserQuestionInput(input);
      expect(qs.length).assertEqual(1);
      expect(qs[0].options.length).assertEqual(1);
      expect(qs[0].options[0].label).assertEqual('ok');
      expect(qs[0].multiSelect).assertFalse();
    });
    it('无 question 且无有效选项 → 整题丢弃', 0, () => {
      const input = rec('{"questions":[{"options":[{"label":"  "}]}]}');
      expect(parseAskUserQuestionInput(input).length).assertEqual(0);
    });
    it('非 questions 数组 → []', 0, () => {
      expect(parseAskUserQuestionInput(rec('{"foo":1}')).length).assertEqual(0);
    });
    it('null input → []', 0, () => {
      expect(parseAskUserQuestionInput(null).length).assertEqual(0);
    });
  });
}
