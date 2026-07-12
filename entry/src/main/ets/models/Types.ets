// Hapi 核心数据类型（对齐 hapi shared/src）
// ArkTS 无 Zod，手写等价类型 + 安全解析（JSON → 强类型）

// —— 会话摘要（列表用，对齐 shared/src/sessionSummary.ts SessionSummary）——
export class SessionSummaryMetadata {
  name: string = '';           // 会话标题
  path: string = '';           // 工作目录
  machineId: string = '';
  summaryText: string = '';    // 摘要文本
  flavor: string = '';
  agentSessionId: string = '';
}

export class SessionSummary {
  id: string = '';
  active: boolean = false;
  thinking: boolean = false;
  activeAt: number = 0;
  updatedAt: number = 0;
  metadata: SessionSummaryMetadata | null = null;
  pendingRequestsCount: number = 0;
  backgroundTaskCount: number = 0;
  model: string = '';          // null → ''
  effort: string = '';
  todoCompleted: number = 0;
  todoTotal: number = 0;

  // 标题：name 优先，否则 path 末段，否则 id
  get title(): string {
    if (this.metadata !== null) {
      if (this.metadata.name !== '') {
        return this.metadata.name;
      }
      if (this.metadata.path !== '') {
        const i: number = this.metadata.path.lastIndexOf('/');
        return i >= 0 ? this.metadata.path.substring(i + 1) : this.metadata.path;
      }
    }
    return this.id;
  }

  get summaryText(): string {
    return this.metadata !== null ? this.metadata.summaryText : '';
  }
}

// —— 机器（运行 CLI/agent 的设备，对齐 shared/src/schemas.ts Machine，简化）——
export class Machine {
  id: string = '';
  namespace: string = '';
  active: boolean = false;
  activeAt: number = 0;
  updatedAt: number = 0;
  displayName: string = '';
}

// —— Team（会话内多 agent 团队，对齐 shared/src/schemas.ts TeamState）——
//   运行时由 agent 自治上报（非 spawn 时配置）；Session.teamState 携带，非 null 时对话页渲染 TeamPanel。
export class TeamMember {
  name: string = '';
  agentType: string = '';        // 可空 → ''
  status: string = '';           // 'active' | 'idle' | 'shutdown'，空 = 未知
}
export class TeamTask {
  id: string = '';
  title: string = '';
  description: string = '';      // 可空 → ''
  status: string = '';           // 'pending' | 'in_progress' | 'completed' | 'blocked'
  owner: string = '';            // 可空 → ''
}
export class TeamMessage {
  from: string = '';
  to: string = '';
  summary: string = '';
  type: string = '';             // 'message' | 'broadcast' | 'shutdown_request' | 'shutdown_response'
  timestamp: number = 0;
}
export class TeamState {
  teamName: string = '';
  description: string = '';      // 可空 → ''
  members: TeamMember[] = [];
  tasks: TeamTask[] = [];
  messages: TeamMessage[] = [];
  updatedAt: number = 0;
}

// —— Todo（会话内待办清单，对齐 shared/src/schemas.ts TodoItem）——
//   agent 的 TodoWrite 工具上报，Session.todos 携带；非空时对话页渲染 TodoPanel（鸿蒙端增值——
//   上游 web 不独立渲染 session.todos，仅列表项显 todoProgress 摘要 + 工具卡显 TodoWrite）。
export class TodoItem {
  content: string = '';          // 必填
  status: string = 'pending';    // 'pending' | 'in_progress' | 'completed'
  priority: string = 'medium';   // 'high' | 'medium' | 'low'（默认 medium）
  id: string = '';               // 可空 → ''
  activeForm: string = '';       // 可空 → ''（进行时描述，本端 v1 不渲染）
}

// —— 会话详情（对齐 shared/src/schemas.ts Session）——
// 本类即上游 Session（完整会话记录）。当前只取渲染/工具卡所需字段，其余按需再补。
export class Session {
  id: string = '';
  namespace: string = '';
  seq: number = 0;
  createdAt: number = 0;
  updatedAt: number = 0;
  active: boolean = false;
  activeAt: number = 0;
  thinking: boolean = false;
  model: string = '';                       // nullable → ''
  effort: string = '';                       // claude 努力度（/effort 端点；nullable → ''）
  modelReasoningEffort: string = '';         // codex 推理努力（/model-reasoning-effort 端点；nullable → ''）
  permissionMode: string = '';               // 权限模式（/permission-mode 端点；optional → ''；claude: default/acceptEdits/bypassPermissions/plan）
  collaborationMode: string = '';            // codex 协作模式（/collaboration-mode 端点；optional → ''；default/plan）
  flavor: string = '';                       // metadata.flavor（claude/codex/…；ContextStatusBar 算预算 + 配置 overlay 门控用）
  agentStateVersion: number = 0;
  // 原始 agentState（{controlledByUser, requests, completedRequests}），由 chat/parseAgentState 解析。
  // 存原始 Record 而非已解析对象，避免 models/ 反向依赖 chat/。
  agentStateRaw: Record<string, Object> | null = null;
  // 会话内多 agent 团队状态（运行时 agent 上报；非 null 时对话页渲染 TeamPanel）
  teamState: TeamState | null = null;
  // 会话内待办清单（agent TodoWrite 上报；非空时对话页渲染 TodoPanel）
  todos: TodoItem[] = [];
}

// —— 重命名会话请求体（对齐 shared/src/apiTypes.ts RenameSessionRequest：name 1–255）——
export class RenameSessionRequest {
  name: string = '';
}

// —— 目录项（对齐 shared/src/apiTypes.ts DirectoryEntry / MachineDirectoryEntry）——
//   list-machine-directory 返回的 entry 带 isGitRepo；无绝对 path，浏览时由 UI 拼 currentPath + '/' + name。
export class DirEntry {
  name: string = '';
  type: string = '';        // 'file' | 'directory' | 'other'
  isGitRepo: boolean = false;
}

// —— 新建会话（spawn）请求体（对齐 shared/src/apiTypes.ts SpawnSessionRequestSchema）——
//   全字段除 directory 外皆 optional（上游 .optional() 无 .default → undefined）：
//     model/effort 为 'auto'/'' 时省略（agent 用自身默认）；yolo 恒发；sessionType 恒发（默认 'simple'）；
//     worktreeName 仅 sessionType==='worktree' 且非空时发。条件化由 HubClientUtils.buildSpawnBody 处理。
export class SpawnSessionRequest {
  directory: string = '';
  agent: string = '';
  model: string = '';             // 'auto'/'' = 省略
  effort: string = '';            // 'auto'/'' = 省略（仅 claude 有意义）
  yolo: boolean = false;          // 恒发（--yolo）
  sessionType: string = '';       // 'simple' | 'worktree'
  worktreeName: string = '';      // 仅 worktree 时发
}

// —— 浏览远端目录请求体（对齐 MachineListDirectoryRequest：path 非空）——
export class ListDirectoryRequest {
  path: string = '';
}

// —— Agent 类型（对齐 shared/src/modes.ts AGENT_FLAVORS）——
export const AGENT_FLAVORS: string[] = ['claude', 'codex', 'cursor', 'gemini', 'kimi', 'opencode'];

// Agent 显示名（下拉用）
export function agentDisplayName(flavor: string): string {
  if (flavor === 'claude') { return 'Claude Code'; }
  if (flavor === 'codex') { return 'Codex'; }
  if (flavor === 'cursor') { return 'Cursor'; }
  if (flavor === 'gemini') { return 'Gemini CLI'; }
  if (flavor === 'kimi') { return 'Kimi'; }
  if (flavor === 'opencode') { return 'OpenCode'; }
  return flavor;
}

// —— spawn 高级选项（静态枚举/预设，对照上游 web/src/components/NewSession）——
//   model 列表：claude/gemini 用 shared/src/models.ts 静态预设；codex/cursor/opencode 走 'auto'
//   （上游需 live model 端点 codex-models/cursor-models/opencode-models，本项目暂不接，'auto'=agent 默认）。
export const MODEL_AUTO: string = 'auto';
export const CLAUDE_MODEL_PRESETS: string[] = ['sonnet', 'sonnet[1m]', 'opus', 'opus[1m]'];
export const GEMINI_MODEL_PRESETS: string[] = [
  'gemini-3.1-pro-preview', 'gemini-3-flash-preview',
  'gemini-2.5-pro', 'gemini-2.5-flash', 'gemini-2.5-flash-lite'
];

// 某 agent 的可选 model（不含 'auto' 前缀，UI 自加「默认」=auto）；动态 agent 返空 → 仅 'auto'
export function modelOptionsForAgent(agent: string): string[] {
  if (agent === 'claude') { return CLAUDE_MODEL_PRESETS; }
  if (agent === 'gemini') { return GEMINI_MODEL_PRESETS; }
  return [];   // codex/cursor/opencode/kimi → 仅 'auto'
}

// model 显示名（对照 CLAUDE_MODEL_LABELS / GEMINI_MODEL_LABELS）
export function modelDisplayName(agent: string, model: string): string {
  if (model === MODEL_AUTO || model === '') { return '默认'; }
  if (agent === 'claude') {
    if (model === 'sonnet') { return 'Sonnet'; }
    if (model === 'sonnet[1m]') { return 'Sonnet 1M'; }
    if (model === 'opus') { return 'Opus'; }
    if (model === 'opus[1m]') { return 'Opus 1M'; }
  }
  return model;   // gemini 预设 / 未知 model 直接显 id
}

// effort（仅 claude；对照 web ClaudeEffort 'auto'|'medium'|'high'|'max'，'auto'=省略）
export const EFFORT_OPTIONS: string[] = ['auto', 'medium', 'high', 'max'];
export function effortDisplayName(effort: string): string {
  if (effort === 'auto') { return '自动'; }
  if (effort === 'medium') { return 'Medium'; }
  if (effort === 'high') { return 'High'; }
  if (effort === 'max') { return 'Max'; }
  return effort;
}

// sessionType（对照 shared/src/apiTypes.ts z.enum(['simple','worktree'])）
export const SESSION_TYPES: string[] = ['simple', 'worktree'];
export function sessionTypeDisplayName(st: string): string {
  if (st === 'simple') { return '普通'; }
  if (st === 'worktree') { return '工作树'; }
  return st;
}

// —— 会话内即时配置子集（对照 shared/src/modes.ts：各 flavor 的权限/协作/推理努力可选域）——
//   permission-mode（/permission-mode 端点，全 flavor）：claude 4 / codex·gemini·kimi 4 / opencode 3 / cursor 4。
export const CLAUDE_PERMISSION_MODES: string[] = ['default', 'acceptEdits', 'bypassPermissions', 'plan'];
export const CODEX_PERMISSION_MODES: string[] = ['default', 'read-only', 'safe-yolo', 'yolo'];   // codex/gemini/kimi 共用
export const OPENCODE_PERMISSION_MODES: string[] = ['default', 'plan', 'yolo'];
export const CURSOR_PERMISSION_MODES: string[] = ['default', 'plan', 'ask', 'yolo'];
// collaboration-mode（/collaboration-mode 端点，仅 codex）：default/plan。
export const CODEX_COLLABORATION_MODES: string[] = ['default', 'plan'];
// model-reasoning-effort（/model-reasoning-effort 端点，codex/opencode）：codex low..xhigh / opencode low..max。
export const CODEX_REASONING_EFFORTS: string[] = ['low', 'medium', 'high', 'xhigh'];
export const OPENCODE_REASONING_EFFORTS: string[] = ['low', 'medium', 'high', 'max'];

export function permissionModesForFlavor(flavor: string): string[] {
  if (flavor === 'codex' || flavor === 'gemini' || flavor === 'kimi') { return CODEX_PERMISSION_MODES; }
  if (flavor === 'opencode') { return OPENCODE_PERMISSION_MODES; }
  if (flavor === 'cursor') { return CURSOR_PERMISSION_MODES; }
  return CLAUDE_PERMISSION_MODES;   // claude + 未知回退
}
export function permissionModeDisplayName(mode: string): string {
  if (mode === 'default') { return '默认'; }
  if (mode === 'acceptEdits') { return '接受编辑'; }
  if (mode === 'bypassPermissions') { return '跳过权限 (Yolo)'; }
  if (mode === 'plan') { return '计划模式'; }
  if (mode === 'ask') { return '询问模式'; }
  if (mode === 'read-only') { return '只读'; }
  if (mode === 'safe-yolo') { return '安全 Yolo'; }
  if (mode === 'yolo') { return 'Yolo'; }
  return mode;
}
export function collaborationModeDisplayName(mode: string): string {
  if (mode === 'default') { return '默认'; }
  if (mode === 'plan') { return '计划'; }
  return mode;
}
export function reasoningEffortsForFlavor(flavor: string): string[] {
  return flavor === 'opencode' ? OPENCODE_REASONING_EFFORTS : CODEX_REASONING_EFFORTS;
}
export function reasoningEffortDisplayName(effort: string): string {
  if (effort === 'low') { return 'Low'; }
  if (effort === 'medium') { return 'Medium'; }
  if (effort === 'high') { return 'High'; }
  if (effort === 'xhigh') { return 'XHigh'; }
  if (effort === 'max') { return 'Max'; }
  return effort;
}

// 解析 GET /api/sessions/:id → { session: {...} }（对照 web getSession 的 SessionResponse）
export function parseSessionDetail(json: string): Session {
  const s: Session = new Session();
  let top: Record<string, Object>;
  try {
    top = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return s;
  }
  const raw: Record<string, Object> | null = pickObj(top, 'session');
  if (raw === null) {
    return s;
  }
  s.id = pickStr(raw, 'id');
  s.namespace = pickStr(raw, 'namespace');
  s.seq = pickNum(raw, 'seq');
  s.createdAt = pickNum(raw, 'createdAt');
  s.updatedAt = pickNum(raw, 'updatedAt');
  s.active = pickBool(raw, 'active');
  s.activeAt = pickNum(raw, 'activeAt');
  s.thinking = pickBool(raw, 'thinking');
  s.model = pickStr(raw, 'model');
  s.effort = pickStr(raw, 'effort');
  s.modelReasoningEffort = pickStr(raw, 'modelReasoningEffort');
  s.permissionMode = pickStr(raw, 'permissionMode');
  s.collaborationMode = pickStr(raw, 'collaborationMode');
  // flavor 在 metadata.flavor（MetadataSchema.flavor 可空 → ''）：供 ContextStatusBar 算预算上限
  const detailMeta = pickObj(raw, 'metadata');
  if (detailMeta !== null) {
    s.flavor = pickStr(detailMeta, 'flavor');
  }
  s.agentStateVersion = pickNum(raw, 'agentStateVersion');
  s.agentStateRaw = pickObj(raw, 'agentState');
  s.teamState = parseTeamState(pickObj(raw, 'teamState'));
  s.todos = parseTodoList(raw['todos']);
  return s;
}

// —— 安全解析辅助（从 Record 取值，类型不符给默认）——
export function pickStr(r: Record<string, Object>, k: string): string {
  const v = r[k];
  return typeof v === 'string' ? v : '';
}
export function pickNum(r: Record<string, Object>, k: string): number {
  const v = r[k];
  return typeof v === 'number' ? v : 0;
}
export function pickBool(r: Record<string, Object>, k: string): boolean {
  const v = r[k];
  return typeof v === 'boolean' ? v : false;
}
export function pickObj(r: Record<string, Object>, k: string): Record<string, Object> | null {
  const v = r[k];
  if (v !== null && v !== undefined && typeof v === 'object') {
    return v as Record<string, Object>;
  }
  return null;
}

// 解析单个 SessionSummary
export function parseSessionSummary(raw: Record<string, Object>): SessionSummary {
  const s = new SessionSummary();
  s.id = pickStr(raw, 'id');
  s.active = pickBool(raw, 'active');
  s.thinking = pickBool(raw, 'thinking');
  s.activeAt = pickNum(raw, 'activeAt');
  s.updatedAt = pickNum(raw, 'updatedAt');
  s.pendingRequestsCount = pickNum(raw, 'pendingRequestsCount');
  s.backgroundTaskCount = pickNum(raw, 'backgroundTaskCount');
  s.model = pickStr(raw, 'model');
  s.effort = pickStr(raw, 'effort');

  const metaRaw = pickObj(raw, 'metadata');
  if (metaRaw !== null) {
    const m = new SessionSummaryMetadata();
    m.name = pickStr(metaRaw, 'name');
    m.path = pickStr(metaRaw, 'path');
    m.machineId = pickStr(metaRaw, 'machineId');
    const sumRaw = pickObj(metaRaw, 'summary');
    if (sumRaw !== null) {
      m.summaryText = pickStr(sumRaw, 'text');
    }
    m.flavor = pickStr(metaRaw, 'flavor');
    s.metadata = m;
  }

  const todoRaw = pickObj(raw, 'todoProgress');
  if (todoRaw !== null) {
    s.todoCompleted = pickNum(todoRaw, 'completed');
    s.todoTotal = pickNum(todoRaw, 'total');
  }
  return s;
}

// 解析 SessionsResponse { sessions: SessionSummary[] }
export function parseSessionsResponse(json: string): SessionSummary[] {
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return [];
  }
  const arr = raw['sessions'];
  if (arr === null || arr === undefined || !Array.isArray(arr)) {
    return [];
  }
  const result: SessionSummary[] = [];
  const list = arr as Object[];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item !== null && item !== undefined && typeof item === 'object') {
      result.push(parseSessionSummary(item as Record<string, Object>));
    }
  }
  return result;
}

// —— 解析 GET /api/machines → { machines: Machine[] }（对齐 MachinesResponse）——
export function parseMachinesResponse(json: string): Machine[] {
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return [];
  }
  const arr = raw['machines'];
  if (arr === null || arr === undefined || !Array.isArray(arr)) {
    return [];
  }
  const result: Machine[] = [];
  const list = arr as Object[];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item !== null && item !== undefined && typeof item === 'object') {
      result.push(parseMachine(item as Record<string, Object>));
    }
  }
  return result;
}

// 解析单个 Machine（displayName 取 metadata.displayName，否则 metadata.host，对照 router getMachineTitle）
function parseMachine(raw: Record<string, Object>): Machine {
  const m = new Machine();
  m.id = pickStr(raw, 'id');
  m.namespace = pickStr(raw, 'namespace');
  m.active = pickBool(raw, 'active');
  m.activeAt = pickNum(raw, 'activeAt');
  m.updatedAt = pickNum(raw, 'updatedAt');
  const meta = pickObj(raw, 'metadata');
  if (meta !== null) {
    m.displayName = pickStr(meta, 'displayName');
    if (m.displayName === '') { m.displayName = pickStr(meta, 'host'); }
  }
  return m;
}

// —— 解析 POST /api/machines/:id/list-directory → { entries: DirEntry[] }（对齐 MachineListDirectoryResponse）——
export function parseListDirectoryResponse(json: string): DirEntry[] {
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return [];
  }
  const arr = raw['entries'];
  if (arr === null || arr === undefined || !Array.isArray(arr)) {
    return [];
  }
  const result: DirEntry[] = [];
  const list = arr as Object[];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item !== null && item !== undefined && typeof item === 'object') {
      const r = item as Record<string, Object>;
      const e = new DirEntry();
      e.name = pickStr(r, 'name');
      e.type = pickStr(r, 'type');
      e.isGitRepo = pickBool(r, 'isGitRepo');
      result.push(e);
    }
  }
  return result;
}

// —— 解析 POST /api/machines/:id/spawn → SpawnResponse（{type:'success',sessionId} | {type:'error',message}）
//   成功返回 sessionId；业务错误（type:'error'）或无 sessionId 抛 Error，由调用方 catch 显示。 ——
export function parseSpawnResponse(json: string): string {
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    throw new Error('启动会话响应解析失败');
  }
  const type = pickStr(raw, 'type');
  if (type === 'error') {
    const msg = pickStr(raw, 'message');
    throw new Error(msg !== '' ? msg : '启动会话失败');
  }
  const sid = pickStr(raw, 'sessionId');
  if (sid === '') {
    throw new Error('启动会话失败：未返回 sessionId');
  }
  return sid;
}

// —— 解析 Session.teamState（对齐 TeamStateSchema）——
//   teamName 是必填，空 → 视为无 team，返回 null（对话页据此决定是否渲染 TeamPanel）。
export function parseTeamState(raw: Record<string, Object> | null): TeamState | null {
  if (raw === null) { return null; }
  const teamName: string = pickStr(raw, 'teamName');
  if (teamName === '') { return null; }
  const t: TeamState = new TeamState();
  t.teamName = teamName;
  t.description = pickStr(raw, 'description');
  t.updatedAt = pickNum(raw, 'updatedAt');
  t.members = parseTeamMemberList(raw['members']);
  t.tasks = parseTeamTaskList(raw['tasks']);
  t.messages = parseTeamMessageList(raw['messages']);
  return t;
}

// —— 解析 Session.todos（对齐 TodosSchema = TodoItem[]）——
//   content 必填（非串跳过该条）；status/priority 归一；id/activeForm 可空。
//   raw 非 null 但非数组（或缺失→undefined）→ []。
function normalizeTodoStatus(value: Object): string {
  if (value === 'completed') { return 'completed'; }
  if (value === 'in_progress') { return 'in_progress'; }
  return 'pending';
}
function normalizeTodoPriority(value: Object): string {
  if (value === 'high') { return 'high'; }
  if (value === 'low') { return 'low'; }
  return 'medium';
}
export function parseTodoList(raw: Object | null): TodoItem[] {
  const out: TodoItem[] = [];
  if (raw === null || !Array.isArray(raw)) { return out; }
  const arr: Object[] = raw as Object[];
  for (let i = 0; i < arr.length; i++) {
    const entry: Object = arr[i];
    if (entry === null || entry === undefined || typeof entry !== 'object') { continue; }
    const rec: Record<string, Object> = entry as Record<string, Object>;
    const contentVal: Object = rec['content'];
    if (typeof contentVal !== 'string') { continue; }
    const item: TodoItem = new TodoItem();
    item.content = contentVal;
    item.status = normalizeTodoStatus(rec['status']);
    item.priority = normalizeTodoPriority(rec['priority']);
    const idVal: Object = rec['id'];
    if (typeof idVal === 'string') { item.id = idVal; }
    const afVal: Object = rec['activeForm'];
    if (typeof afVal === 'string') { item.activeForm = afVal; }
    out.push(item);
  }
  return out;
}

function parseTeamMemberList(arr: Object): TeamMember[] {
  if (arr === null || arr === undefined || !Array.isArray(arr)) { return []; }
  const list: Object[] = arr as Object[];
  const out: TeamMember[] = [];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item !== null && item !== undefined && typeof item === 'object') {
      const r: Record<string, Object> = item as Record<string, Object>;
      const m: TeamMember = new TeamMember();
      m.name = pickStr(r, 'name');
      m.agentType = pickStr(r, 'agentType');
      m.status = pickStr(r, 'status');
      out.push(m);
    }
  }
  return out;
}

function parseTeamTaskList(arr: Object): TeamTask[] {
  if (arr === null || arr === undefined || !Array.isArray(arr)) { return []; }
  const list: Object[] = arr as Object[];
  const out: TeamTask[] = [];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item !== null && item !== undefined && typeof item === 'object') {
      const r: Record<string, Object> = item as Record<string, Object>;
      const tk: TeamTask = new TeamTask();
      tk.id = pickStr(r, 'id');
      tk.title = pickStr(r, 'title');
      tk.description = pickStr(r, 'description');
      tk.status = pickStr(r, 'status');
      tk.owner = pickStr(r, 'owner');
      out.push(tk);
    }
  }
  return out;
}

function parseTeamMessageList(arr: Object): TeamMessage[] {
  if (arr === null || arr === undefined || !Array.isArray(arr)) { return []; }
  const list: Object[] = arr as Object[];
  const out: TeamMessage[] = [];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item !== null && item !== undefined && typeof item === 'object') {
      const r: Record<string, Object> = item as Record<string, Object>;
      const msg: TeamMessage = new TeamMessage();
      msg.from = pickStr(r, 'from');
      msg.to = pickStr(r, 'to');
      msg.summary = pickStr(r, 'summary');
      msg.type = pickStr(r, 'type');
      msg.timestamp = pickNum(r, 'timestamp');
      out.push(msg);
    }
  }
  return out;
}
