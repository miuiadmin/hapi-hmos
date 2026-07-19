import { getHubClient } from '../api/HubClient';
import { getSSEClient, SSESubscription, SSEConnectionState } from '../api/SSEClient';
import { SessionSummary, Machine } from '../models/Types';
import { SyncEvent, SyncEventType } from '../models/SyncEvent';
import { ChatPageRouteParams } from './ChatPage';
import { NewSessionPageRouteParams } from './NewSessionPage';
import {
  UNKNOWN_MACHINE_ID,
  OTHER_DIRECTORY,
  MachineGroup,
  DirectoryGroup,
  RenderRow,
  groupSessionsByDirectory,
  flattenGroups,
  isGroupCollapsed,
  machineGroupHasActive,
  directoryGroupHasActive,
  directoryGroupKey
} from '../chat/SessionGrouping';
import { SessionActionMenu } from '../components/SessionActionMenu';
import { ConnectionBanner } from '../components/ConnectionBanner';
import { SyncingBanner } from '../components/SyncingBanner';
import { ServerToastOverlay } from '../components/ServerToastOverlay';
import { classifySessionAttention, AttentionKind, getSessionSeenService, SessionSeenService } from '../services/SessionAttention';
import { SessionPreviewLimitService, getSessionPreviewLimitState } from '../services/SessionPreviewLimitService';
import { getSessionListStatusModeState } from '../services/SessionListStatusModeService';
import { SyncStateService, getSyncState, SyncState } from '../services/SyncStateService';
import { ToastService } from '../services/ToastService';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { localizeToast } from '../chat/ToastLocalize';
import { t } from '../i18n/I18nService';

// 会话列表页（已登录首屏）
// UI 写法/样式对照 chatcube Index（Navigation + 列表 + 列表项 + 空态/加载态/错误态）
// 数据：HubClient.fetchSessions 拉 /api/sessions；SSEClient 收 session-* 事件实时刷新
// 导航：Navigation + NavPathStack（pushPath ChatPage），对照 chatcube，非 router
// 颜色经统一主题（theme/ThemeService）—— 读 getThemeState().isDark 取调色板，切换/跟随系统即时响应。

@Entry
@ComponentV2
struct Index {
  @Local sessions: SessionSummary[] = [];
  @Local isLoading: boolean = false;
  @Local errorMessage: string = '';
  @Local sseState: SSEConnectionState = 'idle';
  @Local searchQuery: string = '';              // 会话搜索查询（纯客户端过滤，对照 web SessionListSearch）
  @Local isRefreshing: boolean = false;          // 下拉刷新中（Refresh 容器 refreshing 双向绑定）
  @Local sessionFilter: 'all' | 'active' | 'archived' = 'all';   // 列表 Tab 筛选：archived = 非活跃（hapi 归档即 active=false）
  @Local machines: Machine[] = [];                                              // 机器列表（机器组头 label 用；MACHINE_UPDATED 刷新）
  @Local collapsedOverride: Map<string, boolean> = new Map<string, boolean>();  // 用户显式折叠/展开态（true=折叠）
  @Local expandedGroups: Set<string> = new Set<string>();   // 用户显式展开的目录组 key（超出预览行数时点「展开更多」登记；reassign 触发 V2）
  // @Local 持有同步态单例 → 作为 @Monitor('sync.resyncSeq') 的可观测根（前台返回 >30s beginSync → resyncSeq++ → reload）
  @Local sync: SyncState = getSyncState();

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  private navStack: NavPathStack = new NavPathStack();
  private loadSeq: number = 0;
  private sseListenerId: number = -1;

  // 会话长按菜单（重命名/归档/删除委托 SessionActionMenu 组件；本页只持有目标快照 + open 信号）
  @Local actionTarget: SessionSummary | null = null;   // 动作面板目标会话（长按时定）
  @Local actionMenuOpen: boolean = false;              // 动作面板显隐（组件 @Param open）

  aboutToAppear(): void {
    this.loadSessions();
    this.loadMachines();
    this.connectSSE();
  }

  // 拉机器列表（best-effort：失败静默，机器组头回退短 id）。
  //   分组渲染后机器组头需 displayName → 此处拉取；MACHINE_UPDATED 事件触发刷新。
  private async loadMachines(): Promise<void> {
    try {
      this.machines = await getHubClient().getMachines();
    } catch (_e) {
      /* 静默：组头回退 machineId 短标识 */
    }
  }

  // 拉取会话列表（sessionLoadSeq 防并发竞态，对照 chatcube loadSessions）
  private async loadSessions(): Promise<void> {
    this.loadSeq = this.loadSeq + 1;
    const seq: number = this.loadSeq;
    if (this.sessions.length === 0) {
      this.isLoading = true;
    }
    this.errorMessage = '';
    try {
      const list = await getHubClient().fetchSessions();
      if (seq === this.loadSeq) {
        this.sessions = list;
      }
    } catch (e) {
      if (seq === this.loadSeq) {
        this.errorMessage = e instanceof Error ? e.message : t('sessions.loadFailed');
      }
    } finally {
      if (seq === this.loadSeq) {
        this.isLoading = false;
      }
    }
  }

  // 下拉刷新：复用 loadSessions，完成后回写 isRefreshing=false 停 Refresh 指示器。
  //   Refresh 的 refreshing 经 !! 双向绑定：下拉触发时组件自置 true + onRefreshing 回调；
  //   这里只负责拉数据 + 收尾置 false（finally 兜底，失败也停指示器）。
  private async refreshSessions(): Promise<void> {
    try {
      await this.loadSessions();
    } finally {
      this.isRefreshing = false;
    }
  }

  // 连接 SSE（全局订阅，不带 sessionId，收所有可见会话事件），注册本页监听者
  private connectSSE(): void {
    const sse = getSSEClient();
    this.sseListenerId = sse.addListener({
      onEvent: (event: SyncEvent) => { this.onSSEEvent(event); },
      onStateChange: (state: SSEConnectionState) => { this.sseState = state; }
    });
    sse.connect(new SSESubscription());
  }

  // SSE 事件：会话结构性变更 → 重新拉列表（低频）。
  // message-* 高频事件不刷列表（在对话页处理 / 局部更新角标时间）。
  //   scheduled-matured：定时消息成熟 → 会话摘要/updatedAt 变，并入重拉。
  //   toast：服务端推 Toast（后台通知；仅 Index 处理，root 恒在栈避免与对话页双监听者重复弹）。
  //   machine-updated：机器列表变（新增/掉线/displayName 变）→ 拉机器刷新组头 label。
  private onSSEEvent(event: SyncEvent): void {
    const evtType: string = event.type;
    if (evtType === SyncEventType.SESSION_ADDED
      || evtType === SyncEventType.SESSION_UPDATED
      || evtType === SyncEventType.SESSION_REMOVED
      || evtType === SyncEventType.SESSION_ENDED
      || evtType === SyncEventType.SCHEDULED_MATURED) {
      this.loadSessions();
    } else if (evtType === SyncEventType.MACHINE_UPDATED) {
      this.loadMachines();
    } else if (evtType === SyncEventType.TOAST) {
      this.showServerToast(event);
    }
  }

  // 服务端 Toast（data:{title,body,sessionId,url}）→ 本地化 + 悬浮卡（ServerToastOverlay，可点击跳会话）。
  //   对照上游 App.tsx translateIncomingToast：classify/parseReadyBody/localizeToast 在 chat/ToastLocalize（纯层）。
  private showServerToast(event: SyncEvent): void {
    const data = event.getObject('data');
    if (data === null) {
      return;
    }
    const titleVal = data['title'];
    const bodyVal = data['body'];
    const sessionVal = data['sessionId'];
    const title: string = typeof titleVal === 'string' ? titleVal : '';
    const body: string = typeof bodyVal === 'string' ? bodyVal : '';
    const sessionId: string = typeof sessionVal === 'string' ? sessionVal : '';
    if (title === '' && body === '') {
      return;
    }
    const loc = localizeToast(title, body);
    ToastService.show(loc.title, loc.body, sessionId);
  }

  // 点击进入对话页（NavPathStack.pushPath，对照 chatcube openChatRoute）
  private openSession(session: SessionSummary): void {
    const params: ChatPageRouteParams = new ChatPageRouteParams();
    params.sessionId = session.id;
    params.title = session.title;
    this.navStack.pushPath({ name: 'ChatPage', param: params });
  }

  // 点击 toast 跳会话（仅 sessionId；title 留空由 ChatPage 自拉）。sessionId 缺→不跳。
  private openSessionById(sessionId: string): void {
    if (sessionId === '') {
      return;
    }
    const params: ChatPageRouteParams = new ChatPageRouteParams();
    params.sessionId = sessionId;
    params.title = '';
    this.navStack.pushPath({ name: 'ChatPage', param: params });
  }

  // 打开设置页（NavPathStack.pushPath）
  private openSettings(): void {
    this.navStack.pushPath({ name: 'SettingsPage' });
  }

  // 打开新建会话页（spawn 流程，对照上游列表头「+」→ /sessions/new）
  private openNewSession(): void {
    this.navStack.pushPath({ name: 'NewSessionPage' });
  }

  // 打开新建会话页并预填 machine + directory（会话列表「本目录新建」+ 按钮，对照上游 onNewSessionInDirectory）。
  private openNewSessionInDirectory(machineId: string, directory: string): void {
    const params: NewSessionPageRouteParams = new NewSessionPageRouteParams();
    params.machineId = machineId;
    params.directory = directory;
    this.navStack.pushPath({ name: 'NewSessionPage', param: params });
  }

  // 长按会话 → 记目标快照 + 开动作面板（重命名/归档/删除逻辑在 SessionActionMenu 组件内）
  private openActionMenu(session: SessionSummary): void {
    this.actionTarget = session;
    this.actionMenuOpen = true;
  }

  // 会话搜索：纯客户端小写子串匹配（对照 web sessionMatchesQuery）。
  // 命中字段 = title(已含 name→path末段→id 三级回退) + id + metadata.path + metadata.name + summaryText。
  // 上游额外匹配 worktree.basePath/flavor/machineLabel，本项目未存这些字段 → 取实用子集。
  private sessionMatches(s: SessionSummary, q: string): boolean {
    const path: string = s.metadata !== null ? s.metadata.path : '';
    const name: string = s.metadata !== null ? s.metadata.name : '';
    const hay: string = `${s.title}\n${s.id}\n${path}\n${name}\n${s.summaryText}`.toLowerCase();
    return hay.includes(q);
  }

  // 过滤后的可见列表：先按 Tab 筛选（archived=非活跃），再按搜索词过滤。
  // getter 在 build 中被读取，V2 细粒度观察追踪 sessions/sessionFilter/searchQuery → 任一变化自动重渲染
  // （同 theme `c` getter / chatcube getFilteredSessions 模式）。
  get filteredSessions(): SessionSummary[] {
    // 1. Tab 筛选
    let scoped: SessionSummary[] = this.sessions;
    if (this.sessionFilter === 'active') {
      const a: SessionSummary[] = [];
      for (let i = 0; i < this.sessions.length; i++) {
        if (this.sessions[i].active) { a.push(this.sessions[i]); }
      }
      scoped = a;
    } else if (this.sessionFilter === 'archived') {
      const a: SessionSummary[] = [];
      for (let i = 0; i < this.sessions.length; i++) {
        if (!this.sessions[i].active) { a.push(this.sessions[i]); }
      }
      scoped = a;
    }
    // 2. 搜索过滤
    const q: string = this.searchQuery.trim().toLowerCase();
    if (q === '') { return scoped; }
    const out: SessionSummary[] = [];
    for (let i = 0; i < scoped.length; i++) {
      if (this.sessionMatches(scoped[i], q)) { out.push(scoped[i]); }
    }
    return out;
  }

  // 三级分组行：filteredSessions → 机器→目录分组 → 按折叠态展平为 RenderRow[]（单层 ForEach 渲染）。
  //   读 @Local sessions/sessionFilter/searchQuery/collapsedOverride → 任一变化 V2 自动重渲染
  //   （同 filteredSessions getter / theme `c` getter 模式）。
  get sessionRows(): RenderRow[] {
    // 读 @Trace limit（SessionPreviewLimitService 单例）建立 V2 刷新依赖（设置页改 limit 即重算），同 theme `c` getter 模式。
    return flattenGroups(
      groupSessionsByDirectory(this.filteredSessions),
      this.isSearching(),
      this.collapsedOverride,
      getSessionPreviewLimitState().limit,
      this.expandedGroups
    );
  }

  // 前台重同步触发（EntryAbility.onForeground beginSync → resyncSeq++）：重拉列表 + 结束同步（关横幅）。
  @Monitor('sync.resyncSeq')
  onResync(monitor: IMonitor): void {
    this.loadSessions().then((): void => { SyncStateService.endSync(); });
  }

  // 「展开更多」：登记目录组 key 到 expandedGroups 并 reassign 触发 V2 重渲染（flattenGroups 见已展开则全显）。
  private expandGroup(groupKey: string): void {
    const next: Set<string> = new Set<string>();
    this.expandedGroups.forEach((k: string) => { next.add(k); });
    next.add(groupKey);
    this.expandedGroups = next;
  }

  private isSearching(): boolean { return this.searchQuery.trim() !== ''; }

  // 机器组头 label：displayName（命中 machines）→ 短 id（mg.label）→ 原 id → unknown i18n。
  private resolveMachineLabel(mg: MachineGroup): string {
    if (mg.machineId === UNKNOWN_MACHINE_ID) { return t('sessions.group.unknownMachine'); }
    for (let i = 0; i < this.machines.length; i++) {
      if (this.machines[i].id === mg.machineId) {
        const name: string = this.machines[i].displayName;
        return name !== '' ? name : mg.machineId;
      }
    }
    return mg.label !== '' ? mg.label : mg.machineId;
  }

  // 目录组头 label：末两段名（displayName）→ 全路径 → Other i18n。
  private resolveDirectoryLabel(dg: DirectoryGroup): string {
    if (dg.directory === OTHER_DIRECTORY) { return t('sessions.group.other'); }
    return dg.displayName !== '' ? dg.displayName : dg.directory;
  }

  // 「本目录新建」+ 按钮可见：仅真实目录 + 真实机器（Other / unknown 无 spawn 意义，对照上游 canStartInGroupDirectory）。
  private canStartInDirectory(dg: DirectoryGroup): boolean {
    return dg.directory !== OTHER_DIRECTORY && dg.machineId !== UNKNOWN_MACHINE_ID;
  }

  private machineCollapsed(mg: MachineGroup): boolean {
    return isGroupCollapsed(mg.machineId, machineGroupHasActive(mg), this.isSearching(), this.collapsedOverride);
  }
  private directoryCollapsed(dg: DirectoryGroup): boolean {
    return isGroupCollapsed(directoryGroupKey(dg), directoryGroupHasActive(dg), this.isSearching(), this.collapsedOverride);
  }

  // 切换折叠态：reassign 新 Map 触发 @Local 重渲染（V2 观察 @Local 重赋值，不观察 Map 内部变动）。
  private toggleMachine(mg: MachineGroup): void {
    this.toggleKey(mg.machineId, machineGroupHasActive(mg));
  }
  private toggleDirectory(dg: DirectoryGroup): void {
    this.toggleKey(directoryGroupKey(dg), directoryGroupHasActive(dg));
  }
  private toggleKey(key: string, hasActive: boolean): void {
    const cur: boolean = isGroupCollapsed(key, hasActive, this.isSearching(), this.collapsedOverride);
    const next: Map<string, boolean> = new Map<string, boolean>();
    this.collapsedOverride.forEach((v: boolean, k: string) => { next.set(k, v); });
    next.set(key, !cur);
    this.collapsedOverride = next;
  }

  // 筛选 Tab 文案与图标（按 tab+搜索词；filteredSessions===0 时用）
  private emptyMessage(): string {
    if (this.searchQuery.trim() !== '') { return t('sessions.search.noResults'); }
    if (this.sessionFilter === 'active') { return t('sessions.empty.active'); }
    if (this.sessionFilter === 'archived') { return t('sessions.empty.archived'); }
    return t('sessions.search.noResults');
  }
  private emptyIcon(): string {
    if (this.searchQuery.trim() !== '') { return '🔍'; }
    if (this.sessionFilter === 'active') { return '💬'; }
    if (this.sessionFilter === 'archived') { return '📦'; }
    return '🔍';
  }
  private countByActive(active: boolean): number {
    let n: number = 0;
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].active === active) { n = n + 1; }
    }
    return n;
  }

  // 列表筛选 Tab（全部/活跃/已归档，附计数；archived=非活跃）
  @Builder
  private FilterTab(label: string, mode: 'all' | 'active' | 'archived', count: number) {
    Text(`${label} ${count}`)
      .fontSize(fs(13))
      .fontWeight(this.sessionFilter === mode ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.sessionFilter === mode ? this.c.primary : this.c.textTertiary)
      .decoration({ type: this.sessionFilter === mode ? TextDecorationType.Underline : TextDecorationType.None })
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .margin({ right: 8 })
      .onClick(() => { this.sessionFilter = mode; })
  }
  @Builder
  private FilterTabs() {
    Row() {
      this.FilterTab(t('sessions.filter.all'), 'all', this.sessions.length)
      this.FilterTab(t('sessions.filter.active'), 'active', this.countByActive(true))
      this.FilterTab(t('sessions.filter.archived'), 'archived', this.countByActive(false))
    }
    .width('100%')
    .margin({ top: 8 })
  }

  // 相对时间（对照 chatcube RelativeTimeText 分档）
  private formatTime(ts: number): string {
    if (ts === 0) {
      return '';
    }
    const diff: number = Math.max(0, Date.now() - ts);
    const min: number = Math.floor(diff / 60000);
    if (min < 1) {
      return t('sessions.time.justNow');
    }
    if (min < 60) {
      return t('sessions.time.minutesAgo', { n: min });
    }
    const hr: number = Math.floor(min / 60);
    if (hr < 24) {
      return t('sessions.time.hoursAgo', { n: hr });
    }
    const day: number = Math.floor(hr / 24);
    if (day < 7) {
      return t('sessions.time.daysAgo', { n: day });
    }
    const d: Date = new Date(ts);
    return `${d.getMonth() + 1}-${d.getDate()}`;
  }

  private sseBadge(): string {
    if (this.sseState === 'open') {
      return t('sessions.sse.live');
    }
    if (this.sseState === 'connecting' || this.sseState === 'reconnecting') {
      return t('sessions.sse.connecting');
    }
    return '';
  }

  // 会话注意力分级（对照 web lib/sessionAttention）：thinking 不打扰；返回左侧色点类型。
  //   detailed 模式才显 attention 指示器（对照上游 showDetailedStatus ? classify : null）；standard 隐藏色点。
  private attentionFor(session: SessionSummary): AttentionKind | null {
    // 读 @Trace mode 建立 V2 刷新依赖（设置页切 detailed/standard 即重渲染），同 theme `c` getter 模式
    if (getSessionListStatusModeState().mode !== 'detailed') { return null; }
    // 移动端栈式导航：列表可见时用户不在任何会话内 → selected 恒 false（thinking 由 classify 内部抑制）。
    const seen: SessionSeenService = getSessionSeenService();
    // 读 @Trace revision 建立 V2 刷新依赖：ChatPage markSeen 自增 → 列表重渲染 → 重读 lastSeen 拿最新时间戳。
    const _observeRevision: number = seen.revision;
    return classifySessionAttention(session, false, seen.lastSeen(session.id));
  }

  // 注意力色点颜色：permission→琥珀（需授权）；input/background/unread→主色（蓝）。
  private attentionDotColor(kind: AttentionKind): string {
    return kind === 'permission' ? this.c.warning : this.c.primary;
  }

  // 列表项（对照 chatcube SessionCard：头像 | 标题+时间 / 摘要+角标）
  @Builder
  private SessionItem(session: SessionSummary) {
    Row({ space: 12 }) {
      // 头像方块（主题色 + 首字）
      Column() {
        Text(session.title.length > 0 ? session.title.substring(0, 1) : '#')
          .fontSize(fs(18))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.c.bubbleUserText)
      }
      .width(44)
      .height(44)
      .borderRadius(12)
      .backgroundColor(session.active ? this.c.primary : this.c.textTertiary)
      .justifyContent(FlexAlign.Center)

      // 中段：标题 + 时间 / 摘要 + 角标
      Column({ space: 6 }) {
        Row() {
          // 注意力色点（对照 web SessionAttentionIndicator：permission→琥珀/其余→主色；thinking 不显）
          if (this.attentionFor(session) !== null) {
            // 用 Column+尺寸+borderRadius 画圆点（项目无 Circle 先例，沿用既有 badge 样式范式）
            Column()
              .width(7)
              .height(7)
              .borderRadius(4)
              .backgroundColor(this.attentionDotColor(this.attentionFor(session) as AttentionKind))
              .margin({ right: 6 })
          }
          Text(session.title)
            .fontSize(fs(15))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.textPrimary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.formatTime(session.updatedAt))
            .fontSize(fs(12))
            .fontColor(this.c.textTertiary)
        }
        .width('100%')

        Row() {
          Text(session.summaryText !== '' ? session.summaryText : (session.thinking ? t('sessions.thinking') : ' '))
            .fontSize(fs(13))
            .fontColor(this.c.textSecondary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          // todo 进度（对照上游 SessionList getTodoProgress：有未完成 todo 时显 💡 done/total；
          //   无 todo 或全部完成则隐藏——todoTotal=0 或 done===total 都不显，仅在进行中提示）
          if (session.todoTotal > 0 && session.todoCompleted !== session.todoTotal) {
            Row({ space: 3 }) {
              Text('💡').fontSize(fs(10))
              Text(`${session.todoCompleted}/${session.todoTotal}`).fontSize(fs(11))
            }
            .fontColor(this.c.textTertiary)
            .margin({ right: 6 })
          }
          if (session.pendingRequestsCount > 0) {
            Text(`${session.pendingRequestsCount}`)
              .fontSize(fs(11))
              .fontColor(this.c.bubbleUserText)
              .backgroundColor(this.c.error)
              .borderRadius(10)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          }
          // 后台任务角标（backgroundTaskCount>0；agent 后台跑的待办任务数，中性样式区别于待审批红角标）
          if (session.backgroundTaskCount > 0) {
            Row({ space: 3 }) {
              Text('⚙').fontSize(fs(10))
              Text(`${session.backgroundTaskCount}`).fontSize(fs(11))
            }
            .fontColor(this.c.textSecondary)
            .backgroundColor(this.c.surface)
            .borderRadius(8)
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .margin({ left: 6 })
          }
          // 定时消息角标（futureScheduledMessageCount>0；待触发的排队定时消息数，对照上游 SessionList ⏰）
          if (session.futureScheduledMessageCount > 0) {
            Row({ space: 3 }) {
              Text('⏰').fontSize(fs(10))
              Text(`${session.futureScheduledMessageCount}`).fontSize(fs(11))
            }
            .fontColor(this.c.textSecondary)
            .backgroundColor(this.c.surface)
            .borderRadius(8)
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .margin({ left: 6 })
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .opacity(session.active ? 1 : 0.5)
    .gesture(LongPressGesture({ duration: 500, repeat: false })
      .onAction(() => { this.openActionMenu(session); }))
  }

  // 「展开更多 (剩 N)」行（目录组会话数超出预览上限时显示；点击登记 groupKey 全显该组）。
  @Builder
  private ShowMoreRow(row: RenderRow) {
    Row() {
      Text(t('sessions.showMore', { n: row.remaining }))
        .fontSize(fs(12))
        .fontColor(this.c.primary)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .justifyContent(FlexAlign.Center)
  }

  // 机器组头行（▼/▶ + 💻 + label + 总数；点击折叠/展开，对照上游 SessionList 机器分组头）。
  @Builder
  private MachineHeader(mg: MachineGroup) {
    Row({ space: 6 }) {
      Text(this.machineCollapsed(mg) ? '▶' : '▼')
        .fontSize(fs(11))
        .fontColor(this.c.textTertiary)
      Text('💻').fontSize(fs(13))
      Text(this.resolveMachineLabel(mg))
        .fontSize(fs(13))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.textSecondary)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(`${mg.totalSessions}`)
        .fontSize(fs(12))
        .fontColor(this.c.textTertiary)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 6 })
    .alignItems(VerticalAlign.Center)
  }

  // 目录组头行（▼/▶ + 📁 + label + 本组会话数 +「本目录新建」+；点击折叠/展开，对照上游 directory 分组头）。
  //   + 按钮 hitTestBehavior(Block)：拦截点透传，避免同时触发父行折叠 toggle（对照上游 onNewSessionInDirectory）。
  @Builder
  private DirectoryHeader(dg: DirectoryGroup) {
    Row({ space: 6 }) {
      Text(this.directoryCollapsed(dg) ? '▶' : '▼')
        .fontSize(fs(11))
        .fontColor(this.c.textTertiary)
      Text('📁').fontSize(fs(13))
      Text(this.resolveDirectoryLabel(dg))
        .fontSize(fs(13))
        .fontColor(this.c.textSecondary)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(`${dg.sessions.length}`)
        .fontSize(fs(12))
        .fontColor(this.c.textTertiary)
      if (this.canStartInDirectory(dg)) {
        Text('+')
          .fontSize(fs(18))
          .fontColor(this.c.primary)
          .width(28)
          .height(28)
          .textAlign(TextAlign.Center)
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => this.openNewSessionInDirectory(dg.machineId, dg.directory))
      }
    }
    .width('100%')
    .padding({ left: 40, right: 16, top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private EmptyState() {
    Column({ space: 10 }) {
      Text('📭').fontSize(fs(48))
      Text(t('sessions.empty.title')).fontSize(fs(16)).fontColor(this.c.textSecondary)
      Text(t('sessions.empty.hint')).fontSize(fs(13)).fontColor(this.c.textTertiary)
      Button(t('sessions.new'))
        .margin({ top: 12 })
        .backgroundColor(this.c.primary)
        .fontColor(this.c.bubbleUserText)
        .borderRadius(10)
        .onClick(() => this.openNewSession())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  // 列表筛选/搜索无结果空态（icon + message 由 emptyIcon/emptyMessage 按 tab+搜索词给出）
  @Builder
  private SearchEmptyState(icon: string, message: string) {
    Column({ space: 8 }) {
      Text(icon).fontSize(fs(40))
      Text(message).fontSize(fs(15)).fontColor(this.c.textSecondary)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private ErrorState() {
    Column({ space: 12 }) {
      Text(t('sessions.errorTitle')).fontSize(fs(16)).fontColor(this.c.error)
      Text(this.errorMessage).fontSize(fs(13)).fontColor(this.c.textTertiary).textAlign(TextAlign.Center)
      Button(t('common.retry'))
        .backgroundColor(this.c.primary)
        .fontColor(this.c.bubbleUserText)
        .onClick(() => this.loadSessions())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    // Stack 包 Navigation：ServerToastOverlay 悬浮于所有页面之上（TopStart 对齐），跨页可见。
    Stack() {
      Navigation(this.navStack) {
        Column() {
          // 自绘标题栏（含 SSE 实时状态 + 设置入口）
          Row() {
            Row() {
              Text(t('sessions.title')).fontSize(fs(22)).fontWeight(FontWeight.Bold).fontColor(this.c.textPrimary)
              if (this.sseBadge() !== '') {
                Text(this.sseBadge()).fontSize(fs(11)).fontColor(this.c.textTertiary).margin({ left: 8 })
              }
            }
            .layoutWeight(1)

            // 新建会话入口
            Text('+')
              .fontSize(fs(26))
              .fontColor(this.c.textSecondary)
              .width(40)
              .height(40)
              .textAlign(TextAlign.Center)
              .onClick(() => this.openNewSession())

            // 设置入口
            Text('⚙')
              .fontSize(fs(22))
              .fontColor(this.c.textSecondary)
              .width(40)
              .height(40)
              .textAlign(TextAlign.Center)
              .onClick(() => this.openSettings())
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })

          // 搜索框（仅 sessions 非空时显示；纯客户端过滤，对照 web SessionListSearch / chatcube Search 组件）
          if (this.sessions.length > 0) {
            Column() {
              Search({ value: this.searchQuery, placeholder: t('sessions.search.placeholder') })
                .height(40)
                .backgroundColor(this.c.surface)
                .placeholderColor(this.c.textTertiary)
                .onChange((value: string) => { this.searchQuery = value; })
              this.FilterTabs()
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 8 })
          }

          // 连接状态横幅（SSE 重连/断开时显形；常态 Visibility.None 不占位）
          ConnectionBanner()
          // 前台重同步横幅（切后台 >30s 回前台 beginSync；resyncSeq++ 触发 loadSessions，完成后 endSync）
          SyncingBanner()

          if (this.isLoading) {
            Column() {
              LoadingProgress().width(40).height(40).color(this.c.primary)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.errorMessage !== '' && this.sessions.length === 0) {
            this.ErrorState()
          } else if (this.sessions.length === 0) {
            this.EmptyState()
          } else if (this.filteredSessions.length === 0) {
            this.SearchEmptyState(this.emptyIcon(), this.emptyMessage())
          } else {
            // 下拉刷新（Refresh 包 List；refreshing !! 双向绑定 + onRefreshing 触发拉取）
            Refresh({ refreshing: this.isRefreshing!! }) {
              List({ space: 0 }) {
                ForEach(this.sessionRows, (row: RenderRow) => {
                  ListItem() {
                    if (row.kind === 'machine') {
                      this.MachineHeader(row.machineGroup as MachineGroup)
                    } else if (row.kind === 'directory') {
                      this.DirectoryHeader(row.directoryGroup as DirectoryGroup)
                    } else if (row.kind === 'show-more') {
                      this.ShowMoreRow(row)
                    } else {
                      this.SessionItem(row.session as SessionSummary)
                    }
                  }
                  .onClick(() => {
                    if (row.kind === 'machine') {
                      this.toggleMachine(row.machineGroup as MachineGroup);
                    } else if (row.kind === 'directory') {
                      this.toggleDirectory(row.directoryGroup as DirectoryGroup);
                    } else if (row.kind === 'show-more') {
                      this.expandGroup(row.groupKey);
                    } else {
                      this.openSession(row.session as SessionSummary);
                    }
                  })
                }, (row: RenderRow) => row.key)
              }
              .width('100%')
              .height('100%')
              // 不用 List 级 divider：分组头与会话项混排时分隔线会切到头行底，观感凌乱；
              //   会话项靠自身 padding 留白，组头靠缩进 + 字重区分（对照上游 SessionList 分组无全局分隔线）。
              .edgeEffect(EdgeEffect.Spring)
            }
            .width('100%')
            .layoutWeight(1)
            .onRefreshing(() => { this.refreshSessions(); })
          }

          SessionActionMenu({
            sessionId: this.actionTarget !== null ? this.actionTarget.id : '',
            title: this.actionTarget !== null ? this.actionTarget.title : '',
            active: this.actionTarget !== null ? this.actionTarget.active : true,
            open: this.actionMenuOpen,
            onClose: () => { this.actionMenuOpen = false; },
            onRenamed: (_name: string) => { this.loadSessions(); },
            onArchived: () => { this.loadSessions(); },
            onDeleted: () => { this.loadSessions(); }
          })
        }
        .width('100%')
        .height('100%')
      }
      .hideTitleBar(true)
      .mode(NavigationMode.Stack)

      // 服务端 toast 悬浮卡（current 非空才显形；空态 Visibility.None 不占位、不拦截点击）
      ServerToastOverlay({
        onTap: (sid: string): void => { this.openSessionById(sid); }
      })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
  }
}
