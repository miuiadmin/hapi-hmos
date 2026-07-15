// Codex plan_update 解析纯逻辑层（无 @kit，LocalUnit 可测）。
//   对照上游 web/src/chat/normalizeAgent.ts:110-148（normalizePlanStatus / normalizePlanEntries）。
//   Codex agent 发 data.type==='plan_update'，计划项在 data.plan / data.update / data.items /
//   data.steps（或对象本身）。本层把任意结构归一成 Array<{step, status}>，供 Message.ets
//   extractAgentBlocks 合成 update_plan 工具卡（input.plan）。端口 update_plan 卡的
//   extractUpdatePlanChecklist 读 input.plan 渲染清单，故 {step, status} 形状与 TodoWrite 一致即可。
//
// ArkTS 限制：上游 normalizePlanStatus 用 trim().toLowerCase().replace(/[\s-]/g,'_') 的正则 +
//   replace-fn，ArkTS 禁用 → 手写字符扫描器（ASCII 小写 + 空白/连字符 → 下划线），纯函数无 replace-fn。

// 计划项（status ∈ 'pending' | 'in_progress' | 'completed'，对照 normalizePlanEntries 返回类型）
export class PlanEntry {
  step: string = '';
  status: string = '';   // 'pending' | 'in_progress' | 'completed'
}

// 单字符是否空白（space/tab/nl/cr）
function isWsChar(ch: string): boolean {
  return ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r';
}

// ASCII 小写：仅 A-Z → a-z（charCode ±32），其余原样。对照 toLowerCase 的 ASCII 子集
//   （上游用于归一 status 取值；非 ASCII 不会出现在 status 里）。
function asciiLower(ch: string): string {
  const c: number = ch.charCodeAt(0);
  if (c >= 65 && c <= 90) {            // 'A'..'Z'
    return String.fromCharCode(c + 32);
  }
  return ch;
}

// 状态归一（对照 normalizeAgent.ts:110-115 normalizePlanStatus）。
//   上游：trim + toLowerCase + 把 [\s-] 替换为 '_'；再 completed/complete/done → completed，
//   in_progress/inprogress/active/running → in_progress，其余 → pending。
export function normalizePlanStatus(value: Object): string {
  if (typeof value !== 'string') {
    return 'pending';
  }
  const s: string = value as string;
  // trim 首尾空白
  let start: number = 0;
  let end: number = s.length;
  while (start < end && isWsChar(s.charAt(start))) {
    start++;
  }
  while (end > start && isWsChar(s.charAt(end - 1))) {
    end--;
  }
  // 逐字符小写 + 空白/连字符 → 下划线
  let raw: string = '';
  for (let i = start; i < end; i++) {
    const ch: string = s.charAt(i);
    if (isWsChar(ch) || ch === '-') {
      raw += '_';
    } else {
      raw += asciiLower(ch);
    }
  }
  if (raw === 'completed' || raw === 'complete' || raw === 'done') {
    return 'completed';
  }
  if (raw === 'in_progress' || raw === 'inprogress' || raw === 'active' || raw === 'running') {
    return 'in_progress';
  }
  return 'pending';
}

// 取对象上首个非空字符串字段（对照上游 asString(entry.step) ?? asString(entry.content) ?? …）。
//   手写避免 ?? 链的 string|undefined 类型坑；任一字段是字符串且非空即返回，否则 ''。
function firstNonEmptyStr(rec: Record<string, Object>, keys: string[]): string {
  for (let i = 0; i < keys.length; i++) {
    const v: Object = rec[keys[i]];
    if (typeof v === 'string' && (v as string) !== '') {
      return v as string;
    }
  }
  return '';
}

// 计划项归一（对照 normalizeAgent.ts:117-148 normalizePlanEntries）。
//   entries 源：value 是数组 → value；否则 value 是对象 → value.plan / value.items / value.steps
//   （首个数组）；否则 []。逐条：字符串 → {step, status:'pending'}；对象 → step 取
//   step/content/text/title/description 首个非空，status 取 status ?? state 经 normalizePlanStatus；
//   step 空 → 跳过。
export function normalizePlanEntries(value: Object): PlanEntry[] {
  const plan: PlanEntry[] = [];

  // 解析 entries 源数组
  let entries: Object[] | null = null;
  if (Array.isArray(value)) {
    entries = value as Object[];
  } else if (value !== null && value !== undefined && typeof value === 'object') {
    const rec: Record<string, Object> = value as Record<string, Object>;
    const planVal: Object = rec['plan'];
    const itemsVal: Object = rec['items'];
    const stepsVal: Object = rec['steps'];
    if (Array.isArray(planVal)) {
      entries = planVal as Object[];
    } else if (Array.isArray(itemsVal)) {
      entries = itemsVal as Object[];
    } else if (Array.isArray(stepsVal)) {
      entries = stepsVal as Object[];
    }
  }
  if (entries === null) {
    return plan;
  }

  const stepKeys: string[] = ['step', 'content', 'text', 'title', 'description'];
  for (let i = 0; i < entries.length; i++) {
    const entry: Object = entries[i];
    if (typeof entry === 'string') {
      const stepStr: string = entry as string;
      if (stepStr !== '') {
        const e: PlanEntry = new PlanEntry();
        e.step = stepStr;
        e.status = 'pending';
        plan.push(e);
      }
      continue;
    }
    if (entry === null || entry === undefined || typeof entry !== 'object') {
      continue;
    }
    const rec: Record<string, Object> = entry as Record<string, Object>;
    const step: string = firstNonEmptyStr(rec, stepKeys);
    if (step === '') {
      continue;
    }
    const e: PlanEntry = new PlanEntry();
    e.step = step;
    // status ?? state（首个非 undefined/null 者交 normalizePlanStatus）
    const sv: Object = rec['status'];
    const stv: Object = rec['state'];
    const statusVal: Object = (sv !== undefined && sv !== null) ? sv : stv;
    e.status = normalizePlanStatus(statusVal);
    plan.push(e);
  }
  return plan;
}
