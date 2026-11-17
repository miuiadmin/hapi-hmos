// Hapi 核心数据类型（对齐 hapi shared/src）
// ArkTS 无 Zod，手写等价类型 + 安全解析（JSON → 强类型）

import { t } from '../i18n/Translate';

// —— 会话摘要（列表用，对齐 shared/src/sessionSummary.ts SessionSummary）——
// @ObservedV2 + @Trace：会话摘要为列表项数据源，列表 ForEach 同 key 复用项时，
//   须靠 @Trace 字段级响应驱动重渲染（整体替换数组/对象实例 → ForEach 视为同 key 不刷新 → 列表冻结）。
//   故 loadSessions 走 mergeSessionArrays 就地 copyFrom（改 @Trace 字段），非整体替换。对照 ChatBlock 范式。
@ObservedV2
export class SessionSummaryMetadata {
  @Trace name: string = '';           // 会话标题
  @Trace path: string = '';           // 工作目录
  @Trace machineId: string = '';
  @Trace summaryText: string = '';    // 摘要文本
  @Trace flavor: string = '';
  @Trace agentSessionId: string = '';
  @Trace worktreeBasePath: string = '';   // metadata.worktree.basePath（目录建议第二源；对照 shared WorktreeMetadata.basePath）

  // 就地拷贝（改 @Trace 子字段 → 触发依赖此字段的 UI 重渲染，如 title/summaryText getter）。
  copyFrom(o: SessionSummaryMetadata): void {
    this.name = o.name;
    this.path = o.path;
    this.machineId = o.machineId;
    this.summaryText = o.summaryText;
    this.flavor = o.flavor;
    this.agentSessionId = o.agentSessionId;
    this.worktreeBasePath = o.worktreeBasePath;
  }
}

@ObservedV2
export class SessionSummary {
  id: string = '';                  // 不变标识（ForEach key 派生自此），无需 @Trace
  @Trace active: boolean = false;
  @Trace thinking: boolean = false;
  @Trace activeAt: number = 0;
  @Trace updatedAt: number = 0;
  @Trace metadata: SessionSummaryMetadata | null = null;
  @Trace pendingRequestsCount: number = 0;
  @Trace backgroundTaskCount: number = 0;
  @Trace futureScheduledMessageCount: number = 0;   // 待触发的定时消息数（hub GET /api/sessions 返回；列表 ⏰ 角标）
  @Trace pendingRequestKinds: string[] = [];   // 待处理请求类型（'permission'|'input'；attention 指示器分级用）
  @Trace model: string = '';          // null → ''
  @Trace effort: string = '';
  @Trace todoCompleted: number = 0;
  @Trace todoTotal: number = 0;
  @Trace pinned: boolean = false;          // 项目级置顶（对照上游 #1115 SessionSummary.pinned；上游 optional ?? false）
  @Trace globalPinned: boolean = false;    // 全局置顶（跨项目；列表专区分组置顶）

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

  // 就地拷贝 fetched 字段到本对象（@Trace 字段变更触发 V2 重渲染，ForEach 同 key 保留项随之刷新）。
  //   metadata：有→有则就地 copyFrom 子字段；无→有则换引用（@Trace metadata 触发）。
  copyFrom(o: SessionSummary): void {
    this.active = o.active;
    this.thinking = o.thinking;
    this.activeAt = o.activeAt;
    this.updatedAt = o.updatedAt;
    this.pendingRequestsCount = o.pendingRequestsCount;
    this.backgroundTaskCount = o.backgroundTaskCount;
    this.futureScheduledMessageCount = o.futureScheduledMessageCount;
    this.pendingRequestKinds = o.pendingRequestKinds;
    this.model = o.model;
    this.effort = o.effort;
    this.todoCompleted = o.todoCompleted;
    this.todoTotal = o.todoTotal;
    this.pinned = o.pinned;
    this.globalPinned = o.globalPinned;
    if (o.metadata !== null) {
      if (this.metadata !== null) {
        this.metadata.copyFrom(o.metadata);
      } else {
        this.metadata = o.metadata;
      }
    } else {
      this.metadata = null;
    }
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

// Agent 事件（对齐 web/src/chat/types.ts AgentEvent 判别联合）。
//   ArkTS 无判别联合 → 单类 + type 判别串 + 扁平负载字段。type 取上游判别子串：
//   'api-error' | 'microcompact' | 'compact' | 'limit-warning' | 'limit-reached' | 'message'。
//   各 type 仅消费其相关字段，余保持默认（0 / ''）。由 Message.parseMessage 从 system 信封
//   （api_error / microcompact_boundary / compact_boundary）或直连 context_compacted 解析；
//   limit-warning / limit-reached 由 parseClaudeUsageLimit 从 agent 文本嗅探（#4 限额提示）。
//   EventPresentation 据此渲染居中灰条系统消息（#1）。
export class AgentEvent {
  type: string = '';
  // api-error（system/api_error；retryAttempt/maxRetries 来自 data 顶层）
  retryAttempt: number = 0;
  maxRetries: number = 0;
  // microcompact / compact（边界 metadata 或 context_compacted 顶层；trigger/preTokens 当前不渲染，留存）
  trigger: string = '';
  preTokens: number = 0;
  tokensSaved: number = 0;        // 仅 microcompact（「saved Nk tokens」文案用）
  // limit-warning / limit-reached（agent 文本嗅探）
  utilization: number = 0;        // 0–1 比例（limit-warning；warning 管线值 / 100）
  endsAt: number = 0;             // epoch-ms；0 = 无（上游按有无 endsAt 分支文案）
  limitType: string = '';
  // message
  message: string = '';
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
  pinned: boolean = false;                   // 项目级置顶（v0.27.3 #1115；详情响应 Session.pinned，对照 sessionCache.ts:184）
  globalPinned: boolean = false;             // 全局置顶（跨项目；列表专区分区 + 菜单三态入口）
  model: string = '';                       // nullable → ''
  effort: string = '';                       // claude 努力度（/effort 端点；nullable → ''）
  modelReasoningEffort: string = '';         // codex 推理努力（/model-reasoning-effort 端点；nullable → ''）
  permissionMode: string = '';               // 权限模式（/permission-mode 端点；optional → ''；claude: default/acceptEdits/bypassPermissions/plan）
  collaborationMode: string = '';            // codex 协作模式（/collaboration-mode 端点；optional → ''；default/plan）
  copilotAgentMode: string = '';             // copilot agent 模式（/copilot-agent-mode 端点 v0.26.0；optional → ''；interactive/plan/autopilot）
  flavor: string = '';                       // metadata.flavor（claude/codex/…；ContextStatusBar 算预算 + 配置 overlay 门控用）
  path: string = '';                         // metadata.path（会话工作目录；终端页顶栏显示 cwd）
  worktreeBranch: string = '';               // metadata.worktree.branch（git 分支；标题副标题显示，对照 shared WorktreeMetadata.branch）
  supersededBySessionId: string = '';        // metadata.supersededBySessionId（OpenCode /clear 取代流 v0.26.0；''=无取代）
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

// —— 浏览远端目录请求体（对齐 MachineListDirectoryRequest：path 非空 + 可选 includeHidden v0.26.0）——
//   includeHidden=true 时返回隐藏目录（. 开头）；默认 false（隐藏项不返）。HubClient 仅在非空 true 时随 body 发。
export class ListDirectoryRequest {
  path: string = '';
  includeHidden: boolean = false;
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

// —— Agent 类型（对齐 shared/src/modes.ts AGENT_FLAVORS v0.26.0：claude/codex/copilot/cursor/gemini/grok/kimi/opencode/pi）——
//   v0.26.0 相对 v0.25.4 新增 copilot（GitHub Copilot via ACP）；本次一并补齐此前未建模的 grok / pi 到上游全 9 项。
//   grok 仅有 flavor 识别 + 权限模式 + 显示名（其 grok-models / reasoning-effort 端点属 v0.25.4 既有，未在本次移植范围）。
//   pi 无运行时权限切换（上游 getPermissionModesForFlavor('pi') 返回 []）。
export const AGENT_FLAVORS: string[] = ['claude', 'codex', 'copilot', 'cursor', 'gemini', 'grok', 'kimi', 'opencode', 'pi'];

// Agent 显示名（下拉用；对照 shared/src/flavors.ts FLAVOR_LABELS，claude 沿用本项目「Claude Code」旧称）
//   v0.27.2 新增 agy（Antigravity）：仅识别 + 显示名 + 权限模式，**不进 AGENT_FLAVORS 创建列表**
//   （上游 agy 是 macOS-only PTY agent，平台门控；本端无法 spawn，故仅在显示/识别函数里兜底，避免已有 agy 会话崩）。
export function agentDisplayName(flavor: string): string {
  if (flavor === 'agy') { return 'Antigravity'; }
  if (flavor === 'claude') { return 'Claude Code'; }
  if (flavor === 'codex') { return 'Codex'; }
  if (flavor === 'copilot') { return 'Copilot'; }
  if (flavor === 'cursor') { return 'Cursor'; }
  if (flavor === 'gemini') { return 'Gemini CLI'; }
  if (flavor === 'grok') { return 'Grok Build'; }
  if (flavor === 'kimi') { return 'Kimi'; }
  if (flavor === 'opencode') { return 'OpenCode'; }
  if (flavor === 'pi') { return 'Pi'; }
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
//   permission-mode（/permission-mode 端点，全 flavor）：claude 4 / codex·gemini·kimi 4 / opencode 3 / cursor 6
//     （default/plan/ask/debug/autoReview/yolo）/ copilot 4（同 codex 形 default/read-only/safe-yolo/yolo）
//     / grok 4（default/auto/plan/bypassPermissions）/ agy 2（request-review/always-proceed，v0.27.2 新增）
//     / pi 无（[]）。
export const CLAUDE_PERMISSION_MODES: string[] = ['default', 'acceptEdits', 'bypassPermissions', 'plan'];
export const CODEX_PERMISSION_MODES: string[] = ['default', 'read-only', 'safe-yolo', 'yolo'];   // codex/gemini/kimi 共用
export const COPILOT_PERMISSION_MODES: string[] = ['default', 'read-only', 'safe-yolo', 'yolo']; // copilot（同 codex 形，对照 COPILOT_PERMISSION_MODES）
export const GROK_PERMISSION_MODES: string[] = ['default', 'auto', 'plan', 'bypassPermissions']; // grok（含 'auto' 自动放行模式）
export const AGY_PERMISSION_MODES: string[] = ['request-review', 'always-proceed']; // agy（Antigravity，v0.27.2 新增）
export const OPENCODE_PERMISSION_MODES: string[] = ['default', 'plan', 'yolo'];
export const CURSOR_PERMISSION_MODES: string[] = ['default', 'plan', 'ask', 'debug', 'autoReview', 'yolo'];
// collaboration-mode（/collaboration-mode 端点，仅 codex）：default/plan。
export const CODEX_COLLABORATION_MODES: string[] = ['default', 'plan'];
// copilot-agent-mode（/copilot-agent-mode 端点，仅 copilot；对照 shared/src/copilotModes.ts COPILOT_AGENT_MODES）。
//   'fleet' 为历史值，上游 coerce→interactive；我们只发合法三值，收到 fleet 时归一到 interactive（见 normalizeCopilotAgentMode）。
export const COPILOT_AGENT_MODES: string[] = ['interactive', 'plan', 'autopilot'];
export const COPILOT_AGENT_MODE_DEFAULT: string = 'interactive';
// model-reasoning-effort（/model-reasoning-effort 端点，codex/opencode）：codex low..xhigh / opencode low..max。
export const CODEX_REASONING_EFFORTS: string[] = ['low', 'medium', 'high', 'xhigh'];
export const OPENCODE_REASONING_EFFORTS: string[] = ['low', 'medium', 'high', 'max'];

export function permissionModesForFlavor(flavor: string): string[] {
  if (flavor === 'codex' || flavor === 'gemini' || flavor === 'kimi') { return CODEX_PERMISSION_MODES; }
  if (flavor === 'copilot') { return COPILOT_PERMISSION_MODES; }
  if (flavor === 'grok') { return GROK_PERMISSION_MODES; }
  if (flavor === 'opencode') { return OPENCODE_PERMISSION_MODES; }
  if (flavor === 'cursor') { return CURSOR_PERMISSION_MODES; }
  if (flavor === 'agy') { return AGY_PERMISSION_MODES; }   // agy（Antigravity，v0.27.2）：request-review/always-proceed
  if (flavor === 'pi') { return []; }   // pi 无运行时权限切换（上游恒 auto-approve）
  return CLAUDE_PERMISSION_MODES;   // claude + 未知回退
}
export function permissionModeDisplayName(mode: string): string {
  if (mode === 'default') { return t('types.default'); }
  if (mode === 'acceptEdits') { return t('types.permission.acceptEdits'); }
  if (mode === 'bypassPermissions') { return t('types.permission.bypass'); }
  if (mode === 'plan') { return t('types.permission.planMode'); }
  if (mode === 'ask') { return t('types.permission.ask'); }
  if (mode === 'debug') { return t('types.permission.debug'); }   // cursor debug 模式
  if (mode === 'autoReview') { return t('types.permission.autoReview'); }   // cursor 自动审查
  if (mode === 'read-only') { return t('types.permission.readonly'); }
  if (mode === 'safe-yolo') { return t('types.permission.safeYolo'); }
  if (mode === 'yolo') { return t('types.permission.yolo'); }
  if (mode === 'auto') { return t('types.permission.auto'); }   // grok 自动放行模式
  if (mode === 'request-review') { return t('types.permission.requestReview'); }   // agy（v0.27.2）
  if (mode === 'always-proceed') { return t('types.permission.alwaysProceed'); }   // agy（v0.27.2）
  return mode;
}
export function collaborationModeDisplayName(mode: string): string {
  if (mode === 'default') { return t('types.default'); }
  if (mode === 'plan') { return t('types.collaboration.plan'); }
  return mode;
}
// copilot agent 模式显示名（对照 COPILOT_AGENT_MODE_LABELS）
export function copilotAgentModeDisplayName(mode: string): string {
  if (mode === 'interactive') { return t('types.copilotAgent.interactive'); }
  if (mode === 'plan') { return t('types.copilotAgent.plan'); }
  if (mode === 'autopilot') { return t('types.copilotAgent.autopilot'); }
  return mode;
}
// 归一 copilot agent 模式：历史值 'fleet' / 非法值 → interactive（对照 normalizeCopilotAgentMode）。
export function normalizeCopilotAgentMode(value: string): string {
  if (value === 'fleet') { return 'interactive'; }
  if (value === 'interactive' || value === 'plan' || value === 'autopilot') { return value; }
  return 'interactive';
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
  s.pinned = pickBool(raw, 'pinned');
  s.globalPinned = pickBool(raw, 'globalPinned');
  s.model = pickStr(raw, 'model');
  s.effort = pickStr(raw, 'effort');
  s.modelReasoningEffort = pickStr(raw, 'modelReasoningEffort');
  s.permissionMode = pickStr(raw, 'permissionMode');
  s.collaborationMode = pickStr(raw, 'collaborationMode');
  // copilotAgentMode 是 Session 顶层字段（SessionSchema.copilotAgentMode v0.26.0）；'' 表示非 copilot 会话（保持空），
  //   有值时归一（历史 'fleet' → interactive）。仅 copilot 会话该字段有意义。
  {
    const copilotModeRaw = pickStr(raw, 'copilotAgentMode');
    s.copilotAgentMode = copilotModeRaw !== '' ? normalizeCopilotAgentMode(copilotModeRaw) : '';
  }
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
    // supersededBySessionId（OpenCode /clear 取代流 v0.26.0；对照 shared SessionMetadataSchema.supersededBySessionId）
    s.supersededBySessionId = pickStr(detailMeta, 'supersededBySessionId');
  }
  s.agentStateVersion = pickNum(raw, 'agentStateVersion');
  s.agentStateRaw = pickObj(raw, 'agentState');
  s.teamState = parseTeamState(pickObj(raw, 'teamState'));
  s.todos = parseTodoList(raw['todos']);
  return s;
}

// —— 会话取代流（OpenCode /clear：旧会话被新会话取代；对照 web/src/routes/sessions/followSupersedingSession.ts）——
//   metadata.supersededBySessionId 指向取代本会话的新会话；''（空/等于自身）= 无取代。
//   返回 '' 而非 null（ArkTS 无联合 null，简化调用方）。
export function getSupersedingSessionId(currentSessionId: string, supersededBySessionId: string): string {
  const replacement: string = supersededBySessionId.trim();
  if (replacement === '' || replacement === currentSessionId) { return ''; }
  return replacement;
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
  s.futureScheduledMessageCount = pickNum(raw, 'futureScheduledMessageCount');
  s.pinned = pickBool(raw, 'pinned');
  s.globalPinned = pickBool(raw, 'globalPinned');

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

// 列表就地合并：以 id 为键，复用既有 SessionSummary 对象（@ObservedV2 + @Trace），copyFrom 改字段
//   → 触发 V2 字段级重渲染，ForEach 同 key 保留项随之刷新（修「列表冻结，须重启 App 才更新」根因：
//   整体替换为新对象实例时 ForEach 视 key 不变 → 不重调 itemGenerator → 标题/状态点停在首帧）。
//   新增会话入列、删除会话丢弃；返回新数组引用（顺序跟随 fetched）供 sessionRows getter 重算分组结构。
export function mergeSessionArrays(existing: SessionSummary[], fetched: SessionSummary[]): SessionSummary[] {
  const map: Map<string, SessionSummary> = new Map<string, SessionSummary>();
  for (let i = 0; i < existing.length; i++) {
    map.set(existing[i].id, existing[i]);
  }
  const out: SessionSummary[] = [];
  for (let i = 0; i < fetched.length; i++) {
    const f: SessionSummary = fetched[i];
    if (map.has(f.id)) {
      const found: SessionSummary = map.get(f.id) as SessionSummary;
      found.copyFrom(f);
      out.push(found);
    } else {
      out.push(f);
    }
  }
  return out;
}
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

// —— 用量看板（对齐 shared/src/apiTypes.ts v0.26.0 UsageSummaryBucket / UsageSummaryResponse）——
//   GET /api/usage/summary?range=&timeZone=（仅 hub owner=namespace 'default'，非 owner 403）。
//   桶（bucket）= 某 key（日期/agent/model）的 token 计数；totals 额外含 sessions 计数；range.from/to 为 epoch ms（null→0）。
export class UsageSummaryBucket {
  key: string = '';
  inputTokens: number = 0;
  outputTokens: number = 0;
  cacheReadTokens: number = 0;
  cacheCreationTokens: number = 0;
  totalTokens: number = 0;
  uncachedTokens: number = 0;
  requests: number = 0;
}

export class UsageSummaryTotals {
  inputTokens: number = 0;
  outputTokens: number = 0;
  cacheReadTokens: number = 0;
  cacheCreationTokens: number = 0;
  totalTokens: number = 0;
  uncachedTokens: number = 0;
  requests: number = 0;
  sessions: number = 0;
}

// error 为客户端合成字段（HTTP 失败 / 非 owner 403 / 损坏体），上游响应无此字段。
export class UsageSummaryResponse {
  rangeFrom: number = 0;
  rangeTo: number = 0;
  totals: UsageSummaryTotals = new UsageSummaryTotals();
  daily: UsageSummaryBucket[] = [];
  byAgent: UsageSummaryBucket[] = [];
  byModel: UsageSummaryBucket[] = [];
  error: string = '';
}

// 从单个桶 Record 填充 UsageSummaryBucket（key + 7 计数）。
function fillUsageBucket(r: Record<string, Object>): UsageSummaryBucket {
  const b: UsageSummaryBucket = new UsageSummaryBucket();
  b.key = pickStr(r, 'key');
  b.inputTokens = pickNum(r, 'inputTokens');
  b.outputTokens = pickNum(r, 'outputTokens');
  b.cacheReadTokens = pickNum(r, 'cacheReadTokens');
  b.cacheCreationTokens = pickNum(r, 'cacheCreationTokens');
  b.totalTokens = pickNum(r, 'totalTokens');
  b.uncachedTokens = pickNum(r, 'uncachedTokens');
  b.requests = pickNum(r, 'requests');
  return b;
}

// 解析桶数组字段（字段名 → UsageSummaryBucket[]；缺失/非数组 → []）。
function parseUsageBuckets(raw: Record<string, Object>, field: string): UsageSummaryBucket[] {
  const arr = raw[field];
  if (arr === null || arr === undefined || !Array.isArray(arr)) { return []; }
  const list: Object[] = arr as Object[];
  const out: UsageSummaryBucket[] = [];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item !== null && item !== undefined && typeof item === 'object') {
      out.push(fillUsageBucket(item as Record<string, Object>));
    }
  }
  return out;
}

// 解析 GET /api/usage/summary → UsageSummaryResponse（HTTP 失败/非 owner 403/损坏体合成 error，桶全空）。
//   httpError 非空（如 403 文案 / 网络错）→ 直接挂 error 返回；正常体按 range/totals/daily/byAgent/byModel 解析。
export function parseUsageSummaryResponse(json: string, httpError: string): UsageSummaryResponse {
  const r: UsageSummaryResponse = new UsageSummaryResponse();
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    r.error = httpError !== '' ? httpError : t('types.usage.parseFailed');
    return r;
  }
  // 上游错误响应 { error: '...' }（如非 owner 403 的 JSON 体）
  const upstreamErr = pickStr(raw, 'error');
  if (upstreamErr !== '') {
    r.error = upstreamErr;
    return r;
  }
  const rangeRaw = pickObj(raw, 'range');
  if (rangeRaw !== null) {
    r.rangeFrom = pickNum(rangeRaw, 'from');
    r.rangeTo = pickNum(rangeRaw, 'to');
  }
  const totalsRaw = pickObj(raw, 'totals');
  if (totalsRaw !== null) {
    r.totals.inputTokens = pickNum(totalsRaw, 'inputTokens');
    r.totals.outputTokens = pickNum(totalsRaw, 'outputTokens');
    r.totals.cacheReadTokens = pickNum(totalsRaw, 'cacheReadTokens');
    r.totals.cacheCreationTokens = pickNum(totalsRaw, 'cacheCreationTokens');
    r.totals.totalTokens = pickNum(totalsRaw, 'totalTokens');
    r.totals.uncachedTokens = pickNum(totalsRaw, 'uncachedTokens');
    r.totals.requests = pickNum(totalsRaw, 'requests');
    r.totals.sessions = pickNum(totalsRaw, 'sessions');
  }
  r.daily = parseUsageBuckets(raw, 'daily');
  r.byAgent = parseUsageBuckets(raw, 'byAgent');
  r.byModel = parseUsageBuckets(raw, 'byModel');
  return r;
}

// —— Hub 设置（v0.27.2 GET/PUT /api/hub-settings，仅 hub owner=namespace default）——
//   对照 shared/src/apiTypes.ts HubSettingsResponse { sessionSummaryContract: boolean }。
//   sessionSummaryContract=true：Claude/Codex/OpenCode/远程 Grok 会话每轮末追加 AGENT_NOTIFY_SUMMARY 行
//   （更密的就绪通知）。默认关；本地 Grok 与 Cursor 暂不覆盖；对新开/恢复的会话生效。
export class HubSettingsResult {
  sessionSummaryContract: boolean = false;
  error: string = '';   // '' = 成功；非 owner 403 / 网络 / 解析错
}

export function parseHubSettingsResponse(json: string, httpError: string): HubSettingsResult {
  const r: HubSettingsResult = new HubSettingsResult();
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    r.error = httpError !== '' ? httpError : t('types.hubSettings.parseFailed');
    return r;
  }
  // 上游错误响应 { error: '...' }（如非 owner 403）
  const upstreamErr = pickStr(raw, 'error');
  if (upstreamErr !== '') {
    r.error = upstreamErr;
    return r;
  }
  r.sessionSummaryContract = pickBool(raw, 'sessionSummaryContract');
  return r;
}

// Sqlite 存储用量（GET /api/storage/sqlite，仅 hub owner）—— 对照 shared/src/apiTypes.ts
//   SqliteStorageUsageResponse { path, databaseBytes, walBytes, shmBytes, totalBytes }。
//   path: 数据库文件路径；database/wal/shm 三段字节；totalBytes 为 hub 汇总（可能与三段之和略有差异）。
export class SqliteStorageUsageResult {
  path: string = '';
  databaseBytes: number = 0;
  walBytes: number = 0;
  shmBytes: number = 0;
  totalBytes: number = 0;
  error: string = '';   // '' = 成功；非 owner 403 / 网络 / 解析错
}

export function parseSqliteStorageUsageResponse(json: string, httpError: string): SqliteStorageUsageResult {
  const r: SqliteStorageUsageResult = new SqliteStorageUsageResult();
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    r.error = httpError !== '' ? httpError : t('types.storage.parseFailed');
    return r;
  }
  const upstreamErr = pickStr(raw, 'error');
  if (upstreamErr !== '') {
    r.error = upstreamErr;
    return r;
  }
  r.path = pickStr(raw, 'path');
  r.databaseBytes = pickNum(raw, 'databaseBytes');
  r.walBytes = pickNum(raw, 'walBytes');
  r.shmBytes = pickNum(raw, 'shmBytes');
  r.totalBytes = pickNum(raw, 'totalBytes');
  return r;
}

// —— 语音转写凭证（v0.27.2 GET/PUT /api/voice/transcription/credentials，仅 hub owner）——
//   对照 shared/apiTypes + hub config/providerCredentials.ts。GET → TranscriptionCredentialStatus；
//   非 owner → 403 {error}。MaskedCredentialStatus = { configured, source, hint, editable }。
//   source='env'+editable=false = 环境变量锁定（只读，PUT 返 409）；hint = 脱敏密钥（••••+末4）。

export class MaskedCredentialStatus {
  configured: boolean = false;
  source: string = '';         // 'env' | 'settings' | 'none'
  hint: string = '';           // 脱敏密钥（null → ''）
  editable: boolean = false;
}

// OpenAI 兼容端点（baseUrl+model 决定 configured；apiKey 独立掩码）
export class OpenAiCompatibleCredentialStatus {
  configured: boolean = false;
  source: string = '';
  baseUrl: string = '';        // 实际未脱敏 URL（null → ''）
  model: string = '';          // 实际未脱敏模型 id（null → ''）
  baseUrlEditable: boolean = false;
  modelEditable: boolean = false;
  apiKey: MaskedCredentialStatus = new MaskedCredentialStatus();
}

export class TranscriptionCredentialStatus {
  openai: MaskedCredentialStatus = new MaskedCredentialStatus();
  elevenlabs: MaskedCredentialStatus = new MaskedCredentialStatus();
  deepgram: MaskedCredentialStatus = new MaskedCredentialStatus();
  groq: MaskedCredentialStatus = new MaskedCredentialStatus();
  openaiCompatible: OpenAiCompatibleCredentialStatus = new OpenAiCompatibleCredentialStatus();
  // voiceBackends 三项（elevenlabs/geminiLive/qwenRealtime）
  elevenlabsBackend: MaskedCredentialStatus = new MaskedCredentialStatus();
  geminiLive: MaskedCredentialStatus = new MaskedCredentialStatus();
  qwenRealtime: MaskedCredentialStatus = new MaskedCredentialStatus();
  error: string = '';          // 客户端合成（HTTP 失败 / 非 owner 403 / 损坏体）
}

// 解析单个 MaskedCredentialStatus 子对象
function parseMasked(r: Record<string, Object>): MaskedCredentialStatus {
  const m: MaskedCredentialStatus = new MaskedCredentialStatus();
  m.configured = pickBool(r, 'configured');
  m.source = pickStr(r, 'source');
  m.hint = pickStr(r, 'hint');
  m.editable = pickBool(r, 'editable');
  return m;
}

// 解析 GET /api/voice/transcription/credentials → TranscriptionCredentialStatus
export function parseTranscriptionCredentialsResponse(json: string, httpError: string): TranscriptionCredentialStatus {
  const r: TranscriptionCredentialStatus = new TranscriptionCredentialStatus();
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    r.error = httpError !== '' ? httpError : t('types.voice.credsParseFailed');
    return r;
  }
  const upstreamErr = pickStr(raw, 'error');
  if (upstreamErr !== '') {
    r.error = upstreamErr;
    return r;
  }
  const o: Record<string, Object> | null = pickObj(raw, 'openai');
  if (o !== null) { r.openai = parseMasked(o); }
  const e: Record<string, Object> | null = pickObj(raw, 'elevenlabs');
  if (e !== null) { r.elevenlabs = parseMasked(e); }
  const d: Record<string, Object> | null = pickObj(raw, 'deepgram');
  if (d !== null) { r.deepgram = parseMasked(d); }
  const g: Record<string, Object> | null = pickObj(raw, 'groq');
  if (g !== null) { r.groq = parseMasked(g); }
  const compat: Record<string, Object> | null = pickObj(raw, 'openaiCompatible');
  if (compat !== null) {
    r.openaiCompatible.configured = pickBool(compat, 'configured');
    r.openaiCompatible.source = pickStr(compat, 'source');
    r.openaiCompatible.baseUrl = pickStr(compat, 'baseUrl');
    r.openaiCompatible.model = pickStr(compat, 'model');
    r.openaiCompatible.baseUrlEditable = pickBool(compat, 'baseUrlEditable');
    r.openaiCompatible.modelEditable = pickBool(compat, 'modelEditable');
    const ak: Record<string, Object> | null = pickObj(compat, 'apiKey');
    if (ak !== null) { r.openaiCompatible.apiKey = parseMasked(ak); }
  }
  const vb: Record<string, Object> | null = pickObj(raw, 'voiceBackends');
  if (vb !== null) {
    const el: Record<string, Object> | null = pickObj(vb, 'elevenlabs');
    if (el !== null) { r.elevenlabsBackend = parseMasked(el); }
    const gl: Record<string, Object> | null = pickObj(vb, 'geminiLive');
    if (gl !== null) { r.geminiLive = parseMasked(gl); }
    const qr: Record<string, Object> | null = pickObj(vb, 'qwenRealtime');
    if (qr !== null) { r.qwenRealtime = parseMasked(qr); }
  }
  return r;
}
