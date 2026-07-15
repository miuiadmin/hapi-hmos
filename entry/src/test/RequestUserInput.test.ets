// RequestUserInput 单测 —— 对照 web/src/components/ToolCard/requestUserInput.ts parseRequestUserInputAnswers（L111-146）。
//   覆盖读回解析：嵌套 {answers:{[id]:{answers:[...]}}} 包装、扁平 {[id]:[...]}、
//   `user_note: ` 前缀剥离、selected 首个非 note 项 + trim、非 object 入参 → null。
//   input 用 JSON.parse(json) as Record<string,Object> 构造（避 ArkTS 嵌套字面量类型坑）。

import { describe, it, expect } from '@ohos/hypium';
import { parseRequestUserInputAnswers } from '../main/ets/chat/RequestUserInput';
import { RequestUserInputAnswerState } from '../main/ets/chat/RequestUserInput';

function rec(json: string): Record<string, Object> {
  return JSON.parse(json) as Record<string, Object>;
}

export default function requestUserInputTest(): void {
  describe('parseRequestUserInputAnswers — 嵌套包装 {answers:{[id]:{answers:[...]}}}', () => {
    it('selected + user_note 同时存在 → 各取其位', 0, () => {
      const input = rec('{"answers":{"q1":{"answers":["optA","user_note: hello"]}}}');
      const r = parseRequestUserInputAnswers(input);
      expect(r === null).assertFalse();
      const map = r as Record<string, RequestUserInputAnswerState>;
      expect(map['q1'].selected).assertEqual('optA');
      expect(map['q1'].userNote).assertEqual('hello');
    });
    it('仅 selected（无备注）', 0, () => {
      const input = rec('{"answers":{"q2":{"answers":["optB"]}}}');
      const r = parseRequestUserInputAnswers(input);
      const map = r as Record<string, RequestUserInputAnswerState>;
      expect(map['q2'].selected).assertEqual('optB');
      expect(map['q2'].userNote).assertEqual('');
    });
    it('仅备注（纯文本题）', 0, () => {
      const input = rec('{"answers":{"q3":{"answers":["user_note: free text"]}}}');
      const r = parseRequestUserInputAnswers(input);
      const map = r as Record<string, RequestUserInputAnswerState>;
      expect(map['q3'].selected).assertEqual('');
      expect(map['q3'].userNote).assertEqual('free text');
    });
  });

  describe('parseRequestUserInputAnswers — 扁平 {[id]:[...]} 形', () => {
    it('value 为数组 → 直取', 0, () => {
      const input = rec('{"q1":["optA","user_note: n"]}');
      const r = parseRequestUserInputAnswers(input);
      const map = r as Record<string, RequestUserInputAnswerState>;
      expect(map['q1'].selected).assertEqual('optA');
      expect(map['q1'].userNote).assertEqual('n');
    });
  });

  describe('parseRequestUserInputAnswers — 解析规则', () => {
    it('selected 与 userNote 均 trim', 0, () => {
      const input = rec('{"answers":{"q1":{"answers":["  optA  ","user_note:   spaced   "]}}}');
      const r = parseRequestUserInputAnswers(input);
      const map = r as Record<string, RequestUserInputAnswerState>;
      expect(map['q1'].selected).assertEqual('optA');
      expect(map['q1'].userNote).assertEqual('spaced');
    });
    it('备注在 selected 之前 → selected 仍取首个非 note 项', 0, () => {
      const input = rec('{"answers":{"q1":{"answers":["user_note: first","optB"]}}}');
      const r = parseRequestUserInputAnswers(input);
      const map = r as Record<string, RequestUserInputAnswerState>;
      expect(map['q1'].selected).assertEqual('optB');
      expect(map['q1'].userNote).assertEqual('first');
    });
    it('空 answers 数组 → selected/userNote 均空', 0, () => {
      const input = rec('{"answers":{"q1":{"answers":[]}}}');
      const r = parseRequestUserInputAnswers(input);
      const map = r as Record<string, RequestUserInputAnswerState>;
      expect(map['q1'].selected).assertEqual('');
      expect(map['q1'].userNote).assertEqual('');
    });
    it('value 非 object 非 array（如 number）→ 该题 selected/userNote 空（不崩）', 0, () => {
      const input = rec('{"answers":{"q1":42}}');
      const r = parseRequestUserInputAnswers(input);
      const map = r as Record<string, RequestUserInputAnswerState>;
      expect(map['q1'].selected).assertEqual('');
    });
    it('多 id 并存', 0, () => {
      const input = rec('{"answers":{"q1":{"answers":["a"]},"q2":{"answers":["user_note: n2"]}}}');
      const r = parseRequestUserInputAnswers(input);
      const map = r as Record<string, RequestUserInputAnswerState>;
      expect(map['q1'].selected).assertEqual('a');
      expect(map['q2'].selected).assertEqual('');
      expect(map['q2'].userNote).assertEqual('n2');
    });
  });

  describe('parseRequestUserInputAnswers — 非法入参', () => {
    it('数组入参 → null', 0, () => {
      const r = parseRequestUserInputAnswers(JSON.parse('[]'));
      expect(r === null).assertTrue();
    });
    it('空对象 → 空 map（非 null）', 0, () => {
      const input = rec('{}');
      const r = parseRequestUserInputAnswers(input);
      expect(r === null).assertFalse();
      const map = r as Record<string, RequestUserInputAnswerState>;
      expect(Object.keys(map).length).assertEqual(0);
    });
  });
}
