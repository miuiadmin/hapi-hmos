// Hapi 核心数据类型（对齐 hapi shared/src）
// ArkTS 无 Zod，手写等价类型 + 安全解析（JSON → 强类型）

import { t } from '../i18n/Translate';

// —— 会话摘要（列表用，对齐 shared/src/sessionSummary.ts SessionSummary）——
export class SessionSummaryMetadata {
  name: string = '';           // 会话标题
  path: string = '';           // 工作目录
  machineId: string = '';
  summaryText: string = '';    // 摘要文本
  flavor: string = '';
  agentSessionId: string = '';
  worktreeBasePath: string = '';   // metadata.worktree.basePath（目录建议第二源；对照 shared WorktreeMetadata.basePath）
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
  pendingRequestKinds: string[] = [];   // 待处理请求类型（'permission'|'input'；attention 指示器分级用）
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
  // 上次 spawn 错误（对齐 shared/src/schemas.ts runnerState.lastSpawnError {message,at}）。
  //   仅读 Hub 已有字段，零协议改动；message 非空即有错误，at=0 表无时间戳。NewSessionPage 据此显红字诊断。
  lastSpawnErrorMessage: string = '';
  lastSpawnErrorAt: number = 0;
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

// —— Thread goal（codex 持久目标，对齐 shared/src/schemas.ts ThreadGoal）——
//   以 role:'event' 消息下发（thread_goal_updated/cleared），由 parseMessage 标记到 ChatMessage；
//   chat/ThreadGoal.ets getLatestThreadGoal 反向遍历消息取最新有效 goal（含 cleared/complete 抑制），
//   喂 StatusBar goal chip（仅 codex 显）。status ∈ {active, paused, budgetLimited, complete}。
export class ThreadGoal {
  threadId: string = '';          // 必填
  objective: string = '';         // 必填（目标文本）
  status: string = '';            // 必填；'active' | 'paused' | 'budgetLimited' | 'complete'
  tokenBudget: number = -1;       // < 0 = null/缺省（上游 nullable；chip 不用此字段）
  tokensUsed: number = 0;
  timeUsedSeconds: number = 0;
  createdAt: number = 0;          // epoch-ms
  updatedAt: number = 0;          // epoch-ms
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
  path: string = '';                         // metadata.path（会话工作目录；终端页顶栏显示 cwd）
  worktreeBranch: string = '';               // metadata.worktree.branch（git 分支；标题副标题显示，对照 shared WorktreeMetadata.branch）
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

// —— 批量校验远端路径存在性请求体（对齐 MachinePathsExistsRequest：paths 非空数组，上限 1000）——
//   POST /api/machines/:id/paths/exists → { exists: Record<path, boolean> }。
//   新建会话路径存在性校验用（对照 web checkMachinePathsExists）。
export class MachinePathsExistsRequest {
  paths: string[] = [];
}

// —— 服务端斜杠命令（对齐 shared/src/apiTypes.ts SlashCommand，取所需字段）——
//   GET /api/sessions/:id/slash-commands 返回用户/项目/插件命令（source != 'builtin'）。
//   渲染层用 chat/SlashCommand；本类是解析中间态（models 不依赖 chat），由 serverCommandsToSlash 映射。
export class ServerSlashCommand {
  name: string = '';
  description: string = '';
  source: string = 'user';        // 'user' | 'plugin' | 'project'（builtin 不来自服务端）
  content: string = '';           // 自定义命令展开内容（可空）
}

// —— 技能摘要（对齐 web/types/api.ts SkillSummary）——
//   GET /api/sessions/:id/skills 返回 $ 技能列表（name + 可选描述）。
export class SkillItem {
  name: string = '';
  description: string = '';
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

// —— spawn 高级选项（静态预设 + 动态拉取，对照上游 web/src/components/NewSession + @hapi/protocol）——
//   claude/gemini：shared/src/models.ts 静态预设（无端点）。
//   codex/cursor/opencode：live model 端点拉取（GET .../{codex,cursor,opencode}-models[?cwd=]），
//     解析为 ModelOption[]，UI 与静态预设合并（「默认」=auto + 静态 + 动态，去重）。
export const MODEL_AUTO: string = 'auto';
export const CLAUDE_MODEL_PRESETS: string[] = ['sonnet', 'sonnet[1m]', 'opus', 'opus[1m]'];
export const GEMINI_MODEL_PRESETS: string[] = [
  'gemini-3.1-pro-preview', 'gemini-3-flash-preview',
  'gemini-2.5-pro', 'gemini-2.5-flash', 'gemini-2.5-flash-lite'
];

// 动态拉取的 model 项（id=模型标识，发 spawn / setModel 用；label=显示名）。对照 CodexModelSummary / OpencodeModelSummary。
export class ModelOption {
  id: string = '';
  label: string = '';
}

// 某 agent 的可选 model（不含 'auto' 前缀，UI 自加「默认」=auto）；动态 agent 返空 → 仅 'auto'
export function modelOptionsForAgent(agent: string): string[] {
  if (agent === 'claude') { return CLAUDE_MODEL_PRESETS; }
  if (agent === 'gemini') { return GEMINI_MODEL_PRESETS; }
  return [];   // codex/cursor/opencode/kimi → 仅 'auto'
}

// model 显示名（对照 CLAUDE_MODEL_LABELS / GEMINI_MODEL_LABELS）
export function modelDisplayName(agent: string, model: string): string {
  if (model === MODEL_AUTO || model === '') { return t('types.default'); }
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
  if (effort === 'auto') { return t('types.auto'); }
  if (effort === 'medium') { return 'Medium'; }
  if (effort === 'high') { return 'High'; }
  if (effort === 'max') { return 'Max'; }
  return effort;
}

// sessionType（对照 shared/src/apiTypes.ts z.enum(['simple','worktree'])）
export const SESSION_TYPES: string[] = ['simple', 'worktree'];
export function sessionTypeDisplayName(st: string): string {
  if (st === 'simple') { return t('types.sessionSimple'); }
  if (st === 'worktree') { return t('types.sessionWorktree'); }
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
  if (mode === 'default') { return t('types.default'); }
  if (mode === 'acceptEdits') { return t('types.permission.acceptEdits'); }
  if (mode === 'bypassPermissions') { return t('types.permission.bypass'); }
  if (mode === 'plan') { return t('types.permission.planMode'); }
  if (mode === 'ask') { return t('types.permission.ask'); }
  if (mode === 'read-only') { return t('types.permission.readonly'); }
  if (mode === 'safe-yolo') { return t('types.permission.safeYolo'); }
  if (mode === 'yolo') { return t('types.permission.yolo'); }
  return mode;
}
export function collaborationModeDisplayName(mode: string): string {
  if (mode === 'default') { return t('types.default'); }
  if (mode === 'plan') { return t('types.collaboration.plan'); }
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
    s.path = pickStr(detailMeta, 'path');
    // worktree.branch（对照 shared WorktreeMetadataSchema.branch；标题副标题显示）
    const worktreeRaw = pickObj(detailMeta, 'worktree');
    if (worktreeRaw !== null) {
      s.worktreeBranch = pickStr(worktreeRaw, 'branch');
    }
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
// 安全取字符串数组（缺/非数组/元素非字符串 → []；pendingRequestKinds 等用）
export function pickStrArr(r: Record<string, Object>, k: string): string[] {
  const v = r[k];
  if (v === null || v === undefined || !Array.isArray(v)) {
    return [];
  }
  const arr = v as Object[];
  const out: string[] = [];
  for (let i = 0; i < arr.length; i++) {
    const el = arr[i];
    if (typeof el === 'string') {
      out.push(el);
    }
  }
  return out;
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
  s.pendingRequestKinds = pickStrArr(raw, 'pendingRequestKinds');
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
    // worktree.basePath（目录建议第二源；对照 shared WorktreeMetadataSchema.basePath：metadata.worktree?.basePath）
    const worktreeRaw = pickObj(metaRaw, 'worktree');
    if (worktreeRaw !== null) {
      m.worktreeBasePath = pickStr(worktreeRaw, 'basePath');
    }
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
  // runnerState.lastSpawnError（对照 web/src/utils/formatRunnerSpawnError getLastSpawnError）：
  //   message 为空串则视为无错误（两字段留默认）。
  const runnerState = pickObj(raw, 'runnerState');
  if (runnerState !== null) {
    const lastSpawnError = pickObj(runnerState, 'lastSpawnError');
    if (lastSpawnError !== null) {
      const message = pickStr(lastSpawnError, 'message');
      if (message !== '') {
        m.lastSpawnErrorMessage = message;
        m.lastSpawnErrorAt = pickNum(lastSpawnError, 'at');
      }
    }
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
    throw new Error(t('types.spawn.parseFailed'));
  }
  const type = pickStr(raw, 'type');
  if (type === 'error') {
    const msg = pickStr(raw, 'message');
    throw new Error(msg !== '' ? msg : t('types.spawn.failed'));
  }
  const sid = pickStr(raw, 'sessionId');
  if (sid === '') {
    throw new Error(t('types.spawn.noSessionId'));
  }
  return sid;
}

// —— 解析 GET .../codex-models → { models: CodexModelSummary[] }（对齐 CodexModelsResponse）——
//   CodexModelSummary = { id, displayName, isDefault, ... }。映射为 ModelOption（id, label=displayName）。
//   跳过空 id 与 'auto'（UI 自加「默认」=auto 项，避免重复）。容错：缺 models / 非数组 / 损坏 → []。
export function parseCodexModelsResponse(json: string): ModelOption[] {
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return [];
  }
  const arr = raw['models'];
  if (arr === null || arr === undefined || !Array.isArray(arr)) {
    return [];
  }
  const result: ModelOption[] = [];
  const list = arr as Object[];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item === null || item === undefined || typeof item !== 'object') { continue; }
    const r = item as Record<string, Object>;
    const id = pickStr(r, 'id');
    if (id === '' || id === MODEL_AUTO) { continue; }
    const opt = new ModelOption();
    opt.id = id;
    const dn = pickStr(r, 'displayName');
    opt.label = dn !== '' ? dn : id;
    result.push(opt);
  }
  return result;
}

// —— 解析 GET .../cursor-models | opencode-models → { availableModels: OpencodeModelSummary[], currentModelId? }
//   对齐 OpencodeModelsResponse（cursor 同形 CursorModelsResponse = OpencodeModelsResponse）。
//   OpencodeModelSummary = { modelId, name? }。映射为 ModelOption（id=modelId, label=name ?? modelId）。
//   跳过空 modelId 与 'auto'（上游 cursor 显式过滤 auto；opencode 同款，避免与「默认」项重复）。
export function parseOpencodeModelsResponse(json: string): ModelOption[] {
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return [];
  }
  const arr = raw['availableModels'];
  if (arr === null || arr === undefined || !Array.isArray(arr)) {
    return [];
  }
  const result: ModelOption[] = [];
  const list = arr as Object[];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item === null || item === undefined || typeof item !== 'object') { continue; }
    const r = item as Record<string, Object>;
    const modelId = pickStr(r, 'modelId');
    if (modelId === '' || modelId === MODEL_AUTO) { continue; }
    const opt = new ModelOption();
    opt.id = modelId;
    const nm = pickStr(r, 'name');
    opt.label = nm !== '' ? nm : modelId;
    result.push(opt);
  }
  return result;
}

// —— 解析 POST /api/sessions/:id/resume → { sessionId }（对照 web resumeSession client.ts:312）
//   非活跃会话发送前隐式复活，可能返回新的 sessionId（旧 session 已不可写时 Hub 新建）。
//   成功返回 sessionId；无 sessionId 抛 Error，由调用方 catch。 ——
export function parseResumeSessionResponse(json: string): string {
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    throw new Error(t('types.resume.parseFailed'));
  }
  const sid = pickStr(raw, 'sessionId');
  if (sid === '') {
    throw new Error(t('types.resume.noSessionId'));
  }
  return sid;
}

// —— 解析 GET /api/sessions/:id/slash-commands → { success, commands?: SlashCommand[], error? }
//   （对齐 SlashCommandsResponse）。success=false 或无 commands → []（离线回落内置，不抛）。
//   字段：name/description/source/content（pluginName 渲染不用，丢弃）。
export function parseSlashCommandsResponse(json: string): ServerSlashCommand[] {
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return [];
  }
  if (!pickBool(raw, 'success')) {
    return [];
  }
  const arr = raw['commands'];
  if (arr === null || arr === undefined || !Array.isArray(arr)) {
    return [];
  }
  const result: ServerSlashCommand[] = [];
  const list = arr as Object[];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item !== null && item !== undefined && typeof item === 'object') {
      const r = item as Record<string, Object>;
      const c = new ServerSlashCommand();
      c.name = pickStr(r, 'name');
      c.description = pickStr(r, 'description');
      c.source = pickStr(r, 'source');
      c.content = pickStr(r, 'content');
      if (c.source === '') { c.source = 'user'; }   // 缺省归 user（上游 source 必填，防御）
      result.push(c);
    }
  }
  return result;
}

// —— 解析 GET /api/sessions/:id/skills → { success, skills?: SkillSummary[], error? }
//   （对齐 SkillsResponse）。success=false 或无 skills → []（不阻塞 $ 联想）。
export function parseSkillsResponse(json: string): SkillItem[] {
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return [];
  }
  if (!pickBool(raw, 'success')) {
    return [];
  }
  const arr = raw['skills'];
  if (arr === null || arr === undefined || !Array.isArray(arr)) {
    return [];
  }
  const result: SkillItem[] = [];
  const list = arr as Object[];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item !== null && item !== undefined && typeof item === 'object') {
      const r = item as Record<string, Object>;
      const s = new SkillItem();
      s.name = pickStr(r, 'name');
      s.description = pickStr(r, 'description');
      result.push(s);
    }
  }
  return result;
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

// Thread goal 解析（对照 web normalizeAgent.ts:35-52 normalizeThreadGoal）。
//   camelCase↔snake_case 双向容错；缺 threadId/objective/status 或 status 非四值之一 → null。
//   tokenBudget 上游可空 → -1 哨兵；其余数值缺省 → 0（同上游 ?? 0）。
function threadGoalStr(r: Record<string, Object>, camel: string, snake: string): string {
  const c: string = pickStr(r, camel);
  return c !== '' ? c : pickStr(r, snake);
}
function threadGoalNum(r: Record<string, Object>, camel: string, snake: string): number {
  const c: Object = r[camel];
  if (typeof c === 'number') { return c; }
  const s: Object = r[snake];
  if (typeof s === 'number') { return s; }
  return -1;   // 缺省哨兵；调用方按需 ?? 0
}
export function parseThreadGoal(raw: Record<string, Object>): ThreadGoal | null {
  const threadId: string = threadGoalStr(raw, 'threadId', 'thread_id');
  const objective: string = pickStr(raw, 'objective');
  const status: string = pickStr(raw, 'status');
  if (threadId === '' || objective === '' || status === '') { return null; }
  if (status !== 'active' && status !== 'paused'
    && status !== 'budgetLimited' && status !== 'complete') {
    return null;
  }
  const g: ThreadGoal = new ThreadGoal();
  g.threadId = threadId;
  g.objective = objective;
  g.status = status;
  g.tokenBudget = threadGoalNum(raw, 'tokenBudget', 'token_budget');   // < 0 = null（保留）
  const used: number = threadGoalNum(raw, 'tokensUsed', 'tokens_used');
  g.tokensUsed = used < 0 ? 0 : used;
  const time: number = threadGoalNum(raw, 'timeUsedSeconds', 'time_used_seconds');
  g.timeUsedSeconds = time < 0 ? 0 : time;
  const created: number = threadGoalNum(raw, 'createdAt', 'created_at');
  g.createdAt = created < 0 ? 0 : created;
  const updated: number = threadGoalNum(raw, 'updatedAt', 'updated_at');
  g.updatedAt = updated < 0 ? 0 : updated;
  return g;
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

// —— Files 浏览页类型（对照 shared/src/apiTypes.ts + web types/api.ts）——
// FileSearchItem：GET /sessions/:id/files?query= 的单项（fileName/filePath/fullPath/fileType）。
export class FileSearchItem {
  fileName: string = '';
  filePath: string = '';
  fullPath: string = '';
  fileType: string = '';        // 'file' | 'folder'
}

// —— 附件上传（对照 shared/src/schemas.ts AttachmentMetadataSchema + apiTypes.ts UploadFileResponse）——
// AttachmentMetadata：随消息发送的附件元数据；id 客户端生成，path 由 upload 返回（服务端落盘路径）。
export class AttachmentMetadata {
  id: string = '';
  filename: string = '';
  mimeType: string = '';
  size: number = 0;
  path: string = '';            // uploadFile 返回的服务端 path（发送时必填）
  previewUrl: string = '';      // 可选；图片可填 data: URI 供本地预览，v1 留空
}

// UploadFileResult：POST /sessions/:id/upload 的响应壳（success + path? + error?，对照 UploadFileResponse）。
export class UploadFileResult {
  success: boolean = false;
  path: string = '';
  error: string = '';
}

// 解析 POST /sessions/:id/upload 响应 → UploadFileResult（非法 JSON → success=false 空壳）。
//   成功取 path（服务端落盘路径，发送附件时回填 AttachmentMetadata.path）；失败取 error。
export function parseUploadFileResponse(json: string): UploadFileResult {
  const r: UploadFileResult = new UploadFileResult();
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return r;
  }
  r.success = pickBool(raw, 'success');
  r.path = pickStr(raw, 'path');
  r.error = pickStr(raw, 'error');
  return r;
}

// CommandResponse：git-status / git-diff-numstat / git-diff-file 通用壳（success + stdout/stderr/exitCode/error）。
export class CommandResponse {
  success: boolean = false;
  stdout: string = '';
  stderr: string = '';
  exitCode: number = -1;        // -1 哨兵 = 未提供
  error: string = '';
}

// FileReadResponse：GET /sessions/:id/file?path= 的内容壳（content 为 base64 编码）。
export class FileReadResponse {
  success: boolean = false;
  content: string = '';         // base64 编码的文件内容
  error: string = '';
}

// SessionDirEntry：GET /sessions/:id/directory 的单项（区别机器版 DirEntry：无 isGitRepo，有 size/modified）。
export class SessionDirEntry {
  name: string = '';
  type: string = '';            // 'file' | 'directory' | 'other'
  size: number = -1;            // -1 哨兵 = 未提供
  modified: number = -1;        // -1 哨兵 = 未提供（epoch-ms）
}

// 解析 GET /sessions/:id/files?query= → FileSearchItem[]（失败/缺 files → 空数组）
export function parseFileSearchResponse(json: string): FileSearchItem[] {
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return [];
  }
  const arr = raw['files'];
  if (arr === null || arr === undefined || !Array.isArray(arr)) { return []; }
  const list: Object[] = arr as Object[];
  const out: FileSearchItem[] = [];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item !== null && item !== undefined && typeof item === 'object') {
      const r: Record<string, Object> = item as Record<string, Object>;
      const f: FileSearchItem = new FileSearchItem();
      f.fileName = pickStr(r, 'fileName');
      f.filePath = pickStr(r, 'filePath');
      f.fullPath = pickStr(r, 'fullPath');
      f.fileType = pickStr(r, 'fileType');
      out.push(f);
    }
  }
  return out;
}

// 解析 git-* CommandResponse（非法 JSON → success=false 空壳）
export function parseCommandResponse(json: string): CommandResponse {
  const c: CommandResponse = new CommandResponse();
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return c;
  }
  c.success = pickBool(raw, 'success');
  c.stdout = pickStr(raw, 'stdout');
  c.stderr = pickStr(raw, 'stderr');
  c.error = pickStr(raw, 'error');
  const ec = raw['exitCode'];
  c.exitCode = typeof ec === 'number' ? ec : -1;
  return c;
}

// 解析 GET /sessions/:id/file?path= → FileReadResponse（非法 JSON → success=false 空壳）
export function parseFileReadResponse(json: string): FileReadResponse {
  const f: FileReadResponse = new FileReadResponse();
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return f;
  }
  f.success = pickBool(raw, 'success');
  f.content = pickStr(raw, 'content');
  f.error = pickStr(raw, 'error');
  return f;
}

// 解析 GET /sessions/:id/directory → SessionDirEntry[]（失败/缺 entries → 空数组）
export function parseSessionDirectoryResponse(json: string): SessionDirEntry[] {
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return [];
  }
  const arr = raw['entries'];
  if (arr === null || arr === undefined || !Array.isArray(arr)) { return []; }
  const list: Object[] = arr as Object[];
  const out: SessionDirEntry[] = [];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item !== null && item !== undefined && typeof item === 'object') {
      const r: Record<string, Object> = item as Record<string, Object>;
      const e: SessionDirEntry = new SessionDirEntry();
      e.name = pickStr(r, 'name');
      e.type = pickStr(r, 'type');
      const sz = r['size'];
      e.size = typeof sz === 'number' ? sz : -1;
      const md = r['modified'];
      e.modified = typeof md === 'number' ? md : -1;
      out.push(e);
    }
  }
  return out;
}

// —— 语音（Voice）类型 + 解析，对齐 hub web/routes/voice.ts（只读对照，协议权威）——
//   POST /api/voice/token body {voiceId?} → { allowed, token?, agentId?, error? }
//   GET  /api/voice/voices → { voices: [{ id, name, previewUrl, category }] }
//   POST /api/voice/telemetry body { stage, message, sessionId?, voiceId?, language?, details? } → { ok }

// 语音会话 token 结果（Hub 代 ElevenLabs 换的 conversation token；allowed=false 时 error 带原因）
export class VoiceTokenResult {
  allowed: boolean = false;
  token: string = '';
  agentId: string = '';
  error: string = '';
}

// ElevenLabs 声音（含用户克隆声；category 如 'premade'/'cloned'/'generated'）
export class VoiceItem {
  id: string = '';
  name: string = '';
  previewUrl: string = '';
  category: string = '';
}

// 语音遥测事件（stage 为阶段标识，如 'session_start'/'session_end'/'error'；details 透传）
export class VoiceTelemetryEvent {
  stage: string = '';
  message: string = '';
  sessionId: string = '';
  voiceId: string = '';
  language: string = '';
  details: Record<string, Object> = {};
}

// 解析 POST /api/voice/token → VoiceTokenResult（HTTP 失败/损坏体合成 allowed=false+error）
export function parseVoiceTokenResponse(json: string, httpError: string): VoiceTokenResult {
  const r: VoiceTokenResult = new VoiceTokenResult();
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    r.error = httpError !== '' ? httpError : t('types.voice.tokenParseFailed');
    return r;
  }
  r.allowed = raw['allowed'] === true;
  r.token = pickStr(raw, 'token');
  r.agentId = pickStr(raw, 'agentId');
  r.error = pickStr(raw, 'error');
  return r;
}

// 解析 GET /api/voice/voices → VoiceItem[]（失败/缺 voices → 空数组；Hub 已 snake→camel 转好 previewUrl）
export function parseVoicesResponse(json: string): VoiceItem[] {
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return [];
  }
  const arr = raw['voices'];
  if (arr === null || arr === undefined || !Array.isArray(arr)) { return []; }
  const list: Object[] = arr as Object[];
  const out: VoiceItem[] = [];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item !== null && item !== undefined && typeof item === 'object') {
      const rr: Record<string, Object> = item as Record<string, Object>;
      const v: VoiceItem = new VoiceItem();
      v.id = pickStr(rr, 'id');
      v.name = pickStr(rr, 'name');
      v.previewUrl = pickStr(rr, 'previewUrl');
      v.category = pickStr(rr, 'category');
      if (v.id !== '') { out.push(v); }
    }
  }
  return out;
}
