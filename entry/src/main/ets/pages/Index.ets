import { getHubClient } from '../api/HubClient';
import { getSSEClient, SSESubscription, SSEConnectionState } from '../api/SSEClient';
import { SessionSummary } from '../models/Types';
import { SyncEvent, SyncEventType } from '../models/SyncEvent';
import { ChatPageRouteParams } from './ChatPage';
import { SessionActionMenu } from '../components/SessionActionMenu';
import { paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';

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
  // message-* 高频事件不刷列表（后续在对话页处理 / 局部更新角标时间）。
  private onSSEEvent(event: SyncEvent): void {
    const t: string = event.type;
    if (t === SyncEventType.SESSION_ADDED
      || t === SyncEventType.SESSION_UPDATED
      || t === SyncEventType.SESSION_REMOVED
      || t === SyncEventType.SESSION_ENDED) {
      this.loadSessions();
    }
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

  // 过滤后的可见列表：空查询 → 全量。getter 在 build 中被读取，V2 细粒度观察追踪
  // sessions/searchQuery 的读取 → 任一变化自动重渲染（同 theme `c` getter / chatcube getFilteredSessions 模式）。
  get filteredSessions(): SessionSummary[] {
    const q: string = this.searchQuery.trim().toLowerCase();
    if (q === '') {
      return this.sessions;
    }
    const out: SessionSummary[] = [];
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessionMatches(this.sessions[i], q)) {
        out.push(this.sessions[i]);
      }
    }
    return out;
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
          .fontSize(18)
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
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.textPrimary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.formatTime(session.updatedAt))
            .fontSize(12)
            .fontColor(this.c.textTertiary)
        }
        .width('100%')

        Row() {
          Text(session.summaryText !== '' ? session.summaryText : (session.thinking ? '思考中…' : ' '))
            .fontSize(13)
            .fontColor(this.c.textSecondary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (session.pendingRequestsCount > 0) {
            Text(`${session.pendingRequestsCount}`)
              .fontSize(11)
              .fontColor(this.c.bubbleUserText)
              .backgroundColor(this.c.error)
              .borderRadius(10)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
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
      Text('📭').fontSize(48)
      Text('暂无会话').fontSize(16).fontColor(this.c.textSecondary)
      Text('在终端启动 hapi 后，会话会出现在这里').fontSize(13).fontColor(this.c.textTertiary)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  // 搜索无结果（与「无会话」空态区分；对照 web sessions.search.noResults「没有匹配的会话。」）
  @Builder
  private SearchEmptyState() {
    Column({ space: 8 }) {
      Text('🔍').fontSize(40)
      Text('没有匹配的会话。').fontSize(15).fontColor(this.c.textSecondary)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private ErrorState() {
    Column({ space: 12 }) {
      Text('加载失败').fontSize(16).fontColor(this.c.error)
      Text(this.errorMessage).fontSize(13).fontColor(this.c.textTertiary).textAlign(TextAlign.Center)
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
            Text('会话').fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.c.textPrimary)
            if (this.sseBadge() !== '') {
              Text(this.sseBadge()).fontSize(11).fontColor(this.c.textTertiary).margin({ left: 8 })
            }
          }
          .layoutWeight(1)

          // 设置入口
          Text('⚙')
            .fontSize(22)
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
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })
        }

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
          this.SearchEmptyState()
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
