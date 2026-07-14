// CodexReview 结构化卡片纯逻辑层（无 @kit，LocalUnit 可测；零 import 完全自含）。
//   对照上游 web/src/chat/normalizeAgent.ts:150-217（normalizeCodexReviewFinding/
//   normalizeCodexReviewJson/parseCodexReviewMessage）+ chat/types.ts:68-83 类型。
//   Codex agent 偶把 review JSON 当文本发出（data.type==='message' && typeof data.message==='string'）；
//   Reducer text 分支先嗅探（startsWith('{') 守卫），命中 → codex-review block，否则 text。
//   helper 语义对齐 @hapi/protocol asString/asNumber/isObject（非字符串/非数 → null；对象非数组）。
//   snake_case/camelCase 双写对齐上游（absolute_file_path|absoluteFilePath|path、line_range|lineRange 等）。
//   ArkTS 无 unknown → 用 Object；Record 属性经 bracket 取，缺键 → undefined；不用 in/replace/正则。

// 单条 review 发现（对照上游 CodexReviewFinding；null = 未提供）
export class CodexReviewFinding {
  title: string = '';
  body: string = '';
  priority: number | null = null;
  confidenceScore: number | null = null;
  filePath: string | null = null;
  lineStart: number | null = null;
  lineEnd: number | null = null;
}

// 整份 review（对照上游 CodexReview）
export class CodexReview {
  findings: CodexReviewFinding[] = [];
  overallCorrectness: string | null = null;
  overallExplanation: string | null = null;
  overallConfidenceScore: number | null = null;
}

// —— 内部 helper（对齐 @hapi/protocol isObject/asString/asNumber；ArkTS 无 unknown，用 Object）——

// 是否为普通对象（非 null/非数组/typeof object）→ 可安全 cast 成 Record
function isRecordValue(value: Object | undefined): boolean {
  return value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value);
}

// 字符串原样返回，非字符串 → null（'' 不特判，交由调用方按需 ! 判空）
function asStringValue(value: Object | undefined): string | null {
  return typeof value === 'string' ? value : null;
}

// 有限数返回，非数/NaN → null
function asNumberValue(value: Object | undefined): number | null {
  if (typeof value === 'number' && !Number.isNaN(value)) {
    return value;
  }
  return null;
}

// 多键回退取值（上游 `a ?? b ?? c` 链的 ArkTS 等价；bracket 取首个非 undefined）
function pickFirst(r: Record<string, Object>, keys: string[]): Object | undefined {
  for (let i = 0; i < keys.length; i++) {
    const v: Object | undefined = r[keys[i]];
    if (v !== undefined) {
      return v;
    }
  }
  return undefined;
}

// —— 解析（对照 normalizeAgent.ts:150-207）——

// 单条发现：title+body 必填；嵌套 code_location|codeLocation → path + line_range|lineRange{start,end}；
//   priority / confidence_score|confidenceScore。缺/类型不符 → null。
export function parseCodexReviewFinding(value: Object): CodexReviewFinding | null {
  if (!isRecordValue(value)) {
    return null;
  }
  const r: Record<string, Object> = value as Record<string, Object>;
  const title: string | null = asStringValue(r['title']);
  const body: string | null = asStringValue(r['body']);
  if (title === null || title === '' || body === null || body === '') {
    return null;
  }

  // 嵌套 code_location | codeLocation
  const codeLocationRaw: Object | undefined = pickFirst(r, ['code_location', 'codeLocation']);
  const codeLocation: Record<string, Object> | null = isRecordValue(codeLocationRaw)
    ? codeLocationRaw as Record<string, Object>
    : null;

  // line_range | lineRange（嵌在 codeLocation 内）
  let lineRange: Record<string, Object> | null = null;
  if (codeLocation !== null) {
    const lrRaw: Object | undefined = pickFirst(codeLocation, ['line_range', 'lineRange']);
    lineRange = isRecordValue(lrRaw) ? lrRaw as Record<string, Object> : null;
  }

  const finding: CodexReviewFinding = new CodexReviewFinding();
  finding.title = title;
  finding.body = body;
  finding.priority = asNumberValue(r['priority']);
  finding.confidenceScore = asNumberValue(pickFirst(r, ['confidence_score', 'confidenceScore']));
  if (codeLocation !== null) {
    finding.filePath = asStringValue(pickFirst(codeLocation, ['absolute_file_path', 'absoluteFilePath', 'path']));
  }
  if (lineRange !== null) {
    finding.lineStart = asNumberValue(lineRange['start']);
    finding.lineEnd = asNumberValue(lineRange['end']);
  }
  return finding;
}

// 整份 review：marker 校验（findings 数组 或任一 overall_*）；findings map+filter；全空 → null。
export function parseCodexReviewJson(value: Object): CodexReview | null {
  if (!isRecordValue(value)) {
    return null;
  }
  const r: Record<string, Object> = value as Record<string, Object>;

  // marker：findings 数组 或 overall_* 任一存在（上游 in 检查的 bracket 等价）
  const findingsRaw: Object | undefined = r['findings'];
  const hasFindings: boolean = Array.isArray(findingsRaw);
  const hasOverallCorrectness: boolean = pickFirst(r, ['overall_correctness', 'overallCorrectness']) !== undefined;
  const hasOverallExplanation: boolean = pickFirst(r, ['overall_explanation', 'overallExplanation']) !== undefined;
  const hasOverallConfidence: boolean = pickFirst(r, ['overall_confidence_score', 'overallConfidenceScore']) !== undefined;
  if (!hasFindings && !hasOverallCorrectness && !hasOverallExplanation && !hasOverallConfidence) {
    return null;
  }

  // findings：逐条解析，过滤 null
  const findings: CodexReviewFinding[] = [];
  if (hasFindings) {
    const arr: Object[] = findingsRaw as Object[];
    for (let i = 0; i < arr.length; i++) {
      const f: CodexReviewFinding | null = parseCodexReviewFinding(arr[i]);
      if (f !== null) {
        findings.push(f);
      }
    }
  }

  const overallCorrectness: string | null = asStringValue(pickFirst(r, ['overall_correctness', 'overallCorrectness']));
  const overallExplanation: string | null = asStringValue(pickFirst(r, ['overall_explanation', 'overallExplanation']));
  const overallConfidenceScore: number | null = asNumberValue(pickFirst(r, ['overall_confidence_score', 'overallConfidenceScore']));

  // 全空 → null（findings 空 + overall 三者皆空）
  if (findings.length === 0 && overallCorrectness === null && overallExplanation === null && overallConfidenceScore === null) {
    return null;
  }

  const review: CodexReview = new CodexReview();
  review.findings = findings;
  review.overallCorrectness = overallCorrectness;
  review.overallExplanation = overallExplanation;
  review.overallConfidenceScore = overallConfidenceScore;
  return review;
}

// 文本嗅探：trim + 首尾花括号守卫 + JSON.parse；非 JSON / 无 marker → null。
//   常规文本零成本（startsWith('{') 不成立即返 null）。
export function parseCodexReviewMessage(message: string): CodexReview | null {
  const trimmed: string = message.trim();
  if (!startsWithBrace(trimmed) || !endsWithBrace(trimmed)) {
    return null;
  }
  let parsed: Object;
  try {
    parsed = JSON.parse(trimmed);
  } catch (e) {
    return null;
  }
  return parseCodexReviewJson(parsed);
}

// 手写首尾判定（不用正则）：trim 后非空且首 '{' 末 '}'
function startsWithBrace(s: string): boolean {
  return s.length > 0 && charAt(s, 0) === '{';
}
function endsWithBrace(s: string): boolean {
  return s.length > 0 && charAt(s, s.length - 1) === '}';
}
function charAt(s: string, i: number): string {
  return s.substring(i, i + 1);
}

// —— 格式辅助（对照 CodexReviewCard.tsx formatPercent/formatLocation/getPriorityClassName）——

// 置信度 → 百分比串（0.42 → '42%'）；null/非有限 → null（调用方据 null 隐藏徽章）
export function formatReviewPercent(value: number | null): string | null {
  if (value === null || !Number.isFinite(value)) {
    return null;
  }
  return `${Math.round(value * 100)}%`;
}

// 位置串：filePath[:lineStart[-lineEnd]]；无 filePath → null（调用方显「无位置」）
export function formatReviewLocation(finding: CodexReviewFinding): string | null {
  if (finding.filePath === null || finding.filePath === '') {
    return null;
  }
  if (finding.lineStart === null) {
    return finding.filePath;
  }
  if (finding.lineEnd !== null && finding.lineEnd !== finding.lineStart) {
    return `${finding.filePath}:${finding.lineStart}-${finding.lineEnd}`;
  }
  return `${finding.filePath}:${finding.lineStart}`;
}

// 优先级 → 徽章配色（0/1 红、2 琥珀、余中性；null → 中性兜底）。
//   对照上游 getPriorityClassName；鸿蒙侧由组件按返回值映射 palette 色（error/warning/hint）。
export type ReviewPriorityColor = 'error' | 'warning' | 'neutral';
export function reviewPriorityColor(priority: number | null): ReviewPriorityColor {
  if (priority === 0 || priority === 1) {
    return 'error';
  }
  if (priority === 2) {
    return 'warning';
  }
  return 'neutral';
}
