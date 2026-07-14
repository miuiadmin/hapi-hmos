// CodexReview 单测 —— 结构化卡片纯逻辑层（无 @kit，LocalUnit 可测）。
//   对照 CliOutput.test / SessionGrouping.test 范式：同步断言，构建 Record<string,Object> 输入。
//   覆盖：parseCodexReviewFinding（必填 + snake/camel 嵌套 + line_range）；
//   parseCodexReviewJson（marker / findings filter / 全空 null）；
//   parseCodexReviewMessage（非 JSON / 非 { 开头 / 命中 / trim）；
//   格式辅助 formatReviewPercent / formatReviewLocation / reviewPriorityColor 钉值。

import { describe, it, expect } from '@ohos/hypium';
import {
  CodexReviewFinding,
  parseCodexReviewFinding,
  parseCodexReviewJson,
  parseCodexReviewMessage,
  formatReviewPercent,
  formatReviewLocation,
  reviewPriorityColor
} from '../main/ets/chat/CodexReview';

export default function codexReviewTest(): void {
  describe('parseCodexReviewFinding', () => {
    it('缺 title 或 body → null', 0, () => {
      const noTitle: Record<string, Object> = { 'body': 'desc' };
      expect(parseCodexReviewFinding(noTitle)).assertNull();
      const noBody: Record<string, Object> = { 'title': 'Bug' };
      expect(parseCodexReviewFinding(noBody)).assertNull();
    });
    it('空字符串 title/body → null', 0, () => {
      const r: Record<string, Object> = { 'title': '', 'body': 'desc' };
      expect(parseCodexReviewFinding(r)).assertNull();
    });
    it('snake_case 嵌套（code_location / absolute_file_path / line_range）', 0, () => {
      const lineRange: Record<string, Object> = { 'start': 10, 'end': 20 };
      const codeLoc: Record<string, Object> = { 'absolute_file_path': '/a/b.ts', 'line_range': lineRange };
      const r: Record<string, Object> = {
        'title': 'Bug', 'body': 'desc', 'priority': 1,
        'confidence_score': 0.42, 'code_location': codeLoc
      };
      const f: CodexReviewFinding | null = parseCodexReviewFinding(r);
      expect(f).assertNotNull();
      if (f !== null) {
        expect(f.title).assertEqual('Bug');
        expect(f.body).assertEqual('desc');
        expect(f.priority).assertEqual(1);
        expect(f.confidenceScore).assertEqual(0.42);
        expect(f.filePath).assertEqual('/a/b.ts');
        expect(f.lineStart).assertEqual(10);
        expect(f.lineEnd).assertEqual(20);
      }
    });
    it('camelCase 嵌套（codeLocation / absoluteFilePath / lineRange / confidenceScore）', 0, () => {
      const lineRange: Record<string, Object> = { 'start': 5, 'end': 5 };
      const codeLoc: Record<string, Object> = { 'absoluteFilePath': '/c/d.go', 'lineRange': lineRange };
      const r: Record<string, Object> = {
        'title': 'Warn', 'body': 'b', 'confidenceScore': 0.9, 'codeLocation': codeLoc
      };
      const f: CodexReviewFinding | null = parseCodexReviewFinding(r);
      expect(f).assertNotNull();
      if (f !== null) {
        expect(f.filePath).assertEqual('/c/d.go');
        expect(f.lineStart).assertEqual(5);
        expect(f.lineEnd).assertEqual(5);
        expect(f.confidenceScore).assertEqual(0.9);
        expect(f.priority).assertNull();
      }
    });
    it('filePath 仅 path 兜底（无 absolute_*）', 0, () => {
      const codeLoc: Record<string, Object> = { 'path': '/x/y.ts' };
      const r: Record<string, Object> = { 'title': 'T', 'body': 'B', 'code_location': codeLoc };
      const f: CodexReviewFinding | null = parseCodexReviewFinding(r);
      expect(f).assertNotNull();
      if (f !== null) {
        expect(f.filePath).assertEqual('/x/y.ts');
        expect(f.lineStart).assertNull();
      }
    });
    it('非对象输入（数组/字符串）→ null', 0, () => {
      const arr: Object[] = [1, 2, 3];
      expect(parseCodexReviewFinding(arr)).assertNull();
    });
  });

  describe('parseCodexReviewJson', () => {
    it('无 marker → null', 0, () => {
      const r: Record<string, Object> = { 'foo': 'bar' };
      expect(parseCodexReviewJson(r)).assertNull();
    });
    it('findings 数组：过滤 null 子项（title/body 缺）', 0, () => {
      const good: Record<string, Object> = { 'title': 'A', 'body': 'b' };
      const bad: Record<string, Object> = { 'title': 'no body' };
      const r: Record<string, Object> = { 'findings': [good, bad] };
      const parsed = parseCodexReviewJson(r);
      expect(parsed).assertNotNull();
      if (parsed !== null) {
        expect(parsed.findings.length).assertEqual(1);
        expect(parsed.findings[0].title).assertEqual('A');
      }
    });
    it('仅 overallCorrectness（camelCase）marker → 非 null', 0, () => {
      const r: Record<string, Object> = { 'overallCorrectness': 'correct' };
      const parsed = parseCodexReviewJson(r);
      expect(parsed).assertNotNull();
      if (parsed !== null) {
        expect(parsed.overallCorrectness).assertEqual('correct');
        expect(parsed.findings.length).assertEqual(0);
      }
    });
    it('snake overall_confidence_score 解析', 0, () => {
      const r: Record<string, Object> = { 'overall_confidence_score': 0.5, 'overall_explanation': 'e' };
      const parsed = parseCodexReviewJson(r);
      expect(parsed).assertNotNull();
      if (parsed !== null) {
        expect(parsed.overallConfidenceScore).assertEqual(0.5);
        expect(parsed.overallExplanation).assertEqual('e');
      }
    });
    it('全空 marker → null（findings 空 + overall 三者皆空）', 0, () => {
      const r: Record<string, Object> = { 'findings': [], 'overall_correctness': '' };
      expect(parseCodexReviewJson(r)).assertNull();
    });
  });

  describe('parseCodexReviewMessage', () => {
    it('非 JSON → null', 0, () => {
      expect(parseCodexReviewMessage('hello world')).assertNull();
    });
    it('非 { 开头（即便合法 JSON 数组）→ null', 0, () => {
      expect(parseCodexReviewMessage('[1,2,3]')).assertNull();
    });
    it('JSON 但无 marker → null', 0, () => {
      expect(parseCodexReviewMessage('{"foo":"bar"}')).assertNull();
    });
    it('合法 review JSON（前后空白 trim）→ 命中', 0, () => {
      const json = '   {"findings":[{"title":"T","body":"B","priority":0}],"overall_correctness":"needs work"}   ';
      const parsed = parseCodexReviewMessage(json);
      expect(parsed).assertNotNull();
      if (parsed !== null) {
        expect(parsed.findings.length).assertEqual(1);
        expect(parsed.findings[0].priority).assertEqual(0);
        expect(parsed.overallCorrectness).assertEqual('needs work');
      }
    });
    it('损坏 JSON（{ 开头 } 结尾但内部非法）→ null', 0, () => {
      expect(parseCodexReviewMessage('{not valid json}')).assertNull();
    });
  });

  describe('formatReviewPercent', () => {
    it('0.42 → 42%', 0, () => {
      expect(formatReviewPercent(0.42)).assertEqual('42%');
    });
    it('0.5 → 50%（四舍五入 0.426 → 43%）', 0, () => {
      expect(formatReviewPercent(0.5)).assertEqual('50%');
      expect(formatReviewPercent(0.426)).assertEqual('43%');
    });
    it('null → null', 0, () => {
      expect(formatReviewPercent(null)).assertNull();
    });
  });

  describe('formatReviewLocation', () => {
    it('仅 filePath → filePath', 0, () => {
      const f = new CodexReviewFinding();
      f.filePath = '/a.ts';
      expect(formatReviewLocation(f)).assertEqual('/a.ts');
    });
    it('filePath:start-end（起止不同）', 0, () => {
      const f = new CodexReviewFinding();
      f.filePath = '/a.ts'; f.lineStart = 10; f.lineEnd = 20;
      expect(formatReviewLocation(f)).assertEqual('/a.ts:10-20');
    });
    it('filePath:start（起止相同）', 0, () => {
      const f = new CodexReviewFinding();
      f.filePath = '/a.ts'; f.lineStart = 7; f.lineEnd = 7;
      expect(formatReviewLocation(f)).assertEqual('/a.ts:7');
    });
    it('无 filePath → null', 0, () => {
      const f = new CodexReviewFinding();
      f.lineStart = 5;
      expect(formatReviewLocation(f)).assertNull();
    });
  });

  describe('reviewPriorityColor', () => {
    it('0/1 → error', 0, () => {
      expect(reviewPriorityColor(0)).assertEqual('error');
      expect(reviewPriorityColor(1)).assertEqual('error');
    });
    it('2 → warning', 0, () => {
      expect(reviewPriorityColor(2)).assertEqual('warning');
    });
    it('3/null → neutral', 0, () => {
      expect(reviewPriorityColor(3)).assertEqual('neutral');
      expect(reviewPriorityColor(null)).assertEqual('neutral');
    });
  });
}
