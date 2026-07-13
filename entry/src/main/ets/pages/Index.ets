import { getHubClient } from '../api/HubClient';
import { getSSEClient, SSESubscription, SSEConnectionState } from '../api/SSEClient';
import { SessionSummary } from '../models/Types';
import { SyncEvent, SyncEventType } from '../models/SyncEvent';
import { ChatPageRouteParams } from './ChatPage';
import { SessionActionMenu } from '../components/SessionActionMenu';
import { ConnectionBanner } from '../components/ConnectionBanner';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { showToast } from '../utils/Toast';

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
    this.connectSSE();
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
        this.errorMessage = e instanceof Error ? e.message : '加载会话失败';
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
  //   machine-updated：无 machine UI 可消费（机器在 NewSessionPage 实时拉取），留 no-op hook。
  private onSSEEvent(event: SyncEvent): void {
    const t: string = event.type;
    if (t === SyncEventType.SESSION_ADDED
      || t === SyncEventType.SESSION_UPDATED
      || t === SyncEventType.SESSION_REMOVED
      || t === SyncEventType.SESSION_ENDED
      || t === SyncEventType.SCHEDULED_MATURED) {
      this.loadSessions();
    } else if (t === SyncEventType.TOAST) {
      this.showServerToast(event);
    }
  }

  // 服务端 Toast（data:{title,body,sessionId,url}）→ 全局提示。showToast 是窗口级，任何页在前都显形。
  private showServerToast(event: SyncEvent): void {
    const data = event.getObject('data');
    if (data === null) {
      return;
    }
    const titleVal = data['title'];
    const bodyVal = data['body'];
    const title: string = typeof titleVal === 'string' ? titleVal : '';
    const body: string = typeof bodyVal === 'string' ? bodyVal : '';
    const message: string = body !== '' ? `${title}：${body}` : title;
    if (message === '') {
      return;
    }
    showToast(message);
  }

  // 点击进入对话页（NavPathStack.pushPath，对照 chatcube openChatRoute）
  private openSession(session: SessionSummary): void {
    const params: ChatPageRouteParams = new ChatPageRouteParams();
    params.sessionId = session.id;
    params.title = session.title;
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

  // 筛选 Tab 文案与图标（按 tab+搜索词；filteredSessions===0 时用）
  private emptyMessage(): string {
    if (this.searchQuery.trim() !== '') { return '没有匹配的会话。'; }
    if (this.sessionFilter === 'active') { return '没有活跃会话。'; }
    if (this.sessionFilter === 'archived') { return '没有已归档会话。'; }
    return '没有匹配的会话。';
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
      this.FilterTab('全部', 'all', this.sessions.length)
      this.FilterTab('活跃', 'active', this.countByActive(true))
      this.FilterTab('已归档', 'archived', this.countByActive(false))
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
      return '刚刚';
    }
    if (min < 60) {
      return `${min}分钟前`;
    }
    const hr: number = Math.floor(min / 60);
    if (hr < 24) {
      return `${hr}小时前`;
    }
    const day: number = Math.floor(hr / 24);
    if (day < 7) {
      return `${day}天前`;
    }
    const d: Date = new Date(ts);
    return `${d.getMonth() + 1}-${d.getDate()}`;
  }

  private sseBadge(): string {
    if (this.sseState === 'open') {
      return '● 实时';
    }
    if (this.sseState === 'connecting' || this.sseState === 'reconnecting') {
      return '○ 连接中';
    }
    return '';
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
          Text(session.summaryText !== '' ? session.summaryText : (session.thinking ? '思考中…' : ' '))
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

  @Builder
  private EmptyState() {
    Column({ space: 10 }) {
      Text('📭').fontSize(fs(48))
      Text('暂无会话').fontSize(fs(16)).fontColor(this.c.textSecondary)
      Text('在终端启动 hapi 后，会话会出现在这里').fontSize(fs(13)).fontColor(this.c.textTertiary)
      Button('新建会话')
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
      Text('加载失败').fontSize(fs(16)).fontColor(this.c.error)
      Text(this.errorMessage).fontSize(fs(13)).fontColor(this.c.textTertiary).textAlign(TextAlign.Center)
      Button('重试')
        .backgroundColor(this.c.primary)
        .fontColor(this.c.bubbleUserText)
        .onClick(() => this.loadSessions())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Navigation(this.navStack) {
      Column() {
        // 自绘标题栏（含 SSE 实时状态 + 设置入口）
        Row() {
          Row() {
            Text('会话').fontSize(fs(22)).fontWeight(FontWeight.Bold).fontColor(this.c.textPrimary)
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
            Search({ value: this.searchQuery, placeholder: '搜索会话…' })
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
              ForEach(this.filteredSessions, (session: SessionSummary) => {
                ListItem() {
                  this.SessionItem(session)
                }
                .onClick(() => this.openSession(session))
              }, (session: SessionSummary) => session.id)
            }
            .width('100%')
            .height('100%')
            .divider({ strokeWidth: 0.5, color: this.c.border, startMargin: 72, endMargin: 16 })
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
  }
}
