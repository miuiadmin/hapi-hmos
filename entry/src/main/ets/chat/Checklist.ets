// Checklist —— 对照 web/src/components/ToolCard/checklist.tsx
// 纯逻辑：从 TodoWrite / update_plan 的 input（优先）/ result 提取清单项。供 components/ChecklistList 渲染。

export type ChecklistStatus = 'pending' | 'in_progress' | 'completed';

export class ChecklistItem {
  id: string = '';        // '' = 无 id（用下标兜底 key）
  text: string = '';
  status: ChecklistStatus = 'pending';
}

function normalizeChecklistStatus(value: Object): ChecklistStatus {
  if (value === 'completed') {
    return 'completed';
  }
  if (value === 'in_progress') {
    return 'in_progress';
  }
  return 'pending';
}

function isNonArrayObject(v: Object): boolean {
  return v !== null && v !== undefined && typeof v === 'object' && !Array.isArray(v);
}

// entries[] → ChecklistItem[]：按 textKey 取正文、idKey（''=不取）取 id
function parseChecklistEntries(entries: Object, textKey: string, idKey: string): ChecklistItem[] {
  const items: ChecklistItem[] = [];
  if (!Array.isArray(entries)) {
    return items;
  }
  const arr: Object[] = entries as Object[];
  for (let i = 0; i < arr.length; i++) {
    const entry: Object = arr[i];
    if (!isNonArrayObject(entry)) {
      continue;
    }
    const rec: Record<string, Object> = entry as Record<string, Object>;
    const textVal: Object = rec[textKey];
    if (typeof textVal !== 'string') {
      continue;
    }
    const item: ChecklistItem = new ChecklistItem();
    item.text = textVal;
    item.status = normalizeChecklistStatus(rec['status']);
    if (idKey !== '') {
      const idVal: Object = rec[idKey];
      if (typeof idVal === 'string') {
        item.id = idVal;
      }
    }
    items.push(item);
  }
  return items;
}

// TodoWrite：input.todos（content/id/status）优先；否则 result.newTodos
export function extractTodoChecklist(input: Object | null, result: Object | null): ChecklistItem[] {
  if (isNonArrayObject(input)) {
    const rec: Record<string, Object> = input as Record<string, Object>;
    const todos: Object = rec['todos'];
    if (Array.isArray(todos)) {
      const items: ChecklistItem[] = parseChecklistEntries(todos, 'content', 'id');
      if (items.length > 0) {
        return items;
      }
    }
  }
  if (isNonArrayObject(result)) {
    const newTodos: Object = (result as Record<string, Object>)['newTodos'];
    return parseChecklistEntries(newTodos, 'content', 'id');
  }
  return [];
}

// update_plan：input.plan（step/status）优先；否则 result.plan
export function extractUpdatePlanChecklist(input: Object | null, result: Object | null): ChecklistItem[] {
  if (isNonArrayObject(input)) {
    const rec: Record<string, Object> = input as Record<string, Object>;
    const planVal: Object = rec['plan'];
    if (planVal !== undefined) {
      return parseChecklistEntries(planVal, 'step', '');
    }
  }
  if (isNonArrayObject(result)) {
    const plan: Object = (result as Record<string, Object>)['plan'];
    return parseChecklistEntries(plan, 'step', '');
  }
  return [];
}
