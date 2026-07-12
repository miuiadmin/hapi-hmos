// Checklist 纯逻辑单测 —— 对照 web/src/components/ToolCard/checklist.test.tsx
// 上游混了逻辑用例（extractTodo/extractUpdatePlan）与渲染用例（UpdatePlanView/ChecklistList）。
// 此处只移植纯逻辑用例（ArkTS 端无 React 渲染层）；渲染由 components/ChecklistList 承担，不在单测范围。
//
// 与上游的一处必然差异：上游 ChecklistItem.id 为 undefined（未提供时）；ArkTS 类字段必须具初值，
// Checklist.ets 定义 id: string = ''，故断言改为 id === ''。语义等价（"无 id"）。

import { describe, it, expect } from '@ohos/hypium';
import {
  extractTodoChecklist,
  extractUpdatePlanChecklist,
  ChecklistItem
} from '../main/ets/chat/Checklist';

// 用 JSON 构造入参（与真实数据流一致：工具入参/结果从 JSON 解析而来），避免大量对象字面量样板
function rec(json: string): Record<string, Object> {
  return JSON.parse(json) as Record<string, Object>;
}

// ChecklistItem → 可读签名 'text|status|id'，便于整体断言
function itemsSig(items: ChecklistItem[]): string {
  const parts: string[] = [];
  for (let i = 0; i < items.length; i++) {
    const it: ChecklistItem = items[i];
    parts.push(`${it.text}|${it.status}|${it.id}`);
  }
  return parts.join(',');
}

export default function checklistTest(): void {
  describe('extractUpdatePlanChecklist', () => {
    // 上游：「prefers input.plan over result.plan」
    it('prefers input.plan over result.plan', 0, () => {
      const input = rec('{"plan":[{"step":"Patch root cause","status":"completed"}]}');
      const result = rec('{"plan":[{"step":"Result fallback","status":"pending"}]}');
      const items: ChecklistItem[] = extractUpdatePlanChecklist(input, result);
      expect(items.length).assertEqual(1);
      expect(items[0].text).assertEqual('Patch root cause');
      expect(items[0].status).assertEqual('completed');
      expect(items[0].id).assertEqual(''); // update_plan 的 idKey=''，不取 id
    });

    // 上游：「falls back to result.plan when input.plan is absent」
    it('falls back to result.plan when input.plan is absent', 0, () => {
      const input = rec('{}');
      const result = rec('{"plan":[{"step":"Re-run build validation","status":"in_progress"}]}');
      const items: ChecklistItem[] = extractUpdatePlanChecklist(input, result);
      expect(itemsSig(items)).assertEqual('Re-run build validation|in_progress|');
    });

    // 上游：「keeps valid steps and normalizes unknown status to pending」
    it('keeps valid steps and normalizes unknown status to pending', 0, () => {
      // step 非字符串（123）、缺 step 的项被丢弃；未知 status → pending
      const input = rec('{"plan":[{"step":"Summarize fix","status":"unknown_status"},' +
        '{"step":123,"status":"completed"},' +
        '{"status":"pending"}]}');
      const items: ChecklistItem[] = extractUpdatePlanChecklist(input, null);
      expect(itemsSig(items)).assertEqual('Summarize fix|pending|');
    });

    it('returns an empty array when neither input nor result has a plan', 0, () => {
      expect(extractUpdatePlanChecklist(null, null).length).assertEqual(0);
      expect(extractUpdatePlanChecklist(rec('{}'), rec('{}')).length).assertEqual(0);
    });

    it('preserves completed and in_progress statuses verbatim', 0, () => {
      const input = rec('{"plan":[' +
        '{"step":"done","status":"completed"},' +
        '{"step":"now","status":"in_progress"},' +
        '{"step":"later","status":"pending"}]}');
      const items: ChecklistItem[] = extractUpdatePlanChecklist(input, null);
      expect(itemsSig(items)).assertEqual('done|completed|,now|in_progress|,later|pending|');
    });
  });

  describe('extractTodoChecklist', () => {
    // 上游：「uses result.newTodos when input.todos is unavailable」
    it('uses result.newTodos when input.todos is unavailable', 0, () => {
      const result = rec('{"newTodos":[{"id":"todo-1","content":"Ship it","status":"completed"}]}');
      const items: ChecklistItem[] = extractTodoChecklist(null, result);
      expect(itemsSig(items)).assertEqual('Ship it|completed|todo-1');
    });

    it('prefers input.todos over result.newTodos', 0, () => {
      const input = rec('{"todos":[{"id":"a","content":"from input","status":"in_progress"}]}');
      const result = rec('{"newTodos":[{"id":"b","content":"from result","status":"pending"}]}');
      const items: ChecklistItem[] = extractTodoChecklist(input, result);
      expect(itemsSig(items)).assertEqual('from input|in_progress|a');
    });

    it('falls back to result.newTodos when input.todos is present but empty', 0, () => {
      // input.todos 为空数组 → 解析得 0 项（length 不 >0）→ 回退 result.newTodos
      const input = rec('{"todos":[]}');
      const result = rec('{"newTodos":[{"id":"x","content":"fallback","status":"pending"}]}');
      const items: ChecklistItem[] = extractTodoChecklist(input, result);
      expect(itemsSig(items)).assertEqual('fallback|pending|x');
    });

    it('ignores a non-array input.todos and falls back to result.newTodos', 0, () => {
      const input = rec('{"todos":"not-an-array"}');
      const result = rec('{"newTodos":[{"id":"x","content":"fallback","status":"pending"}]}');
      const items: ChecklistItem[] = extractTodoChecklist(input, result);
      expect(itemsSig(items)).assertEqual('fallback|pending|x');
    });

    it('returns an empty array when both input.todos and result.newTodos are missing', 0, () => {
      expect(extractTodoChecklist(null, null).length).assertEqual(0);
    });

    it('drops todo entries whose content is not a string', 0, () => {
      const input = rec('{"todos":[' +
        '{"id":"a","content":"keep","status":"completed"},' +
        '{"id":"b","content":123,"status":"pending"},' +
        '{"id":"c","status":"pending"}]}');
      const items: ChecklistItem[] = extractTodoChecklist(input, null);
      expect(itemsSig(items)).assertEqual('keep|completed|a');
    });
  });
}
