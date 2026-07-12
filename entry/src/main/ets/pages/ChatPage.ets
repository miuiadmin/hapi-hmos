import { getHubClient } from '../api/HubClient';
import { getSSEClient } from '../api/SSEClient';
import { ChatMessage, MessageStatus, parseMessage, mergeMessage, cloneMessage } from '../models/Message';
import { SyncEvent, SyncEventType } from '../models/SyncEvent';
import { MarkdownText } from '../components/MarkdownText';
import { ToolCard } from '../components/ToolCard';
import { ReasoningBubble } from '../components/ReasoningBubble';
import { SessionActionMenu } from '../components/SessionActionMenu';
import { DateDivider } from '../components/DateDivider';
import { ChatBlock } from '../chat/ChatBlock';
import { reduceChatBlocks } from '../chat/Reducer';
import { blockMatchesQuery } from '../chat/ChatSearch';
import { AgentState, parseAgentState } from '../chat/AgentState';
import { Session } from '../models/Types';
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
  @Local menuOpen: boolean = false;              // ⋯ 动作面板显隐（组件 @Param open；逻辑全在 SessionActionMenu）

  // 消息长按菜单（复制 / 重发[仅失败] / 分享）——底部动作 sheet，复用 SessionActionMenu 的 bindSheet 模式
  @Local messageMenuBlock: ChatBlock | null = null;   // 长按目标块（复制/重发/分享读其 text/userStatus）
  @Local messageMenuOpen: boolean = false;            // 动作 sheet 显隐
  @Local searchMode: boolean = false;                 // 🔍 对话内搜索栏显隐（标题栏 🔍/✕ 切换）
  @Local searchQuery: string = '';                     // 搜索查询（纯客户端过滤，对照 Index filteredSessions）

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
    const reduced: ChatBlock[] = reduceChatBlocks(this.messages, this.agentState);
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
        const nameVal = (metaVal as Record<string, Object>)['name'];
        if (typeof nameVal === 'string' && nameVal !== '') {
          this.sessionTitle = nameVal;
        }
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

    const optimistic = new ChatMessage();
    optimistic.id = localId;
    optimistic.localId = localId;
    optimistic.role = 'user';
    optimistic.text = text;
    optimistic.status = 'sending';
    optimistic.isOptimistic = true;
    optimistic.createdAt = Date.now();

    this.setMessages(this.messages.concat([optimistic]));
    this.inputText = '';
    this.isSending = true;
    this.isThinking = true;
    this.scrollToBottom();

    try {
      const ok = await getHubClient().sendMessage(this.sessionId, text, localId);
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

  // 输入栏（TextArea 多行 + 发送/停止按钮）
  @Builder
  private InputBar() {
    Row({ space: 8 }) {
      TextArea({ text: this.inputText, placeholder: '输入消息…' })
        .layoutWeight(1)
        .fontSize(15)
        .fontColor(this.c.textPrimary)
        .placeholderColor(this.c.textTertiary)
        .constraintSize({ minHeight: 40, maxHeight: 100 })
        .backgroundColor(this.c.surface)
        .borderRadius(20)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onChange((v: string) => { this.inputText = v; })

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

        this.InputBar()

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
