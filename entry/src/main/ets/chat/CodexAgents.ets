// CodexAgents —— 对照 web/src/components/ToolCard/codexAgents.ts
// 纯层（零 @kit）：Codex 子代理集群（spawn_agent / send_input / resume_agent / wait_agent / close_agent / CodexAgent）
//   的入参/结果解析 + 展示文案 helper。供 Presentation（头/副标题）、ToolCardViews（body/结果）共用。
// 输出串经 Translate.t 本地化（reasoning effort label / state 计数等裸英 loanword 不译，同上游）。
// '' 哨兵表 null；type-guard→裸 boolean + cast；Object.entries→Object.keys；全部正则→手写扫描器（ArkTS 严格）。

import { getInputStrAny, truncateStr } from './ToolInputUtils';
import { t } from '../i18n/Translate';

// ===== 类型（替 TS type；'' 哨兵表 null）=====

export class CodexSpawnAgentResult {
  agentId: string = '';
  nickname: string = '';
}

export class CodexAgentStatus {
  agentId: string = '';
  state: string = '';
  text: string = '';      // '' = null
}

// wait_agent 解析结果。timedOut=false 兼表「缺席/假」——summary 只查真值（缺席即假），等价。
export class CodexWaitAgentResult {
  statuses: CodexAgentStatus[] = [];
  timedOut: boolean = false;
}

export class AgentFieldRow {
  label: string = '';
  value: string = '';
}

// ===== 内部 helper =====

// 是否普通对象（非 null / 非数组 / typeof object）
function isRecord(v: Object | null | undefined): boolean {
  return v !== null && v !== undefined && typeof v === 'object' && !Array.isArray(v);
}

// 非空字符串 → 原值；否则 ''（替 asNonEmptyString 的 null）
function asNonEmptyStr(v: Object | null | undefined): string {
  if (typeof v === 'string' && v.trim().length > 0) {
    return v;
  }
  return '';
}

// 布尔 → 'true'/'false'；否则 ''（替 asBooleanLabel 的 null）
function asBoolLabel(v: Object | null | undefined): string {
  return typeof v === 'boolean' ? (v ? 'true' : 'false') : '';
}

// a 非空取 a，否则取 b（替 ?? 链：'' 在 ?? 下不触发，需显式哨兵）
function firstNonEmpty(a: string, b: string): string {
  return a !== '' ? a : b;
}

function mkFieldRow(label: string, value: string): AgentFieldRow {
  const r: AgentFieldRow = new AgentFieldRow();
  r.label = label;
  r.value = value;
  return r;
}

// 是否空白符（\s：space/tab/LF/CR/FF/VT）—— compactText / 行处理共用
function isWsChar(code: number): boolean {
  return code === 32 /* space */ || code === 9 /* \t */ || code === 10 /* \n */
    || code === 13 /* \r */ || code === 12 /* \f */ || code === 11 /* \v */;
}

// 是否词字符 [A-Za-z0-9_] —— normalizeNonTerminalCodexAgentActivity \b 判定用
function isWordChar(code: number): boolean {
  return (code >= 48 && code <= 57) /* 0-9 */
    || (code >= 65 && code <= 90) /* A-Z */
    || (code >= 97 && code <= 122) /* a-z */
    || code === 95; /* _ */
}

// 折叠连续空白为单空格 + trim（替 /\s+/g → ' ' + trim）。逐 char 扫描：遇空白登记待出空格，
//   遇非空白先补一个空格（若有挂起）再补该字符——天然去首尾空白。
function compactText(text: string): string {
  const out: string[] = [];
  let pendingSpace: boolean = false;
  for (let i = 0; i < text.length; i++) {
    if (isWsChar(text.charCodeAt(i))) {
      pendingSpace = true;
    } else {
      if (pendingSpace) {
        out.push(' ');
        pendingSpace = false;
      }
      out.push(text.charAt(i));
    }
  }
  return out.join('');
}

// 替 <[^>\n]+>/g → ' '：找 '<'，其后至少 1 个非 '>'/非 '\n' 字符直到 '>'，整段替一个空格；无闭合则 '<' 字面保留
function stripAngleTags(prompt: string): string {
  const out: string[] = [];
  let i: number = 0;
  while (i < prompt.length) {
    if (prompt.charAt(i) === '<') {
      let j: number = i + 1;
      let closeIdx: number = -1;
      let contentLen: number = 0;
      while (j < prompt.length) {
        const cj: string = prompt.charAt(j);
        if (cj === '\n') {
          break;
        }
        if (cj === '>') {
          closeIdx = j;
          break;
        }
        contentLen++;
        j++;
      }
      if (closeIdx >= 0 && contentLen >= 1) {
        out.push(' ');
        i = closeIdx + 1;
        continue;
      }
    }
    out.push(prompt.charAt(i));
    i++;
  }
  return out.join('');
}

// \r → \n（手写，替 /\r/g）
function crToNewline(s: string): string {
  if (s.indexOf('\r') < 0) {
    return s;
  }
  const out: string[] = [];
  for (let i = 0; i < s.length; i++) {
    out.push(s.charAt(i) === '\r' ? '\n' : s.charAt(i));
  }
  return out.join('');
}

// 剥行首 '-'/'*' + 至少 1 空白（替 /^[-*]\s+/）
function stripLeadingBullet(line: string): string {
  if (line.length === 0) {
    return line;
  }
  const first: string = line.charAt(0);
  if (first !== '-' && first !== '*') {
    return line;
  }
  let j: number = 1;
  while (j < line.length && isWsChar(line.charCodeAt(j))) {
    j++;
  }
  return j > 1 ? line.substring(j) : line;
}

// 剥行首 1-6 个 '#' + 至少 1 空白（替 /^#{1,6}\s+/）。7+ 个 '#' 不匹配（同正则）
function stripLeadingHeading(line: string): string {
  if (line.length === 0 || line.charAt(0) !== '#') {
    return line;
  }
  let count: number = 0;
  let j: number = 0;
  while (j < line.length && line.charAt(j) === '#' && count < 6) {
    count++;
    j++;
  }
  let ws: number = j;
  while (ws < line.length && isWsChar(line.charCodeAt(ws))) {
    ws++;
  }
  if (count < 1 || count > 6 || ws <= j) {
    return line;
  }
  return line.substring(ws);
}

// 噪声短语（小写，逐行 indexOf 命中即滤）—— 替 8 条 /i 正则 .test
const AGENT_PROMPT_NOISE: string[] = [
  'not alone in the codebase',
  'do not revert',
  "don't revert",
  'list the file paths',
  'changed files',
  'final answer',
  'avoid merge conflicts',
  'accommodate the changes'
];

// 剥串首 task/your task/request/prompt + 可选空白 + ':' + 可选空白（大小写不敏感，替 /^(task|your task|request|prompt)\s*[:：]\s*/i）
//   注：上游正则用 ASCII ':'（非全角 '：'），此处忠实只判 ':'。
function stripLeadingLabel(s: string): string {
  const lower: string = s.toLowerCase();
  const labels: string[] = ['task', 'your task', 'request', 'prompt'];
  for (let i = 0; i < labels.length; i++) {
    const label: string = labels[i];
    if (!lower.startsWith(label)) {
      continue;
    }
    let j: number = label.length;
    while (j < lower.length && isWsChar(lower.charCodeAt(j))) {
      j++;
    }
    if (j >= lower.length || lower.charAt(j) !== ':') {
      continue;
    }
    j++;
    while (j < lower.length && isWsChar(lower.charCodeAt(j))) {
      j++;
    }
    return s.substring(j);
  }
  return s;
}

// 清洗 prompt 供摘要（替 cleanAgentPromptForSummary 的全部正则链）
function cleanAgentPromptForSummary(prompt: string): string {
  const stripped: string = crToNewline(stripAngleTags(prompt));
  const rawLines: string[] = stripped.split('\n');
  const kept: string[] = [];
  for (let i = 0; i < rawLines.length; i++) {
    let line: string = rawLines[i].trim();
    line = stripLeadingBullet(line);
    line = stripLeadingHeading(line);
    if (line.length === 0) {
      continue;
    }
    const lower: string = line.toLowerCase();
    let isNoise: boolean = false;
    for (let k = 0; k < AGENT_PROMPT_NOISE.length; k++) {
      if (lower.indexOf(AGENT_PROMPT_NOISE[k]) >= 0) {
        isNoise = true;
        break;
      }
    }
    if (isNoise) {
      continue;
    }
    kept.push(line);
  }
  const candidate: string = kept.length > 0 ? kept.join(' ') : stripped;
  return stripLeadingLabel(compactText(candidate));
}

// 取 agent 状态串（agentStatus/status/state → trim+小写）
function getCodexAgentStatus(input: Record<string, Object> | null): string {
  const status: string = getInputStrAny(input, ['agentStatus', 'status', 'state']);
  return status !== '' ? status.trim().toLowerCase() : '';
}

// 是否终态（completed/failed/error/canceled/cancelled）
function isTerminalCodexAgentStatus(status: string): boolean {
  return status === 'completed' || status === 'failed' || status === 'error'
    || status === 'canceled' || status === 'cancelled';
}

// 非终态活动文案归一（替 4 条 /i 前缀替换 + Array<[RegExp,string]>，顺序匹配首中即返）
function normalizeNonTerminalCodexAgentActivity(activity: string): string {
  const lower: string = activity.toLowerCase();
  // 1) ^Command completed\b → 'Command finished' + 余
  if (lower.startsWith('command completed')) {
    const after: number = 17;   // 'command completed'.length（after 指向后随首字符，做 \b 判定）
    if (after >= lower.length || !isWordChar(lower.charCodeAt(after))) {
      return 'Command finished' + activity.substring(after);
    }
  }
  // 2) ^Tool completed\b → 'Tool finished' + 余
  if (lower.startsWith('tool completed')) {
    const after: number = 14;   // 'tool completed'.length
    if (after >= lower.length || !isWordChar(lower.charCodeAt(after))) {
      return 'Tool finished' + activity.substring(after);
    }
  }
  // 3) ^Completed\s*:\s* → 'Output ready: ' + 余
  if (lower.startsWith('completed')) {
    let j: number = 9;          // 'completed'.length（j 指向后随首字符，做 \s*:\s* 扫描）
    while (j < lower.length && isWsChar(lower.charCodeAt(j))) {
      j++;
    }
    if (j < lower.length && lower.charAt(j) === ':') {
      j++;
      while (j < lower.length && isWsChar(lower.charCodeAt(j))) {
        j++;
      }
      return 'Output ready: ' + activity.substring(j);
    }
  }
  // 4) ^Completed$ → 'Running'（整串 === completed）
  if (lower === 'completed') {
    return 'Running';
  }
  return activity;
}

// ===== 导出 helper =====

// 对象 / 形如 '{...}' 的串 → 解析为对象；否则 null
export function parseMaybeJsonObject(value: Object | null): Record<string, Object> | null {
  if (isRecord(value)) {
    return value as Record<string, Object>;
  }
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed: string = value.trim();
  if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
    return null;
  }
  try {
    const parsed: Object = JSON.parse(trimmed);
    return isRecord(parsed) ? parsed as Record<string, Object> : null;
  } catch (e) {
    return null;
  }
}

// prompt 全文：message/prompt；否则 items[].text 以空行拼接。'' = 无
export function getCodexAgentPrompt(input: Record<string, Object> | null): string {
  const direct: string = getInputStrAny(input, ['message', 'prompt']);
  if (direct !== '') {
    return direct;
  }
  if (input === null) {
    return '';
  }
  const items: Object = input['items'];
  if (!Array.isArray(items)) {
    return '';
  }
  const arr: Object[] = items as Object[];
  const parts: string[] = [];
  for (let i = 0; i < arr.length; i++) {
    const item: Object = arr[i];
    if (isRecord(item)) {
      const txt: Object = (item as Record<string, Object>)['text'];
      if (typeof txt === 'string') {
        const trimmed: string = (txt as string).trim();
        if (trimmed.length > 0) {
          parts.push(trimmed);
        }
      }
    }
  }
  return parts.length > 0 ? parts.join('\n\n') : '';
}

// prompt 摘要：清洗后截断（默认 80）。'' = 无
export function summarizeCodexAgentPrompt(prompt: string, max: number = 80): string {
  const cleaned: string = cleanAgentPromptForSummary(prompt);
  if (cleaned === '') {
    return '';
  }
  return truncateStr(cleaned, max);
}

// 摘要：显式 summary/title/description → 折叠截 80；否则 prompt 摘要；否则 `{type} agent`。'' = 无
export function getCodexAgentSummary(input: Record<string, Object> | null): string {
  const explicit: string = getInputStrAny(input, ['summary', 'title', 'description']);
  if (explicit !== '') {
    return truncateStr(compactText(explicit), 80);
  }
  const prompt: string = getCodexAgentPrompt(input);
  if (prompt !== '') {
    const summary: string = summarizeCodexAgentPrompt(prompt);
    if (summary !== '') {
      return summary;
    }
  }
  const agentType: string = getCodexAgentType(input);
  return agentType !== '' ? `${agentType} agent` : '';
}

// 活动文案：终态原样，非终态归一。'' = 无
export function getCodexAgentActivity(input: Record<string, Object> | null): string {
  const activity: string = getInputStrAny(input, ['activity', 'statusText', 'status_text', 'agentStatus']);
  if (activity === '') {
    return '';
  }
  const status: string = getCodexAgentStatus(input);
  return isTerminalCodexAgentStatus(status) ? activity : normalizeNonTerminalCodexAgentActivity(activity);
}

export function getCodexAgentReasoningEffort(input: Record<string, Object> | null): string {
  return getInputStrAny(input, ['reasoning_effort', 'reasoningEffort']);
}

// reasoning effort 标签（裸英 loanword，不译）：default/缺→'reasoning default'，余→'reasoning X'
export function formatCodexAgentReasoningEffort(effort: string): string {
  const normalized: string = effort.trim().toLowerCase();
  if (normalized === '' || normalized === 'default') {
    return 'reasoning default';
  }
  return `reasoning ${normalized}`;
}

export function getCodexAgentReasoningEffortLabel(input: Record<string, Object> | null): string {
  const effort: string = getCodexAgentReasoningEffort(input);
  return effort !== '' ? formatCodexAgentReasoningEffort(effort) : '';
}

export function getCodexAgentType(input: Record<string, Object> | null): string {
  return getInputStrAny(input, ['agent_type', 'subagent_type', 'type']);
}

// 目标列表：targets[] 滤串（>0 即返）；否则 target/id/agent_id/agentId 滤串
export function getCodexAgentTargets(input: Record<string, Object> | null): string[] {
  if (input === null) {
    return [];
  }
  const targetsRaw: Object = input['targets'];
  if (Array.isArray(targetsRaw)) {
    const arr: Object[] = targetsRaw as Object[];
    const out: string[] = [];
    for (let i = 0; i < arr.length; i++) {
      if (typeof arr[i] === 'string' && (arr[i] as string).length > 0) {
        out.push(arr[i] as string);
      }
    }
    if (out.length > 0) {
      return out;
    }
  }
  const candidates: Object[] = [input['target'], input['id'], input['agent_id'], input['agentId']];
  const direct: string[] = [];
  for (let i = 0; i < candidates.length; i++) {
    if (typeof candidates[i] === 'string' && (candidates[i] as string).length > 0) {
      direct.push(candidates[i] as string);
    }
  }
  return direct;
}

// 字段行（label 本地化）：Agent/Status/Work/Type/Model/Reasoning/Fork context/Timeout/Targets
export function getCodexAgentFieldRows(toolName: string, input: Record<string, Object> | null): AgentFieldRow[] {
  const rows: AgentFieldRow[] = [];
  if (input !== null) {
    const agentId: string = firstNonEmpty(asNonEmptyStr(input['agentId']), asNonEmptyStr(input['agent_id']));
    if (agentId !== '') {
      rows.push(mkFieldRow(t('agent.field.agent'), agentId));
    }
  }
  const statusText: string = getCodexAgentActivity(input);
  if (statusText !== '') {
    rows.push(mkFieldRow(t('agent.field.status'), statusText));
  }
  const summary: string = getCodexAgentSummary(input);
  if (summary !== '') {
    rows.push(mkFieldRow(t('agent.field.work'), summary));
  }
  const agentType: string = getCodexAgentType(input);
  if (agentType !== '') {
    rows.push(mkFieldRow(t('agent.field.type'), agentType));
  }
  const model: string = getInputStrAny(input, ['model']);
  if (model !== '') {
    rows.push(mkFieldRow(t('agent.field.model'), model));
  }
  const effort: string = getCodexAgentReasoningEffort(input);
  if (effort !== '') {
    rows.push(mkFieldRow(t('agent.field.reasoning'), effort));
  }
  if (input !== null) {
    const forkLabel: string = asBoolLabel(input['fork_context']);
    if (forkLabel !== '') {
      rows.push(mkFieldRow(t('agent.field.forkContext'), forkLabel));
    }
    const to: Object = input['timeout_ms'];
    if (typeof to === 'number') {
      rows.push(mkFieldRow(t('agent.field.timeout'), `${to} ms`));
    }
  }
  const targets: string[] = getCodexAgentTargets(input);
  if (targets.length > 0) {
    const label: string = targets.length === 1
      ? (toolName === 'resume_agent' ? t('agent.field.agent') : t('agent.field.target'))
      : t('agent.field.targets');
    rows.push(mkFieldRow(label, targets.join(', ')));
  }
  return rows;
}

// ===== 结果解析 =====

export function parseCodexSpawnAgentResult(result: Object | null): CodexSpawnAgentResult | null {
  const obj: Record<string, Object> | null = parseMaybeJsonObject(result);
  if (obj === null) {
    return null;
  }
  const agentId: string = firstNonEmpty(
    firstNonEmpty(asNonEmptyStr(obj['agent_id']), asNonEmptyStr(obj['agentId'])),
    asNonEmptyStr(obj['id']));
  const nickname: string = firstNonEmpty(asNonEmptyStr(obj['nickname']), asNonEmptyStr(obj['name']));
  if (agentId === '' && nickname === '') {
    return null;
  }
  const r: CodexSpawnAgentResult = new CodexSpawnAgentResult();
  r.agentId = agentId;
  r.nickname = nickname;
  return r;
}

// 状态文本提取：string→原值；对象按 completed/failed/error/message/output/text/reason 取首串；否则 JSON 序列化
function extractStatusText(value: Object | null): string {
  if (typeof value === 'string') {
    return value;
  }
  if (!isRecord(value)) {
    return '';
  }
  const rec: Record<string, Object> = value as Record<string, Object>;
  const candidates: string[] = ['completed', 'failed', 'error', 'message', 'output', 'text', 'reason'];
  for (let i = 0; i < candidates.length; i++) {
    const v: Object = rec[candidates[i]];
    if (typeof v === 'string') {
      return v;
    }
  }
  try {
    return JSON.stringify(value);
  } catch (e) {
    return '';
  }
}

// 状态值判定：按 key 存在性优先序，首中即返（cancelled→canceled）；无则 status/state 串；末 'completed'
function extractStatusState(value: Object | null): string {
  if (!isRecord(value)) {
    return 'completed';
  }
  const rec: Record<string, Object> = value as Record<string, Object>;
  const states: string[] = ['completed', 'failed', 'error', 'canceled', 'cancelled', 'killed', 'running', 'pending'];
  for (let i = 0; i < states.length; i++) {
    const key: string = states[i];
    if (rec[key] !== undefined) {
      return key === 'cancelled' ? 'canceled' : key;
    }
  }
  const statusStr: string = firstNonEmpty(asNonEmptyStr(rec['status']), asNonEmptyStr(rec['state']));
  return statusStr !== '' ? statusStr : 'completed';
}

export function parseCodexWaitAgentResult(result: Object | null): CodexWaitAgentResult | null {
  const obj: Record<string, Object> | null = parseMaybeJsonObject(result);
  if (obj === null) {
    return null;
  }
  const statusRaw: Object = obj['status'];
  const statusObj: Record<string, Object> | null = isRecord(statusRaw) ? statusRaw as Record<string, Object> : null;
  const statuses: CodexAgentStatus[] = [];
  if (statusObj !== null) {
    const keys: string[] = Object.keys(statusObj);
    for (let i = 0; i < keys.length; i++) {
      const agentId: string = keys[i];
      const statusValue: Object = statusObj[agentId];
      const st: CodexAgentStatus = new CodexAgentStatus();
      st.agentId = agentId;
      st.state = extractStatusState(statusValue);
      st.text = extractStatusText(statusValue);
      statuses.push(st);
    }
  }
  const to1: Object = obj['timed_out'];
  const to2: Object = obj['timedOut'];
  const hasTimedOut: boolean = typeof to1 === 'boolean' || typeof to2 === 'boolean';
  let timedOut: boolean = false;
  if (typeof to1 === 'boolean') {
    timedOut = to1;
  } else if (typeof to2 === 'boolean') {
    timedOut = to2;
  }
  if (statuses.length === 0 && !hasTimedOut) {
    return null;
  }
  const r: CodexWaitAgentResult = new CodexWaitAgentResult();
  r.statuses = statuses;
  r.timedOut = timedOut;
  return r;
}

export function parseCodexCloseAgentResult(result: Object | null): CodexAgentStatus | null {
  const obj: Record<string, Object> | null = parseMaybeJsonObject(result);
  if (obj === null) {
    return null;
  }
  const ps1: Object = obj['previous_status'];
  const ps2: Object = obj['previousStatus'];
  const previous: Record<string, Object> | null = isRecord(ps1) ? ps1 as Record<string, Object>
    : (isRecord(ps2) ? ps2 as Record<string, Object> : null);
  if (previous === null) {
    return null;
  }
  const st: CodexAgentStatus = new CodexAgentStatus();
  st.agentId = '';
  st.state = extractStatusState(previous);
  st.text = extractStatusText(previous);
  return st;
}

// 结果摘要（本地化；供 Presentation 副标题）。'' = 无（send_input/resume_agent/CodexAgent 或 parse null）
//   注：CodexAgent 的 result 摘要上游硬编码 'wait_agent'——调用方忠实传 'wait_agent'（见 Presentation 注释）。
export function summarizeCodexAgentResult(toolName: string, result: Object | null): string {
  if (toolName === 'spawn_agent') {
    const parsed: CodexSpawnAgentResult | null = parseCodexSpawnAgentResult(result);
    if (parsed === null) {
      return '';
    }
    const label: string = (parsed.nickname !== '' && parsed.agentId !== '')
      ? `${parsed.nickname} (${parsed.agentId})`
      : firstNonEmpty(parsed.nickname, parsed.agentId);
    return label !== '' ? t('agent.launched', { label: label }) : t('agent.launchedShort');
  }
  if (toolName === 'wait_agent') {
    const parsed: CodexWaitAgentResult | null = parseCodexWaitAgentResult(result);
    if (parsed === null) {
      return '';
    }
    if (parsed.statuses.length === 0 && parsed.timedOut) {
      return t('agent.timedOut');
    }
    let completed: number = 0;
    let failed: number = 0;
    for (let i = 0; i < parsed.statuses.length; i++) {
      if (parsed.statuses[i].state === 'completed') {
        completed++;
      } else {
        failed++;
      }
    }
    const parts: string[] = [];
    if (completed > 0) {
      parts.push(t('agent.nCompleted', { n: completed }));
    }
    if (failed > 0) {
      parts.push(t('agent.nNonCompleted', { n: failed }));
    }
    if (parsed.timedOut) {
      parts.push(t('agent.timedOutSuffix'));
    }
    return parts.length > 0 ? parts.join(', ') : t('agent.noStatusYet');
  }
  if (toolName === 'close_agent') {
    const parsed: CodexAgentStatus | null = parseCodexCloseAgentResult(result);
    if (parsed === null) {
      return '';
    }
    return t('agent.closedState', { state: parsed.state });
  }
  return '';
}
