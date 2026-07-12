import { getHubClient } from '../api/HubClient';
import { getSSEClient } from '../api/SSEClient';
import { ChatMessage, MessageStatus, parseMessage, mergeMessage, cloneMessage, UsageData, latestVisibleUsage, getContextBudgetTokens, formatTokenCount, sortQueuedMessages, formatScheduledIn } from '../models/Message';
import { SyncEvent, SyncEventType } from '../models/SyncEvent';
import { MarkdownText } from '../components/MarkdownText';
import { ToolCard } from '../components/ToolCard';
import { ReasoningBubble } from '../components/ReasoningBubble';
import { SessionActionMenu } from '../components/SessionActionMenu';
import { TeamPanel } from '../components/TeamPanel';
import { TodoPanel } from '../components/TodoPanel';
import { QueuedMessagesBar } from '../components/QueuedMessagesBar';
import { ConnectionBanner } from '../components/ConnectionBanner';
import { DateDivider } from '../components/DateDivider';
import { ChatBlock } from '../chat/ChatBlock';
import { reduceChatBlocks } from '../chat/Reducer';
import { blockMatchesQuery } from '../chat/ChatSearch';
import { SlashCommand, slashCommandSuggestions, getBuiltinSlashCommands } from '../chat/SlashCommands';
import { findActiveWord, applySuggestion } from '../chat/ActiveWord';
import { SlashMenu } from '../components/SlashMenu';
import { SessionConfigOverlay } from '../components/SessionConfigOverlay';
import { AgentState, parseAgentState } from '../chat/AgentState';
import { Session, TeamState, parseTeamState, TodoItem, parseTodoList } from '../models/Types';
import { paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { shouldShowDateDivider, formatClock, formatDateDivider } from '../utils/DateFormatUtils';
import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { getShareService } from '../services/ShareService';

// 对话页：消息流 + 输入发送 + SSE 实时接收
// 协议对照 hapi：GET /api/sessions/:id/messages 拉历史；POST 同端点发送（{ok:true}，真实消息靠 SSE message-received 回推）
// 流式模型：每条 message-received 是完整消息（非 token 增量），按 id 去重 / 按 localId 替换乐观行
// 渲染管线（对齐 web normalize→reduce→render）：ChatMessage[]+AgentState → reduceChatBlocks → ChatBlock[]（user-text/agent-text/tool-call/reasoning）→ ForEach 派发
// UI 对照 chatcube ChatPage：V2 (@ComponentV2/@Local)、List+Scroller 贴底跟随、左右气泡分色、TextArea 多行输入
// 通过 router_map.json 注册（ChatPageBuilder），由 Index 的 NavPathStack.pushPath('ChatPage') 触发
// 颜色经统一主题（theme/ThemeService）—— 读 getThemeState().isDark 取调色板，切换/跟随系统即时响应。

// 路由参数（对照 chatcube ChatPageRouteParams）
export class ChatPageRouteParams {
  sessionId: string = '';
  title: string = '';
}

@ComponentV2
struct ChatPage {
  @Param routeParamsSeed: ChatPageRouteParams | null = null;

  @Local messages: ChatMessage[] = [];
  @Local blocks: ChatBlock[] = [];            // 由 messages+agentState 派生的渲染单元（reducer 产出）
  @Local inputText: string = '';
  @Local isLoading: boolean = false;
  @Local loadError: string = '';
  @Local isThinking: boolean = false;          // agent 生成中（session-updated.thinking）
  @Local isSending: boolean = false;           // 发送请求进行中
  @Local sessionId: string = '';
  @Local agentState: AgentState | null = null; // 会话权限态（pending 请求队列等），SESSION_UPDATED 实时更新
  @Local nowTick: number = 0;                   // running 卡 elapsed 实时刷新驱动值（ticker 每秒 +1，仅 running 卡收到非 0）
  @Local hasMoreMessages: boolean = false;       // 还有更旧历史可加载（取自响应 page.hasMore）
  @Local isLoadingOlder: boolean = false;        // 加载更旧中（防抖 + 顶部指示器）

  // 会话生命周期（标题栏 ⋯ 菜单：重命名 / 归档 / 删除；委托 SessionActionMenu 组件，与 Index 长按菜单复用）
  @Local sessionTitle: string = '';              // 标题栏显示标题（aboutToAppear 取种子，重命名/SSE 更新）
  @Local isActive: boolean = true;               // 会话活跃态（归档/删除二选一：active→归档，否则→删除）
  @Local teamState: TeamState | null = null;     // 会话内多 agent 团队态（agent 自治上报；非 null 时消息列表上方渲染 TeamPanel）
  @Local todos: TodoItem[] = [];                 // 会话内待办清单（agent TodoWrite 上报；非空时消息列表上方渲染 TodoPanel）
  @Local model: string = '';                     // 会话 model（ContextStatusBar 算预算上限用；首屏/SSE 播种）
  @Local flavor: string = '';                    // 会话 flavor（claude/codex/…；getContextBudgetTokens 门控 + 配置 overlay 门控）
  @Local effort: string = '';                    // claude 努力度（/effort；首屏/SSE 播种；SessionConfigOverlay 用）
  @Local modelReasoningEffort: string = '';      // codex/opencode 推理努力（/model-reasoning-effort；首屏/SSE 播种）
  @Local permissionMode: string = '';            // 权限模式（/permission-mode；首屏/SSE 播种）
  @Local collaborationMode: string = '';         // codex 协作模式（/collaboration-mode；首屏/SSE 播种）
  @Local configSheetOpen: boolean = false;       // 会话配置 overlay 显隐（模型/权限/effort 即时改）
  @Local menuOpen: boolean = false;              // ⋯ 动作面板显隐（组件 @Param open；逻辑全在 SessionActionMenu）

  // 消息长按菜单（复制 / 重发[仅失败] / 分享）——底部动作 sheet，复用 SessionActionMenu 的 bindSheet 模式
  @Local messageMenuBlock: ChatBlock | null = null;   // 长按目标块（复制/重发/分享读其 text/userStatus）
  @Local messageMenuOpen: boolean = false;            // 动作 sheet 显隐
  @Local searchMode: boolean = false;                 // 🔍 对话内搜索栏显隐（标题栏 🔍/✕ 切换）
  @Local searchQuery: string = '';                     // 搜索查询（纯客户端过滤，对照 Index filteredSessions）
  @Local pendingSchedule: number = 0;                  // 待发定时（0=无/>0=epoch-ms；发送时拼 scheduledAt，对照 PendingSchedule）
  @Local scheduleSheetOpen: boolean = false;           // 定时选择 sheet 显隐
  @Local inputCursorStart: number = 0;                 // TextArea 光标区起点（onTextSelectionChange；活动词定位用）
  @Local inputCursorEnd: number = 0;                   // TextArea 光标区终点
  @Local slashSuggestions: SlashCommand[] = [];        // 斜杠补全建议（输入 / 触发；findActiveWord→slashCommandSuggestions）
  @Local slashSelectedIndex: number = 0;               // 补全高亮项（tap 即选；预留键盘扩展）
  private textAreaController: TextAreaController = new TextAreaController();   // 光标定位（applySuggestion 后 caretPosition 复位）

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  private navPathStack: NavPathStack | null = null;
  private scroller: Scroller = new Scroller();
  private isPinnedToBottom: boolean = true;
  private sseListenerId: number = -1;
  private localIdCounter: number = 0;
  private tickerId: number = -1;                // elapsed 每秒 ticker 句柄
  private nextBeforeAt: number = 0;              // 下一页「加载更旧」游标（服务端 page.nextBeforeAt，0=无更旧）
  private nextBeforeSeq: number = 0;             // 下一页游标 seq（与 nextBeforeAt 成对，禁止本地重算）

  aboutToAppear(): void {
    // @Param 在构造时已由 @Builder 注入，aboutToAppear 可读
    this.sessionId = this.routeParamsSeed !== null ? this.routeParamsSeed.sessionId : '';
    this.sessionTitle = this.routeParamsSeed !== null ? this.routeParamsSeed.title : '';
    this.loadMessages();
    this.addSSEListener();
    this.startTicker();
  }

  aboutToDisappear(): void {
    this.stopTicker();
    if (this.sseListenerId !== -1) {
      getSSEClient().removeListener(this.sseListenerId);
      this.sseListenerId = -1;
    }
  }

  // messages/agentState 变更统一走 setter，确保每次都重算 blocks（单一职责，避免漏调）
  private setMessages(list: ChatMessage[]): void {
    this.messages = list;
    this.recomputeBlocks();
  }

  private setAgentState(state: AgentState | null): void {
    this.agentState = state;
    this.recomputeBlocks();
  }

  private recomputeBlocks(): void {
    // 排队消息（isQueued：已发未被 CLI 消费，含即时排队 + 定时）不进 thread——对照 web SessionChat 过滤
    //   isQueuedForInvocation 行，仅由 QueuedMessagesBar 承载。thread 仅留已生效消息 + 失败行（可重发）。
    const visible: ChatMessage[] = this.messages.filter((m: ChatMessage): boolean => !m.isQueued);
    const reduced: ChatBlock[] = reduceChatBlocks(visible, this.agentState);
    // 盖「日期分隔」渲染标记：首条或与前一块不同日 → dividerBefore（纯序列判定，无 now 依赖）。
    //   盖在 block 自身字段（同 userOptimistic/userStatus 渲染提示），避免在 ForEach 闭包里依赖捕获的
    //   index/prev——后者在「加载更旧」prepend 重排后可能因 key 复用而不刷新（对齐 ArkUI ForEach 文档：
    //   「修改数据项若键值不变，则组件不更新」）。DateDivider 文本（今天/昨天/日期）在渲染时取。
    for (let i = 0; i < reduced.length; i++) {
      const prevTs: number = i > 0 ? reduced[i - 1].createdAt : 0;
      reduced[i].dividerBefore = shouldShowDateDivider(reduced[i].createdAt, prevTs);
    }
    this.blocks = reduced;
  }

  // 对话内搜索过滤视图（对照 Index.filteredSessions）：searchMode 关 或 空查询 → 全量；
  //   否则按 blockMatchesQuery 过滤。getter 在 build 中被读，V2 细粒度观察 searchMode/searchQuery/blocks
  //   任一变化即重渲染；过滤改变 ForEach 的 key 集合（命中入列 / 未命中出列）→ 必然刷新，
  //   无 key 复用冻结（对比「同 key 块换高亮样式」会撞 ForEach「键值不变则不更新」，故不取跳转+高亮方案）。
  get filteredBlocks(): ChatBlock[] {
    if (!this.searchMode) {
      return this.blocks;
    }
    const q: string = this.searchQuery.trim();
    if (q === '') {
      return this.blocks;
    }
    const out: ChatBlock[] = [];
    for (let i = 0; i < this.blocks.length; i++) {
      if (blockMatchesQuery(this.blocks[i], q)) {
        out.push(this.blocks[i]);
      }
    }
    return out;
  }

  // 是否处于「实际过滤」态（searchMode 且有非空查询）—— 决定压制日期分隔（过滤视图是非连续子集，分隔会误导）
  private isFiltering(): boolean {
    return this.searchMode && this.searchQuery.trim() !== '';
  }

  // 排队消息视图（对照 web sortQueuedMessages）：isQueued 行 + 排序（即时在前按 createdAt，定时在后按 scheduledAt）。
  //   getter 读 this.messages，messages 每次整体重赋值 → V2 自动重算；非空时 InputBar 上方渲染 QueuedMessagesBar。
  private get queuedMessages(): ChatMessage[] {
    const queued: ChatMessage[] = this.messages.filter((m: ChatMessage): boolean => m.isQueued);
    return sortQueuedMessages(queued);
  }

  // 待发定时标签（pendingSchedule>0 才显）
  private get pendingScheduleLabel(): string {
    if (this.pendingSchedule <= 0) { return ''; }
    return formatScheduledIn(this.pendingSchedule, Date.now());
  }

  // —— Token / 上下文用量（对照 web AssistantChat/StatusBar：ctx {size}/{max} (pct%) + cache 命中）——
  // 最新可见用量（反序取首条父上下文可见的 agent usage；对照 reducer latestUsage）。
  //   getter 读 this.messages，messages 每次整体重赋值（刷新策略）→ V2 观察引用变化即重算，无需手动维护。
  get latestUsage(): UsageData | null {
    return latestVisibleUsage(this.messages);
  }

  // 上下文预算上限：优先 usage.context_window，否则按 model/flavor 静态回退（getContextBudgetTokens）。
  //   < 0 = 无可用上限 → ContextStatusBar 只显 ctx {size}，不算百分比/告警（对照 StatusBar !maxContextSize 分支）。
  private get maxContextTokens(): number {
    const u = this.latestUsage;
    if (u !== null && u.contextWindow >= 0) { return u.contextWindow; }
    const budget = getContextBudgetTokens(this.model, this.flavor);
    return budget !== null ? budget : -1;
  }

  // 用量标签：有上限 → ctx {size}/{max} (pct%)；无上限 → ctx {size}（对照 contextUsageLabel）
  private get contextLabel(): string {
    const u = this.latestUsage;
    if (u === null) { return ''; }
    const size: number = u.contextSize;
    const max: number = this.maxContextTokens;
    if (max < 0) { return `ctx ${formatTokenCount(size)}`; }
    const pct: number = Math.min(100, Math.round((size / max) * 100));
    return `ctx ${formatTokenCount(size)}/${formatTokenCount(max)} (${pct}%)`;
  }

  // 告警配色：剩余 ≤5% 红 / ≤10% 琥珀 / 否则弱化灰（对照 getContextWarning 阈值）
  private get contextColor(): string {
    const u = this.latestUsage;
    if (u === null) { return this.c.textTertiary; }
    const max: number = this.maxContextTokens;
    if (max < 0) { return this.c.textTertiary; }
    const pctLeft: number = Math.max(0, 100 - (u.contextSize / max) * 100);
    if (pctLeft <= 5) { return this.c.error; }
    if (pctLeft <= 10) { return this.c.warning; }
    return this.c.textTertiary;
  }

  // 缓存命中标签：cache_read > 0 才显（对照 cacheHitLabel）
  private get cacheLabel(): string {
    const u = this.latestUsage;
    if (u === null || u.cacheRead <= 0) { return ''; }
    return `cache ${formatTokenCount(u.cacheRead)}`;
  }

  @Builder ContextStatusBar() {
    Row({ space: 8 }) {
      Text(this.contextLabel).fontSize(11).fontColor(this.contextColor)
      if (this.cacheLabel !== '') {
        Text(this.cacheLabel).fontSize(11).fontColor(this.c.textTertiary)
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 6, bottom: 4 })
    .justifyContent(FlexAlign.Start)
  }

  private toggleSearch(): void {
    this.searchMode = !this.searchMode;
    if (!this.searchMode) {
      this.searchQuery = '';   // 关闭即清空，重开为全新查询
    }
  }

  // elapsed 实时 ticker：仅当 thinking 或有 running 工具卡时每秒 bump nowTick（否则不 bump，避免无谓 rebuild）
  private startTicker(): void {
    this.stopTicker();
    this.tickerId = setInterval(() => {
      if (this.isThinking || this.hasRunningBlock()) {
        this.nowTick = this.nowTick + 1;
      }
    }, 1000);
  }

  private stopTicker(): void {
    if (this.tickerId !== -1) {
      clearInterval(this.tickerId);
      this.tickerId = -1;
    }
  }

  private hasRunningBlock(): boolean {
    for (let i = 0; i < this.blocks.length; i++) {
      if (this.isRunningBlock(this.blocks[i])) {
        return true;
      }
    }
    return false;
  }

  private isRunningBlock(b: ChatBlock): boolean {
    return b.tool !== null && b.tool.state === 'running';
  }

  // 审批/拒绝后主动刷新 agentState：防 SSE 漏事件导致卡不翻转；延迟 200ms 等服务端落库，失败静默（SSE 兜底）
  private refreshAfterDecision(): void {
    if (this.sessionId === '') {
      return;
    }
    setTimeout(() => {
      getHubClient().fetchSession(this.sessionId).then((session: Session) => {
        this.setAgentState(parseAgentState(session.agentStateRaw));
        this.teamState = session.teamState;
        this.todos = session.todos;
        this.model = session.model;
        this.flavor = session.flavor;
        this.effort = session.effort;
        this.permissionMode = session.permissionMode;
        this.collaborationMode = session.collaborationMode;
        this.modelReasoningEffort = session.modelReasoningEffort;
      }).catch(() => {});
    }, 200);
  }

  // 拉历史消息（首屏）+ 取初始 agentState（pending 权限等会话态）
  //   用分页接口取最新一页，同时拿到 page.hasMore / 下一页游标（nextBeforeAt/nextBeforeSeq）供「加载更旧」。
  private async loadMessages(): Promise<void> {
    if (this.sessionId === '') {
      return;
    }
    this.isLoading = true;
    this.loadError = '';
    try {
      const page = await getHubClient().fetchMessagesPage(this.sessionId);
      this.messages = page.messages;
      this.recomputeBlocks();
      this.hasMoreMessages = page.hasMore;
      this.nextBeforeAt = page.nextBeforeAt;
      this.nextBeforeSeq = page.nextBeforeSeq;
      // 取初始 agentState（取不到不影响消息展示）
      try {
        const session = await getHubClient().fetchSession(this.sessionId);
        this.setAgentState(parseAgentState(session.agentStateRaw));
        this.isActive = session.active;
        this.isThinking = session.thinking;   // 首屏播种：打开「正在生成」的会话即显停止按钮（对照上游立即 patch thinking）
        this.teamState = session.teamState;   // 首屏播种团队态（非 null 时消息列表上方渲染 TeamPanel）
        this.todos = session.todos;           // 首屏播种待办清单（非空时消息列表上方渲染 TodoPanel）
        this.model = session.model;            // 首屏播种 model/flavor（ContextStatusBar 算预算上限）
        this.flavor = session.flavor;
        this.effort = session.effort;
        this.permissionMode = session.permissionMode;        // 首屏播种会话内配置（SessionConfigOverlay 用）
        this.collaborationMode = session.collaborationMode;
        this.modelReasoningEffort = session.modelReasoningEffort;
      } catch (e) {
        this.agentState = null;
      }
      this.isPinnedToBottom = true;
      this.scrollToBottom();
    } catch (e) {
      this.loadError = e instanceof Error ? e.message : '加载消息失败';
    } finally {
      this.isLoading = false;
    }
  }

  // 加载更旧的历史消息（滚到顶触发）：透传服务端游标，prepend 后按 block 增量锚定滚动位置，保持视口不跳。
  //   对照上游 happy-thread：loadMore 守卫（hasMore && !isLoadingMore）+ 服务端游标 + prepend + 锚定恢复。
  private async loadOlderMessages(): Promise<void> {
    if (this.isLoading || this.isLoadingOlder || !this.hasMoreMessages || this.sessionId === '') {
      return;
    }
    if (this.nextBeforeAt === 0 || this.nextBeforeSeq === 0) {
      this.hasMoreMessages = false;   // 无有效游标 → 没有更旧
      return;
    }
    this.isLoadingOlder = true;
    const prevBlocksCount = this.blocks.length;   // prepend 后「旧首块」的新索引 = 新增 block 数
    try {
      const page = await getHubClient().fetchMessagesPage(this.sessionId, this.nextBeforeAt, this.nextBeforeSeq);
      // 去重（防游标边界极小概率重叠）：跳过已存在的 id
      const existing = this.messages;
      const fresh = page.messages.filter((m: ChatMessage): boolean => {
        if (m.id === '') {
          return true;
        }
        for (let i = 0; i < existing.length; i++) {
          if (existing[i].id === m.id) {
            return false;
          }
        }
        return true;
      });
      // 更新游标 / hasMore（取自服务端，成对透传；本页无新增则收敛不再 prepend）
      this.hasMoreMessages = page.hasMore && fresh.length > 0;
      this.nextBeforeAt = page.nextBeforeAt;
      this.nextBeforeSeq = page.nextBeforeSeq;
      if (fresh.length === 0) {
        return;
      }
      // 旧消息在前（fresh 已升序），prepend 到现有消息之前
      this.messages = fresh.concat(this.messages);
      this.recomputeBlocks();
      // 视口锚定：把「之前的首个 block」重新对齐到视口顶部，新增的更旧块在其上方（向上滚可见）
      const addedBlocks = this.blocks.length - prevBlocksCount;
      if (addedBlocks > 0) {
        setTimeout(() => {
          this.scroller.scrollToIndex(addedBlocks, false, ScrollAlign.START);
        }, 60);
      }
    } catch (e) {
      // 静默失败：不打断阅读，下次滚到顶可重试
    } finally {
      this.isLoadingOlder = false;
    }
  }

  private addSSEListener(): void {
    this.sseListenerId = getSSEClient().addListener({
      onEvent: (event: SyncEvent) => { this.onSSEEvent(event); }
    });
  }

  // 本会话 SSE 事件处理（全局连接，按 sessionId 过滤）
  private onSSEEvent(event: SyncEvent): void {
    if (event.sessionId !== this.sessionId) {
      return;
    }
    const t = event.type;
    if (t === SyncEventType.MESSAGE_RECEIVED) {
      const msgRaw = event.getObject('message');
      if (msgRaw !== null) {
        const msg = parseMessage(msgRaw);
        this.setMessages(mergeMessage(this.messages, msg));
        this.maybeScrollToBottom();
      }
    } else if (t === SyncEventType.MESSAGES_CONSUMED) {
      this.markMessagesConsumed(event);
    } else if (t === SyncEventType.MESSAGE_CANCELLED) {
      this.removeCancelledMessage(event);
    } else if (t === SyncEventType.SESSION_UPDATED) {
      this.handleSessionUpdated(event);
    } else if (t === SyncEventType.MESSAGES_INVALIDATED) {
      this.loadMessages();
    } else if (t === SyncEventType.SCHEDULED_MATURED) {
      // 定时消息成熟（到达预定时间被发出）→ 重拉本会话消息，补入这条新消息
      this.loadMessages();
    }
  }

  // thinking / active / 标题 / agentState（防御性：session 对象内或事件顶层均可；agentState 仅在 session 对象内取）
  //   active：归档后 patch {active:false} → 翻转菜单（归档→删除）。
  //   metadata.name：重命名（本端或远端）后 patch → 标题栏即时更新。
  //   两者须在 agentState 早返回之前处理，否则 agentState 存在时会跳过。
  private handleSessionUpdated(event: SyncEvent): void {
    const sessionObj = event.getObject('session');
    if (sessionObj !== null) {
      if (sessionObj['thinking'] === true) {
        this.isThinking = true;
      } else if (sessionObj['thinking'] === false) {
        this.isThinking = false;
      }
      if (sessionObj['active'] === true) {
        this.isActive = true;
      } else if (sessionObj['active'] === false) {
        this.isActive = false;
      }
      const metaVal = sessionObj['metadata'];
      if (metaVal !== null && metaVal !== undefined && typeof metaVal === 'object') {
        const meta = metaVal as Record<string, Object>;
        const nameVal = meta['name'];
        if (typeof nameVal === 'string' && nameVal !== '') {
          this.sessionTitle = nameVal;
        }
        // flavor 实时同步（ContextStatusBar 算预算上限门控）
        const flavorVal = meta['flavor'];
        if (typeof flavorVal === 'string') {
          this.flavor = flavorVal;
        }
      }
      // model 实时同步（ContextStatusBar 算预算上限：claude-/[1m]/codex 分档）
      const modelVal = sessionObj['model'];
      if (typeof modelVal === 'string') {
        this.model = modelVal;
      }
      // 会话内配置实时同步（SessionConfigOverlay 高亮）：本端 set 后服务端回推；null/缺省保留当前。
      const permVal = sessionObj['permissionMode'];
      if (typeof permVal === 'string') { this.permissionMode = permVal; }
      const collabVal = sessionObj['collaborationMode'];
      if (typeof collabVal === 'string') { this.collaborationMode = collabVal; }
      const reasoningVal = sessionObj['modelReasoningEffort'];
      if (typeof reasoningVal === 'string') { this.modelReasoningEffort = reasoningVal; }
      const effortVal = sessionObj['effort'];
      if (typeof effortVal === 'string') { this.effort = effortVal; }
      // teamState：会话内团队态实时更新（agent 自治上报；含 null 显式清除已解散团队）
      const teamVal = sessionObj['teamState'];
      if (teamVal !== null && teamVal !== undefined && typeof teamVal === 'object') {
        this.teamState = parseTeamState(teamVal as Record<string, Object>);
      } else if (teamVal === null) {
        this.teamState = null;
      }
      // todos：会话内待办清单实时更新（agent TodoWrite 上报；含 [] 显式清空）
      const todosVal = sessionObj['todos'];
      if (Array.isArray(todosVal)) {
        this.todos = parseTodoList(todosVal);
      } else if (todosVal === null) {
        this.todos = [];
      }
      // agentState：会话态实时更新（权限请求队列）
      const asVal = sessionObj['agentState'];
      if (asVal !== null && asVal !== undefined && typeof asVal === 'object') {
        this.setAgentState(parseAgentState(asVal as Record<string, Object>));
        return;
      }
    } else {
      if (event.raw['thinking'] === true) {
        this.isThinking = true;
      } else if (event.raw['thinking'] === false) {
        this.isThinking = false;
      }
    }
  }

  // CLI 消费了排队消息：对应 localId 的 user 消息置 sent + invokedAt
  private markMessagesConsumed(event: SyncEvent): void {
    const localIdsRaw = event.raw['localIds'];
    if (localIdsRaw === null || localIdsRaw === undefined || !Array.isArray(localIdsRaw)) {
      return;
    }
    const ids = localIdsRaw as string[];
    const invokedAt = event.getNumber('invokedAt');
    let changed = false;
    const next = this.messages.map((m: ChatMessage): ChatMessage => {
      if (m.localId !== '' && ids.indexOf(m.localId) >= 0) {
        const c = cloneMessage(m);
        c.invokedAt = invokedAt;
        c.status = 'sent';
        changed = true;
        return c;
      }
      return m;
    });
    if (changed) {
      this.setMessages(next);
    }
  }

  // 排队消息被取消：移除对应行
  private removeCancelledMessage(event: SyncEvent): void {
    const messageId = event.getString('messageId');
    const localId = event.getString('localId');
    const next = this.messages.filter((m: ChatMessage): boolean => {
      if (messageId !== '' && m.id === messageId) {
        return false;
      }
      if (localId !== '' && m.localId === localId) {
        return false;
      }
      return true;
    });
    if (next.length !== this.messages.length) {
      this.setMessages(next);
    }
  }

  // 发送：乐观插入 → POST（{ok:true}）→ 真实消息靠 SSE 回推替换
  private async handleSend(): Promise<void> {
    const text = this.inputText.trim();
    if (text === '' || this.isSending || this.sessionId === '') {
      return;
    }
    this.localIdCounter = this.localIdCounter + 1;
    const localId = `local-${Date.now()}-${this.localIdCounter}`;
    const schedule = this.pendingSchedule;   // 捕获待发定时（发送后清空）

    const optimistic = new ChatMessage();
    optimistic.id = localId;
    optimistic.localId = localId;
    optimistic.role = 'user';
    optimistic.text = text;
    optimistic.status = 'sending';
    optimistic.isOptimistic = true;
    optimistic.createdAt = Date.now();
    optimistic.scheduledAt = schedule;       // 定时乐观行：QueuedMessagesBar 显「⏰ X 后发送」

    this.setMessages(this.messages.concat([optimistic]));
    this.inputText = '';
    this.pendingSchedule = 0;                // 已捕获到 schedule，清空待发态
    this.slashSuggestions = [];               // 发送后清空残留补全（按钮发送不触发 recompute）
    this.inputCursorStart = 0;
    this.inputCursorEnd = 0;
    this.isSending = true;
    if (schedule <= 0) {
      this.isThinking = true;                // 即时发送才显生成中（定时未触发，agent 未跑）
    }
    this.scrollToBottom();

    try {
      const ok = await getHubClient().sendMessage(this.sessionId, text, localId, schedule);
      this.updateOptimisticStatus(localId, ok ? 'queued' : 'failed');
    } catch (e) {
      this.updateOptimisticStatus(localId, 'failed');
    } finally {
      this.isSending = false;
    }
  }

  private updateOptimisticStatus(localId: string, status: MessageStatus): void {
    const next = this.messages.map((m: ChatMessage): ChatMessage => {
      if (m.localId === localId && m.isOptimistic) {
        const c = cloneMessage(m);
        c.status = status;
        return c;
      }
      return m;
    });
    this.setMessages(next);
  }

  // 停止生成：中止会话运行（对照 web abortSession）
  private async handleStop(): Promise<void> {
    try {
      await getHubClient().abortSession(this.sessionId);
    } catch (e) {
      // 忽略
    }
    this.isThinking = false;
  }

  // —— 排队消息：编辑 / 取消（对照 web QueuedMessagesBar edit + useCancelQueuedMessage）——

  // 编辑 = 回填 composer（文本 + 恢复定时）+ 移除本行。有服务端 id 则顺带 cancel（服务器删）。
  private async editQueued(m: ChatMessage): Promise<void> {
    this.inputText = m.text;
    this.pendingSchedule = (m.scheduledAt > 0 && m.scheduledAt > Date.now()) ? m.scheduledAt : 0;
    this.slashSuggestions = [];               // 回填后清残留补全（光标未定位，不重算）
    this.inputCursorStart = m.text.length;
    this.inputCursorEnd = m.text.length;
    if (!m.isOptimistic && m.id !== '') {
      try { await getHubClient().cancelMessage(this.sessionId, m.id); } catch (e) { /* 乐观移除不阻塞 */ }
    }
    this.removeMessageLocal(m.id, m.localId);
  }

  // 取消排队消息：DELETE → cancelled 分支移除；invoked 分支（竞态：CLI 已消费）用权威行替换并入 thread。
  private async cancelQueued(m: ChatMessage): Promise<void> {
    if (m.isOptimistic || m.id === '') { return; }
    try {
      const result = await getHubClient().cancelMessage(this.sessionId, m.id);
      if (result.cancelled) {
        this.removeMessageLocal(m.id, m.localId);
      } else if (result.invokedMessage !== null) {
        this.setMessages(mergeMessage(this.messages, result.invokedMessage));
      }
    } catch (e) {
      this.toast('取消失败');
    }
  }

  // 本地移除一条消息（按 id 或 localId 匹配）
  private removeMessageLocal(id: string, localId: string): void {
    const next = this.messages.filter((m: ChatMessage): boolean => {
      if (id !== '' && m.id === id) { return false; }
      if (localId !== '' && m.localId === localId) { return false; }
      return true;
    });
    if (next.length !== this.messages.length) {
      this.setMessages(next);
    }
  }

  // —— 定时消息预设（对照 web ScheduleTimePicker：+5m/+30m/+1h/+4h）——
  //   skills/$ 等高级选择暂缓；绝对时间选择后续按需加（TimePicker+DatePicker）。
  private chooseSchedule(offsetMs: number): void {
    const now: number = Date.now();
    const max: number = now + 7 * 24 * 3600 * 1000;   // 上游 refine 7 天上限（预设最大 4h，此处为防御）
    const target: number = now + offsetMs;
    this.pendingSchedule = target <= max ? target : max;
    this.scheduleSheetOpen = false;
  }

  private clearSchedule(): void {
    this.pendingSchedule = 0;
    this.scheduleSheetOpen = false;
  }

  // —— 斜杠命令补全（对照 web useActiveWord + useSlashCommands.getSuggestions）——
  //   onTextSelectionChange / onChange 触发：以光标选区在 inputText 回溯找 '/' 前缀活动词，
  //   命中则按 flavor 取内置命令评分（精确/前缀/包含/Levenshtein），取前 6 条；否则清空。
  private recomputeSlash(): void {
    const aw = findActiveWord(this.inputText, this.inputCursorStart, this.inputCursorEnd, ['/']);
    if (aw === null || !aw.activeWord.startsWith('/')) {
      this.slashSuggestions = [];
      this.slashSelectedIndex = 0;
      return;
    }
    const all: SlashCommand[] = getBuiltinSlashCommands(this.flavor);
    const ranked: SlashCommand[] = slashCommandSuggestions(all, aw.activeWord);
    this.slashSuggestions = ranked.length > 6 ? ranked.slice(0, 6) : ranked;
    this.slashSelectedIndex = 0;
  }

  // 选中某建议：applySuggestion 把活动词替换为 '/name '，复位光标到新位置（TextAreaController.caretPosition）。
  private selectSlash(cmd: SlashCommand): void {
    const applied = applySuggestion(this.inputText, this.inputCursorStart, this.inputCursorEnd,
      `/${cmd.name}`, ['/'], true);
    this.inputText = applied.text;
    this.inputCursorStart = applied.cursorPosition;
    this.inputCursorEnd = applied.cursorPosition;
    this.slashSuggestions = [];
    this.slashSelectedIndex = 0;
    this.textAreaController.caretPosition(applied.cursorPosition);
  }

  // —— 会话内即时配置（对照 web setPermissionMode/setModel/...，5 端点）——
  //   每 tap 即发：乐观更新本地 @Local（overlay 立即高亮新值）→ 调 REST → 失败回滚 + toast。
  //   model/effort/reasoning '' 即发 null 复位（HubClient 内部转 null）。

  private async applyModel(model: string): Promise<void> {
    const prev = this.model;
    this.model = model;
    const ok = await getHubClient().setModel(this.sessionId, model);
    if (!ok) { this.model = prev; this.toast('修改模型失败'); }
  }
  private async applyPermissionMode(mode: string): Promise<void> {
    const prev = this.permissionMode;
    this.permissionMode = mode;
    const ok = await getHubClient().setPermissionMode(this.sessionId, mode);
    if (!ok) { this.permissionMode = prev; this.toast('修改权限模式失败'); }
  }
  private async applyCollaborationMode(mode: string): Promise<void> {
    const prev = this.collaborationMode;
    this.collaborationMode = mode;
    const ok = await getHubClient().setCollaborationMode(this.sessionId, mode);
    if (!ok) { this.collaborationMode = prev; this.toast('修改协作模式失败'); }
  }
  private async applyEffort(effort: string): Promise<void> {
    const prev = this.effort;
    this.effort = effort;
    const ok = await getHubClient().setEffort(this.sessionId, effort);
    if (!ok) { this.effort = prev; this.toast('修改努力度失败'); }
  }
  private async applyReasoningEffort(effort: string): Promise<void> {
    const prev = this.modelReasoningEffort;
    this.modelReasoningEffort = effort;
    const ok = await getHubClient().setModelReasoningEffort(this.sessionId, effort);
    if (!ok) { this.modelReasoningEffort = prev; this.toast('修改推理努力失败'); }
  }

  // —— 消息长按菜单（复制 / 重发 / 分享）——
  // 长按 user/agent 气泡 → 底部动作 sheet（复用 SessionActionMenu 的 bindSheet 模式，零 API 风险；
  //   移动端主流长按交互，对照 chatcube MessageBubble 菜单 + 上游 copy/retry 语义）。

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg });
  }

  private openMessageMenu(b: ChatBlock): void {
    this.messageMenuBlock = b;
    this.messageMenuOpen = true;
  }

  private closeMessageMenu(): void {
    this.messageMenuOpen = false;
  }

  // 写系统剪贴板（@ohos.pasteboard；对照 MarkdownText.copyToClipboard 同款实现）
  private copyToClipboard(text: string): void {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data)
      .then((): void => { this.toast('已复制'); })
      .catch((): void => { this.toast('复制失败'); });
  }

  private copyMessageText(): void {
    const b: ChatBlock | null = this.messageMenuBlock;
    if (b === null) {
      return;
    }
    const text: string = b.text;
    this.closeMessageMenu();
    this.copyToClipboard(text);
  }

  // 重发（仅失败用户消息，对齐上游 Retry）：复用同 localId + 同文重 POST → 置回 sending。
  //   失败的乐观行未被 SSE 替换，其 block.id 即 localId（handleSend 设 id=localId）。
  private async retryMessage(b: ChatBlock): Promise<void> {
    if (this.isSending || this.sessionId === '' || b.id === '') {
      return;
    }
    this.updateOptimisticStatus(b.id, 'sending');
    this.isSending = true;
    this.isThinking = true;
    try {
      const ok: boolean = await getHubClient().sendMessage(this.sessionId, b.text, b.id);
      this.updateOptimisticStatus(b.id, ok ? 'queued' : 'failed');
    } catch (e) {
      this.updateOptimisticStatus(b.id, 'failed');
    } finally {
      this.isSending = false;
    }
  }

  private retryMessageMenu(): void {
    const b: ChatBlock | null = this.messageMenuBlock;
    if (b === null) {
      return;
    }
    this.closeMessageMenu();
    this.retryMessage(b);
  }

  // 系统分享（@kit.ShareKit；对照 chatcube ShareService.shareText）
  private async shareMessageText(text: string): Promise<void> {
    if (text === '') {
      return;
    }
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined || hostContext === null) {
      this.toast('无法分享');
      return;
    }
    const ctx: common.UIAbilityContext = hostContext as common.UIAbilityContext;
    const r = await getShareService().shareText(ctx, text);
    if (!r.success) {
      this.toast('分享失败');
    }
  }

  private shareMessageMenu(): void {
    const b: ChatBlock | null = this.messageMenuBlock;
    if (b === null) {
      return;
    }
    const text: string = b.text;
    this.closeMessageMenu();
    this.shareMessageText(text);
  }

  // —— 导出 / 分享整个对话 ——
  // 按当前渲染的 blocks（与屏幕一致：user-text / agent-text / tool-call）拼成纯文本转录（含跨日日期分隔），
  //   经 ShareService 拉系统分享面板。上游 web 无 export，此为鸿蒙端增值（同单条分享）。
  private async exportConversation(): Promise<void> {
    if (this.blocks.length === 0) {
      this.toast('暂无可导出的消息');
      return;
    }
    const text: string = this.buildExportText();
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined || hostContext === null) {
      this.toast('无法分享');
      return;
    }
    const ctx: common.UIAbilityContext = hostContext as common.UIAbilityContext;
    const title: string = this.sessionTitle !== '' ? this.sessionTitle : '导出对话';
    const r = await getShareService().shareText(ctx, text, title);
    if (!r.success) {
      this.toast('分享失败');
    }
  }

  // 拼导出纯文本：标题 + 逐块（跨日日期分隔行 + HH:mm 角色 + 正文）。
  //   - 工具调用（tool-call）/ 思考过程（reasoning）不导出（只导出 user/agent 对话，转录更干净）；
  //   - 日期分隔复用 block.dividerBefore（recomputeBlocks 盖戳，与屏幕 DateDivider 同款）+ formatDateDivider；
  //   - 无 markdown 语法（#/**/> 等），便于粘贴到任意纯文本目标。
  //   已知边角：若某新日首块恰好是被跳过的工具调用/思考过程，其 dividerBefore 分隔随之丢失（导出断档，屏幕正常）。
  private buildExportText(): string {
    const lines: string[] = [];
    const title: string = this.sessionTitle !== '' ? this.sessionTitle : '对话';
    lines.push(title);
    lines.push('');
    for (let i = 0; i < this.blocks.length; i++) {
      const b: ChatBlock = this.blocks[i];
      if (b.kind === 'tool-call' || b.kind === 'reasoning') {
        continue;   // 工具调用 / 思考过程不导出（只导出 user/agent 对话）
      }
      if (b.dividerBefore) {
        lines.push(`——— ${formatDateDivider(b.createdAt)} ———`);
        lines.push('');
      }
      const clock: string = b.createdAt > 0 ? formatClock(b.createdAt) : '--:--';
      lines.push(b.kind === 'user-text' ? `${clock} 用户` : `${clock} 助手`);
      lines.push('');
      lines.push(b.text);
      lines.push('');
    }
    return lines.join('\n');
  }

  // 该 reasoning 块是否「正在流式思考」：是当前最后一块 + 会话 thinking 中（对照上游 isStreaming：
  //   message running 且末块为 reasoning）。用于 ReasoningBubble 自动展开 + 流式指示。
  //   末块判定用 id 比较，避免依赖 ForEach 下标。
  private isReasoningStreaming(b: ChatBlock): boolean {
    if (!this.isThinking) {
      return false;
    }
    const n: number = this.blocks.length;
    return n > 0 && this.blocks[n - 1].id === b.id;
  }

  // 滚动控制（仅贴底时跟随，上滑读历史不打断，对照 chatcube alignToBottomIfPinned）
  private scrollToBottom(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 120);
  }

  private maybeScrollToBottom(): void {
    if (this.isPinnedToBottom) {
      this.scrollToBottom();
    }
  }

  private statusText(s: string): string {
    if (s === 'sending') {
      return '发送中';
    }
    if (s === 'queued') {
      return '排队中';
    }
    if (s === 'failed') {
      return '发送失败';
    }
    return '';
  }

  // 用户气泡（靠右、主色、右下尖角）+ 发送时间（HH:mm，气泡下方右对齐）
  @Builder
  private UserBubble(b: ChatBlock) {
    Row() {
      Blank()
      // 右簇：气泡 + 时间，整体右对齐（时间贴气泡右下）
      Column() {
        Column() {
          Text(b.text)
            .fontSize(15)
            .fontColor(this.c.bubbleUserText)
          if (b.userOptimistic) {
            Text(this.statusText(b.userStatus))
              .fontSize(10)
              .fontColor('rgba(255,255,255,0.75)')
              .margin({ top: 2 })
          }
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(b.userStatus === 'failed' ? this.c.error : this.c.primary)
        .borderRadius({ topLeft: 16, topRight: 16, bottomLeft: 16, bottomRight: 4 })
        .constraintSize({ maxWidth: '78%' })
        .alignItems(HorizontalAlign.End)

        if (b.createdAt > 0) {
          Text(formatClock(b.createdAt))
            .fontSize(10)
            .fontColor(this.c.textTertiary)
            .margin({ top: 3, right: 2 })
        }
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
    // priorityGesture 与 agent 气泡保持一致（user 气泡是纯 Text 无内部长按冲突，但统一写法）
    .priorityGesture(LongPressGesture({ duration: 500, repeat: false })
      .onAction(() => { this.openMessageMenu(b); }))
  }

  // agent 文本气泡（靠左、表面色，Markdown 渲染）+ 时间（HH:mm，气泡下方左对齐）
  @Builder
  private AgentBubble(b: ChatBlock) {
    Row() {
      // 左簇：气泡 + 时间，整体左对齐（时间贴气泡左下）
      Column() {
        Column() {
          MarkdownText({ content: b.text })
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(this.c.surface)
        .borderRadius(16)
        .constraintSize({ maxWidth: '85%' })
        .alignItems(HorizontalAlign.Start)
        .clip(true)

        if (b.createdAt > 0) {
          Text(formatClock(b.createdAt))
            .fontSize(10)
            .fontColor(this.c.textTertiary)
            .margin({ top: 3, left: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    // priorityGesture（非 gesture）：让本气泡长按压过内嵌 MarkdownText(CJMarkdown) 的长按（文本选择），
    // 否则长按 agent 气泡会被 markdown 吞掉、不开菜单。仅同型手势竞争 → 不影响链接点按。
    .priorityGesture(LongPressGesture({ duration: 500, repeat: false })
      .onAction(() => { this.openMessageMenu(b); }))
  }

  // 空态：无消息且非生成中
  @Builder
  private EmptyState() {
    Column({ space: 8 }) {
      Text('💬')
        .fontSize(40)
      Text('开始对话')
        .fontSize(15)
        .fontColor(this.c.textPrimary)
      Text('向 agent 发送消息开始协作')
        .fontSize(12)
        .fontColor(this.c.textTertiary)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  // 生成中指示器（贴底，靠左）
  @Builder
  private TypingIndicator() {
    Row() {
      Text('思考中…')
        .fontSize(14)
        .fontColor(this.c.textTertiary)
        .padding({ left: 14, right: 14, top: 9, bottom: 9 })
        .backgroundColor(this.c.surface)
        .borderRadius(16)
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
  }

  // 顶部「加载更早消息」指示器（isLoadingOlder 时显示在列表上方）
  @Builder
  private LoadingOlderBar() {
    Row({ space: 6 }) {
      LoadingProgress().width(16).height(16).color(this.c.textTertiary)
      Text('加载更早消息…')
        .fontSize(12)
        .fontColor(this.c.textTertiary)
    }
    .width('100%')
    .height(28)
    .justifyContent(FlexAlign.Center)
  }

  // 输入栏（定时按钮 + TextArea 多行 + 发送/停止按钮）
  @Builder
  private InputBar() {
    Column({ space: 4 }) {
      // 待发定时 chip（pendingSchedule>0 显形；点 ✕ 清除，对照 web PendingSchedule 徽标）
      if (this.pendingSchedule > 0) {
        Row({ space: 6 }) {
          Text(`⏰ ${this.pendingScheduleLabel}`)
            .fontSize(12)
            .fontColor(this.c.warning)
            .layoutWeight(1)
          Text('✕')
            .fontSize(13)
            .fontColor(this.c.textTertiary)
            .onClick(() => { this.pendingSchedule = 0; })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 4 })
      }
      // 斜杠补全浮层（输入 / 触发；挂输入行正上方，对照 web 建议列表）
      if (this.slashSuggestions.length > 0) {
        SlashMenu({
          suggestions: this.slashSuggestions,
          selectedIndex: this.slashSelectedIndex,
          onSelect: (cmd: SlashCommand): void => { this.selectSlash(cmd); }
        })
      }
      Row({ space: 8 }) {
        // 定时按钮：开 ScheduleSheet 选预设；已设定时显 ⏰+警告色
        Text(this.pendingSchedule > 0 ? '⏰' : '🕖')
          .fontSize(18)
          .fontColor(this.pendingSchedule > 0 ? this.c.warning : this.c.textSecondary)
          .width(36)
          .height(40)
          .textAlign(TextAlign.Center)
          .onClick(() => { this.scheduleSheetOpen = true; })

        TextArea({ text: this.inputText, placeholder: '输入消息…', controller: this.textAreaController })
          .layoutWeight(1)
          .fontSize(15)
          .fontColor(this.c.textPrimary)
          .placeholderColor(this.c.textTertiary)
          .constraintSize({ minHeight: 40, maxHeight: 100 })
          .backgroundColor(this.c.surface)
          .borderRadius(20)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .onChange((v: string) => {
            this.inputText = v;
            this.recomputeSlash();
          })
          .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
            this.inputCursorStart = selectionStart;
            this.inputCursorEnd = selectionEnd;
            this.recomputeSlash();
          })

        Button(this.isThinking ? '停止' : '发送')
          .fontSize(15)
          .height(40)
          .backgroundColor(this.isThinking ? this.c.surface : this.c.primary)
          .fontColor(this.isThinking ? this.c.error : this.c.bubbleUserText)
          .borderRadius(20)
          .enabled(!this.isSending && (this.isThinking || this.inputText.trim() !== ''))
          .onClick(() => {
            if (this.isThinking) {
              this.handleStop();
            } else {
              this.handleSend();
            }
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.c.bg)
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .backgroundColor(this.c.bg)
  }

  // 定时选择 sheet（对照 web ScheduleTimePicker 预设：+5m/+30m/+1h/+4h；MVP 仅预设，绝对时间后续加）
  @Builder
  private scheduleOption(label: string, offsetMs: number) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor(this.c.textPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .height(48)
    .padding({ left: 20, right: 20 })
    .onClick(() => { this.chooseSchedule(offsetMs); })
  }

  @Builder
  private ScheduleSheet() {
    Column() {
      Text('定时发送')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.textPrimary)
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 4 })

      this.scheduleOption('+5 分钟', 5 * 60 * 1000)
      this.scheduleOption('+30 分钟', 30 * 60 * 1000)
      this.scheduleOption('+1 小时', 60 * 60 * 1000)
      this.scheduleOption('+4 小时', 4 * 60 * 60 * 1000)

      if (this.pendingSchedule > 0) {
        Row() {
          Text('清除定时')
            .fontSize(15)
            .fontColor(this.c.error)
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 20, right: 20 })
        .onClick(() => { this.clearSchedule(); })
      }
    }
    .width('100%')
    .backgroundColor(this.c.bg)
  }

  // 会话配置 sheet（包 SessionConfigOverlay；当前值/回调全接本页 @Local 与 applyXxx）
  @Builder
  private ConfigSheet() {
    SessionConfigOverlay({
      flavor: this.flavor,
      model: this.model,
      effort: this.effort,
      modelReasoningEffort: this.modelReasoningEffort,
      permissionMode: this.permissionMode,
      collaborationMode: this.collaborationMode,
      onSetModel: (m: string): void => { this.applyModel(m); },
      onSetEffort: (e: string): void => { this.applyEffort(e); },
      onSetReasoningEffort: (e: string): void => { this.applyReasoningEffort(e); },
      onSetPermissionMode: (m: string): void => { this.applyPermissionMode(m); },
      onSetCollaborationMode: (m: string): void => { this.applyCollaborationMode(m); }
    })
  }

  // 标题栏右侧菜单（NavDestination.menus CustomBuilder，对照 chatcube SettingsNavigationMenus）：
  //   ↗ 导出/分享整个对话 + ⋯ 重命名/归档/删除（动作面板逻辑全在 SessionActionMenu 组件内）
  @Builder
  private HeaderMenu() {
    Row({ space: 2 }) {
      Text(this.searchMode ? '✕' : '🔍')
        .fontSize(18)
        .fontColor(this.searchMode ? this.c.primary : this.c.textSecondary)
        .width(36)
        .height(40)
        .textAlign(TextAlign.Center)
        .onClick(() => { this.toggleSearch(); })
      Text('↗')
        .fontSize(20)
        .fontColor(this.c.textSecondary)
        .width(36)
        .height(40)
        .textAlign(TextAlign.Center)
        .onClick(() => { this.exportConversation(); })
      // 会话内配置（模型/权限/effort 即时改；对照 web FloatingOverlay）
      Text('🎛')
        .fontSize(18)
        .fontColor(this.c.textSecondary)
        .width(36)
        .height(40)
        .textAlign(TextAlign.Center)
        .onClick(() => { this.configSheetOpen = true; })
      Text('⋯')
        .fontSize(22)
        .fontColor(this.c.textSecondary)
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .onClick(() => { this.menuOpen = true; })
    }
  }

  // 对话内搜索栏（对照 Index 顶栏 Search 组件：内置 ✕ 仅清文本；标题栏 🔍/✕ 切整栏显隐）
  //   过滤中显示「N 个匹配」（0 命中即「0 个匹配」=空反馈，无需另设空态分支）。
  @Builder
  private SearchBar() {
    Column({ space: 4 }) {
      Search({ value: this.searchQuery, placeholder: '搜索对话内消息…' })
        .height(40)
        .backgroundColor(this.c.surface)
        .placeholderColor(this.c.textTertiary)
        .onChange((value: string) => { this.searchQuery = value; })
      if (this.isFiltering()) {
        Text(`${this.filteredBlocks.length} 个匹配`)
          .fontSize(12)
          .fontColor(this.c.textTertiary)
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 4 })
  }

  // 消息长按动作面板：复制 / 重发（仅失败用户消息）/ 分享
  // （对照 chatcube MessageBubble UserMoreMenu + 上游 copy/retry 语义；FIT_CONTENT 高度自适应）
  @Builder
  private MessageMenuSheet() {
    Column() {
      Row() {
        Text('复制').fontSize(16).fontColor(this.c.textPrimary).layoutWeight(1)
      }
      .width('100%')
      .height(52)
      .padding({ left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => { this.copyMessageText(); })

      Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 20, right: 20 })

      // 重发：仅失败的用户消息（对齐上游 Retry；成功/agent/工具卡不显示）
      if (this.messageMenuBlock !== null
        && this.messageMenuBlock.kind === 'user-text'
        && this.messageMenuBlock.userStatus === 'failed') {
        Row() {
          Text('重发').fontSize(16).fontColor(this.c.textPrimary).layoutWeight(1)
        }
        .width('100%')
        .height(52)
        .padding({ left: 20, right: 20 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => { this.retryMessageMenu(); })

        Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 20, right: 20 })
      }

      Row() {
        Text('分享').fontSize(16).fontColor(this.c.textPrimary).layoutWeight(1)
      }
      .width('100%')
      .height(52)
      .padding({ left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => { this.shareMessageMenu(); })
    }
    .width('100%')
    .backgroundColor(this.c.bg)
    .padding({ bottom: 20 })
  }

  build() {
    NavDestination() {
      Column() {
        // 连接状态横幅（SSE 重连/断开时显形；常态 Visibility.None 不占位）
        ConnectionBanner()
        if (this.isLoading && this.messages.length === 0) {
          Column() {
            LoadingProgress().width(36).height(36).color(this.c.primary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.loadError !== '' && this.messages.length === 0) {
          Column({ space: 10 }) {
            Text('加载失败').fontSize(15).fontColor(this.c.error)
            Text(this.loadError).fontSize(12).fontColor(this.c.textTertiary).textAlign(TextAlign.Center)
            Button('重试')
              .fontSize(13)
              .backgroundColor(this.c.primary)
              .fontColor(this.c.bubbleUserText)
              .onClick(() => this.loadMessages())
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.blocks.length === 0 && !this.isThinking) {
          this.EmptyState()
        } else {
          Column() {
            if (this.teamState !== null) {
              TeamPanel({ teamState: this.teamState as TeamState })
                .margin({ left: 12, right: 12, top: 8 })
            }
            if (this.todos.length > 0) {
              TodoPanel({ todos: this.todos })
                .margin({ left: 12, right: 12, top: 8 })
            }
            if (this.searchMode) {
              this.SearchBar()
            }
            if (this.isLoadingOlder) {
              this.LoadingOlderBar()
            }
            List({ scroller: this.scroller, space: 8 }) {
              ForEach(this.filteredBlocks, (b: ChatBlock) => {
                ListItem() {
                  Column() {
                    // 跨日（或首条）日期分隔（dividerBefore 由 recomputeBlocks 盖戳）；
                    //   过滤视图是非连续子集，分隔会误导 → 实际过滤时（非空查询）不显示。
                    if (b.dividerBefore && !this.isFiltering()) {
                      DateDivider({ timestamp: b.createdAt })
                    }
                    if (b.kind === 'user-text') {
                      this.UserBubble(b)
                    } else if (b.kind === 'agent-text') {
                      this.AgentBubble(b)
                    } else if (b.kind === 'reasoning') {
                      ReasoningBubble({
                        text: b.text,
                        isStreaming: this.isReasoningStreaming(b)
                      })
                    } else {
                      ToolCard({
                        block: b,
                        sessionId: this.sessionId,
                        nowTick: this.isRunningBlock(b) ? this.nowTick : 0,
                        onDecided: () => { this.refreshAfterDecision(); }
                      })
                    }
                  }
                }
              }, (b: ChatBlock) => b.id)

              if (this.isThinking) {
                ListItem() {
                  this.TypingIndicator()
                }
              }
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .onReachStart(() => {
              // 过滤中不分页：命中少/空时列表易贴顶，否则会级联拉完全部历史页（搜不到时尤甚）。
              //   搜不到 → 清搜索、手动滚顶加载更旧后再搜。
              if (!this.isFiltering()) {
                this.loadOlderMessages();
              }
            })
            .onScrollStop(() => {
              this.isPinnedToBottom = this.scroller.isAtEnd();
            })
          }
          .width('100%')
          .layoutWeight(1)
        }

        // Token / 上下文用量条（对照 web AssistantChat/StatusBar：仅在有可见 usage 时显形）
        if (this.latestUsage !== null) {
          this.ContextStatusBar()
        }

        // 排队消息条（已发未被 CLI 消费：即时排队 + 定时；对照 web QueuedMessagesBar，挂 InputBar 正上方）
        if (this.queuedMessages.length > 0) {
          QueuedMessagesBar({
            queued: this.queuedMessages,
            onEdit: (m: ChatMessage): void => { this.editQueued(m); },
            onCancel: (m: ChatMessage): void => { this.cancelQueued(m); }
          })
        }

        Column() {
          this.InputBar()
        }
        .bindSheet(this.scheduleSheetOpen, this.ScheduleSheet(), {
          detents: [SheetSize.FIT_CONTENT],
          dragBar: true,
          showClose: true,
          onDisappear: (): void => { this.scheduleSheetOpen = false; }
        })

        // 标题栏 ⋯ 菜单：重命名/归档/删除全委托 SessionActionMenu（与 Index 长按复用同一组件）
        //   重命名成功 → 更新本页标题；归档成功 → isActive 置 false（菜单翻删除，不离开页）；删除成功 → pop 回列表
        SessionActionMenu({
          sessionId: this.sessionId,
          title: this.sessionTitle,
          active: this.isActive,
          open: this.menuOpen,
          onClose: () => { this.menuOpen = false; },
          onRenamed: (name: string) => { this.sessionTitle = name; },
          onArchived: () => { this.isActive = false; },
          onDeleted: () => { if (this.navPathStack !== null) { this.navPathStack.pop(); } }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.c.bg)
      .bindSheet(this.messageMenuOpen, this.MessageMenuSheet(), {
        detents: [SheetSize.FIT_CONTENT],
        dragBar: true,
        showClose: false,
        onDisappear: (): void => { this.closeMessageMenu(); }
      })
      .bindSheet(this.configSheetOpen, this.ConfigSheet(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        dragBar: true,
        showClose: true,
        onDisappear: (): void => { this.configSheetOpen = false; }
      })
    }
    .title(this.sessionTitle !== '' ? this.sessionTitle : '对话')
    .menus(this.HeaderMenu)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack;
      const param = context.pathInfo.param as ChatPageRouteParams;
      if (param !== null && param !== undefined) {
        this.routeParamsSeed = param;
        if (this.sessionId === '') {
          this.sessionId = param.sessionId;
        }
      }
    })
  }
}

// 系统路由表 buildFunction（router_map.json 引用）
@Builder
export function ChatPageBuilder(name: string, param: Object) {
  ChatPage({ routeParamsSeed: param as ChatPageRouteParams })
}
