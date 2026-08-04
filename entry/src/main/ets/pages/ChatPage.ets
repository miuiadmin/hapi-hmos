import { getHubClient, ApproveOptions } from '../api/HubClient';
import { getSSEClient } from '../api/SSEClient';
import { ChatMessage, MessageStatus, parseMessage, mergeMessage, cloneMessage, UsageData, latestVisibleUsage, getContextBudgetTokens, formatTokenCount, sortQueuedMessages, formatScheduledIn } from '../models/Message';
import { SyncEvent, SyncEventType } from '../models/SyncEvent';
import { MarkdownText } from '../components/MarkdownText';
import { ToolCard } from '../components/ToolCard';
import { ToolGroupCard } from '../components/ToolGroupCard';
import { ReasoningBubble } from '../components/ReasoningBubble';
import { GeneratedImageCard } from '../components/GeneratedImageCard';
import { ImagePreviewSheet } from '../components/ImagePreviewSheet';
import { CliOutputCard } from '../components/CliOutputCard';
import { CodexReviewCard } from '../components/CodexReviewCard';
import { TeamPanel } from '../components/TeamPanel';
import { TodoPanel } from '../components/TodoPanel';
import { QueuedMessagesBar } from '../components/QueuedMessagesBar';
import { ConnectionBanner } from '../components/ConnectionBanner';
import { SyncingBanner } from '../components/SyncingBanner';
import { ComposerToolbar } from '../components/ComposerToolbar';
import { AttachmentPickerPanel } from '../components/AttachmentPickerPanel';
import { SyncStateService, getSyncState, SyncState } from '../services/SyncStateService';
import { DateDivider } from '../components/DateDivider';
import { ChatBlock, ChatToolCall, ToolPermission } from '../chat/ChatBlock';
import { reduceChatBlocks } from '../chat/Reducer';
import { buildVisibleChatBlocks } from '../chat/ToolGroups';
import { ChatBlockDataSource } from '../chat/ChatBlockDataSource';
import { getInputStrAny } from '../chat/ToolInputUtils';
import { ToolActionState } from '../chat/ToolActionState';
import { buildConversationOutline, ConversationOutlineItem } from '../chat/Outline';
import { blockMatchesQuery } from '../chat/ChatSearch';
import { buildMessageMetadataLabels } from '../chat/MessageMetadata';
import { SlashCommand, slashCommandSuggestions, getBuiltinSlashCommands, mergeSlashCommands, serverCommandsToSlash } from '../chat/SlashCommands';
import { skillSuggestions, loadRecentSkills, markSkillUsed } from '../chat/Skills';
import { findActiveWord, applySuggestion } from '../chat/ActiveWord';
import { getLatestThreadGoal } from '../chat/ThreadGoal';
import { getEventPresentation, EventPresentation } from '../chat/EventPresentation';
import { eventGlyph } from '../components/IconGlyphs';
import { extractLeadingDirectives, formatDirectiveLabel } from '../chat/UserDirectives';
import { SlashMenu } from '../components/SlashMenu';
import { MentionMenu } from '../components/MentionMenu';
import { SkillsMenu } from '../components/SkillsMenu';
import { getSessionSeenService } from '../services/SessionAttention';
import { SessionConfigOverlay } from '../components/SessionConfigOverlay';
import { OutlinePanel } from '../components/OutlinePanel';
import { FilesRouteParams } from './FilesPage';
import { FileViewerRouteParams } from './FileViewerPage';
import { TerminalRouteParams } from './TerminalPage';
import { VoiceRouteParams } from './VoicePage';
import { AgentState, parseAgentState } from '../chat/AgentState';
import { Session, TeamState, parseTeamState, TodoItem, parseTodoList, FileSearchItem, AttachmentMetadata, SkillItem, agentDisplayName, modelDisplayName, ThreadGoal } from '../models/Types';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { shouldShowDateDivider, formatClock, formatDateDivider } from '../utils/DateFormatUtils';
import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { getShareService } from '../services/ShareService';
import { getPreferencesService } from '../services/PreferencesService';
import { getChatSurfaceColorsState } from '../services/ChatSurfaceColorsService';
import { HapticService } from '../services/HapticService';
import { getGeneratedImageCache } from '../services/GeneratedImageCache';
import { flavorLabel, flavorColorHex } from '../chat/AgentFlavor';
import { isImageMimeType, formatFileSize } from '../chat/AttachmentFormat';
import { PreferenceKeys } from '../config/Keys';
import { PickedFile } from '../services/FilePicker';
import { showToast } from '../utils/Toast';
import { t, kv, kv2, kv4 } from '../i18n/I18nService';

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

function errMsg(e: Object, fallback: string): string {
  return e instanceof Error ? e.message : fallback;
}

@ComponentV2
struct ChatPage {
  @Param routeParamsSeed: ChatPageRouteParams | null = null;

  @Local messages: ChatMessage[] = [];
  @Local blocks: ChatBlock[] = [];            // 由 messages+agentState 派生的渲染单元（reducer 产出）
  @Local toolActionStates: Record<string, ToolActionState> = {} as Record<string, ToolActionState>;  // 审批态（上提自 ToolCard，按 block.id 索引；V2 整体替换触发刷新）
  @Local detailOpenSigs: Record<string, string> = {} as Record<string, string>;  // tool 详情 sheet 展开态：key=block.id、value=展开瞬间冻结的 childSig（存在=开；冻结→blockSignature 不变→父卡不刷新→sheet/滚动稳定无闪烁）
  @Local inputText: string = '';
  @Local enterToSend: boolean = false;     // 回车发送（设置开关，默认关；关时 Enter=换行多行输入）
  @Local isLoading: boolean = false;
  @Local loadError: string = '';
  @Local isThinking: boolean = false;          // agent 生成中（session-updated.thinking）
  @Local isAborting: boolean = false;          // 停止生成请求进行中（防重入 + abort 按钮 spinner）
  @Local isSending: boolean = false;           // 发送请求进行中
  @Local sessionId: string = '';
  @Local agentState: AgentState | null = null; // 会话权限态（pending 请求队列等），SESSION_UPDATED 实时更新
  @Local nowTick: number = 0;                   // running 卡 elapsed 实时刷新驱动值（ticker 每秒 +1，仅 running 卡收到非 0）
  @Local hasMoreMessages: boolean = false;       // 还有更旧历史可加载（取自响应 page.hasMore）
  @Local isLoadingOlder: boolean = false;        // 加载更旧中（防抖 + 顶部指示器）
  // @Local 持有同步态单例 → 作为 @Monitor('sync.resyncSeq') 的可观测根（前台返回 >30s beginSync → resyncSeq++ → reload）
  @Local sync: SyncState = getSyncState();

  // 会话生命周期（⋯ 下拉：重命名/归档/删除 + 文件/终端/语音/导出/大纲/配置；ChatPage 自洽，不再依赖 SessionActionMenu 组件）
  @Local sessionTitle: string = '';              // 标题栏显示标题（aboutToAppear 取种子，重命名/SSE 更新）
  @Local isActive: boolean = true;               // 会话活跃态（归档/删除二选一：active→归档，否则→删除）
  @Local teamState: TeamState | null = null;     // 会话内多 agent 团队态（agent 自治上报；非 null 时消息列表上方渲染 TeamPanel）
  @Local todos: TodoItem[] = [];                 // 会话内待办清单（agent TodoWrite 上报；非空时消息列表上方渲染 TodoPanel）
  @Local model: string = '';                     // 会话 model（ContextStatusBar 算预算上限用；首屏/SSE 播种）
  @Local flavor: string = '';                    // 会话 flavor（claude/codex/…；getContextBudgetTokens 门控 + 配置 overlay 门控）
  @Local worktreeBranch: string = '';            // 会话 worktree git 分支（metadata.worktree.branch；标题副标题显示）
  @Local effort: string = '';                    // claude 努力度（/effort；首屏/SSE 播种；SessionConfigOverlay 用）
  @Local modelReasoningEffort: string = '';      // codex/opencode 推理努力（/model-reasoning-effort；首屏/SSE 播种）
  @Local permissionMode: string = '';            // 权限模式（/permission-mode；首屏/SSE 播种）
  @Local collaborationMode: string = '';         // codex 协作模式（/collaboration-mode；首屏/SSE 播种）
  @Local configSheetOpen: boolean = false;       // 会话配置 overlay 显隐（模型/权限/effort 即时改；⋯ 下拉「配置」开）
  @Local outlineOpen: boolean = false;           // 对话大纲抽屉显隐（📋 用户提问列表，tap 跳转）
  @Local outlineItems: ConversationOutlineItem[] = [];  // 大纲项（recomputeBlocks 随 blocks 重算）
  @Local entryLastSeenAt: number = 0;            // 进入会话时的「上次已看」时间戳（markSeen 前捕获；滚到首条未读 + 未读分隔依据）
  @Local newMessagesCount: number = 0;           // 滚在上方时累计的新消息数（>0 显「↓N条新消息」浮标）
  @Local expandedMeta: Set<string> = new Set<string>(); // 展开元数据脚注的 ChatBlock id（agent-text；reassign 触发 V2）

  // 消息长按菜单（复制 / 重发[仅失败] / 分享）——底部动作 sheet，复用 SessionActionMenu 的 bindSheet 模式
  @Local messageMenuBlock: ChatBlock | null = null;   // 长按目标块（复制/重发/分享读其 text/userStatus）
  @Local messageMenuOpen: boolean = false;            // 动作 sheet 显隐
  // 重命名（⋯ 菜单「重命名」开；逻辑镜像 SessionActionMenu，ChatPage 自洽 ⋯ 下拉后不再依赖该组件）
  @Local showRename: boolean = false;                 // 重命名 sheet 显隐
  @Local renameText: string = '';                      // 重命名输入（预填当前标题）
  @Local renameActing: boolean = false;                // 重命名请求中（防重入 + 保存键置灰）
  @Local sessionActing: boolean = false;               // 归档/删除/切换远程请求中（防重入）
  private renameInputController: TextInputController = new TextInputController();
  @Local searchMode: boolean = false;                 // 🔍 对话内搜索栏显隐（标题栏 🔍/✕ 切换）
  @Local searchQuery: string = '';                     // 搜索查询（纯客户端过滤，对照 Index filteredSessions）
  @Local pendingSchedule: number = 0;                  // 待发定时（0=无/>0=epoch-ms；发送时拼 scheduledAt，对照 PendingSchedule）
  @Local scheduleSheetOpen: boolean = false;           // 定时选择 sheet 显隐
  @Local attachmentPreviewSrc: string = '';            // 用户气泡图片全屏预览源（data: URI 或路径）
  @Local attachmentPreviewOpen: boolean = false;       // 用户气泡图片全屏预览显隐
  @Local scheduleCustomMode: boolean = false;          // 定时 sheet：自定义绝对时间分支（DatePicker+TimePicker）
  @Local pickDate: Date = new Date();                  // 自定义定时所选日期（DatePicker 驱动）
  @Local pickHour: number = 0;                          // 自定义定时所选时（TimePicker 驱动）
  @Local pickMinute: number = 0;                        // 自定义定时所选分（TimePicker 驱动）
  @Local inputCursorStart: number = 0;                 // TextArea 光标区起点（onTextSelectionChange；活动词定位用）
  @Local inputCursorEnd: number = 0;                   // TextArea 光标区终点
  @Local slashSuggestions: SlashCommand[] = [];        // 斜杠补全建议（输入 / 触发；findActiveWord→slashCommandSuggestions）
  @Local slashSelectedIndex: number = 0;               // 补全高亮项（tap 即选；预留键盘扩展）
  @Local serverSlashCommands: SlashCommand[] = [];     // 服务端斜杠命令（loadMessages 拉；recomputeSlash 与 builtin 合并，server 覆盖同名）
  @Local serverSkills: SkillItem[] = [];               // $ 技能（loadMessages 拉；recomputeSkill 评分数据源）
  @Local skillSuggestionItems: SkillItem[] = [];       // $ 技能补全建议（输入 $ 触发；findActiveWord→skillSuggestions）
  @Local skillSelectedIndex: number = 0;               // 补全高亮项（tap 即选）
  private recentSkills: Map<string, number> = new Map();   // 技能最近使用 map（不绑 UI，仅 recomputeSkill 读；选中即时更新+持久化）
  @Local mentionItems: FileSearchItem[] = [];          // @ 文件联想结果（输入 @ 触发；debounce→searchSessionFiles）
  @Local mentionSelectedIndex: number = 0;             // 联想高亮项（tap 即选）
  @Local pendingAttachments: AttachmentMetadata[] = [];   // 待发附件（📎 选文件→upload→入列；发送随消息带走）
  @Local isUploading: boolean = false;                 // 附件上传中（📎 按钮 disabled，防重复选）
  @Local attachmentPanelOpen: boolean = false;          // 附件「+」展开态（animateTo 驱动开合，非声明式 .animation）
  // 附件面板绝对叠层（硬复刻 chatcube ChatPage:185/3735-3754）：高度由 animateTo 驱动 0↔attachPanelHeight，
  //   opacity/enabled 随 attachmentPanelOpen 翻转；card 走流式（自然撑 wrapper 高），panel 绝对底锚覆盖 card 底 padding 留白条。
  @Local attachmentPanelHeightVp: number = 0;             // 附件面板当前高度（0=收起；animateTo 驱动 0↔attachPanelHeight）
  // 发送/附件键动效（对照 chatcube ChatInputBar：图标变形触发器 + pause 呼吸 + 按下态 + 弹跳缩放）
  @Local sendIconTrigger: number = 0;                   // 发送键 ReplaceSymbolEffect 触发器（hasContent/isThinking 翻转 bump）
  @Local attachIconTrigger: number = 0;                 // 附件键 plus↔xmark 变形触发器
  @Local breathOpacity: number = 1;                     // pause 呼吸透明度（生成中且无内容时 1↔0.35 循环）
  @Local sendBtnPressed: boolean = false;               // 发送键按下态（阴影放大 + 0.95 缩放）
  @Local sendBtnScale: number = 1;                      // 发送键状态切换弹跳（isThinking 起 0.9 回弹）
  @Local modelBtnPressed: boolean = false;              // 模型键按下态（0.95 缩放 + 浅底）
  private breatheTimerId: number = -1;                  // 呼吸 setInterval 句柄
  private lastHasContent: boolean = false;              // 上次 hasContent（仅翻转时 bump 触发器，省冗余变形）
  // 附件面板展开高度（3 项 64 圆角块 + 文案 + 内边距；≈118 实测，+6 余量防文案裁切 → 124；= attachmentPanelHeightVp 展开目标值）
  private readonly attachPanelHeight: number = 124;
  private mentionQueryId: number = 0;                  // 联想查询竞态保护：每次发起递增，仅最新返回生效
  private mentionDebounceId: number = -1;              // 联想查询 debounce 句柄（输入停顿 200ms 再查，省请求）
  private textAreaController: TextAreaController = new TextAreaController();   // 光标定位（applySuggestion 后 caretPosition 复位）

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }
  private get isDark(): boolean { return getThemeState().isDark; }

  // —— 液态玻璃配方（复刻 ComposerToolbar:50-62 chip，顶栏/按钮共用）——
  // 半透明色：#RRGGBB → #AA{{RRGGBB}}（HarmonyOS 八位色 alpha 在前）。
  private withAlpha(color: string, alphaHex: string): string {
    if (color.startsWith('#') && color.length === 7) {
      return `#${alphaHex}${color.substring(1)}`;
    }
    return color;
  }
  // 玻璃底半透明（surface + 暗 '14'/亮 '1A'）。
  private glassBg(): string { return this.withAlpha(this.c.surface, this.isDark ? '14' : '1A'); }
  // 未选中描边（border + 暗 'A6'/亮 '73'）。
  private glassBorderInactive(): string { return this.withAlpha(this.c.border, this.isDark ? 'A6' : '73'); }
  // 阴影色（暗 0.18 / 亮 rgba(15,23,42,0.06)）。
  private glassShadow(): string { return this.isDark ? 'rgba(0, 0, 0, 0.18)' : 'rgba(15, 23, 42, 0.06)'; }

  private navPathStack: NavPathStack | null = null;
  private scroller: Scroller = new Scroller();
  // LazyForEach 数据源（流式渲染根治，对照 chatcube ChatMessageListDataSource）：单项原地重渲染、不销毁、
  //   MarkdownText/CJMarkdown 保活 → 流式逐字实时增长、无冻结。refreshDataSource() 把 filteredBlocks 灌入并按签名 diff 通知。
  private dataSource: ChatBlockDataSource = new ChatBlockDataSource();
  private isPinnedToBottom: boolean = true;
  private settlingCancelled: boolean = false;          // 初始滚动定锚：用户上滑即放弃后续重试（对照上游 shouldCancelInitialScrollSettling）
  private settlingTimerIds: number[] = [];             // 初始定锚重试 timer 句柄簇（进会话按延迟数组排多个 scrollEdge）
  private sseListenerId: number = -1;
  private localIdCounter: number = 0;
  private tickerId: number = -1;                // elapsed 每秒 ticker 句柄
  private draftTimerId: number = -1;             // 草稿去抖落盘句柄（onChange 500ms 去抖，aboutToDisappear 即时落盘）
  private nextBeforeAt: number = 0;              // 下一页「加载更旧」游标（服务端 page.nextBeforeAt，0=无更旧）
  private nextBeforeSeq: number = 0;             // 下一页游标 seq（与 nextBeforeAt 成对，禁止本地重算）
  private nextAttachmentSeq: number = 0;         // 附件 id 自增序号（多文件并发 upload 防撞键，替代 Date.now()+length）

  aboutToAppear(): void {
    this.isDisposed = false;        // 复用兜底：aboutToDisappear 置 true 后，若组件被复用须复位
    // @Param 在构造时已由 @Builder 注入，aboutToAppear 可读
    this.sessionId = this.routeParamsSeed !== null ? this.routeParamsSeed.sessionId : '';
    this.sessionTitle = this.routeParamsSeed !== null ? this.routeParamsSeed.title : '';
    // 捕获「进入时上次已看」时间戳（须在 loadMessages/markSeen 前；滚到首条未读 + 未读分隔依据）。
    //   lastSeen 返回 0=从未看过（首次进入无未读概念 → 滚底）。
    if (this.sessionId !== '') {
      this.entryLastSeenAt = getSessionSeenService().lastSeen(this.sessionId);
    }
    this.loadMessages();
    this.restoreDraft();            // 恢复上次未发草稿（per-session，发送/离开落盘）
    this.loadEnterToSend();          // 读「回车发送」偏好（默认关；onChange 据此决定 Enter=发送/换行）
    this.addSSEListener();
    this.startTicker();
    this.lastHasContent = this.composerHasContent();   // 发送键动效初值（进页即生成中也能正确显 pause 呼吸）
    this.updateBreathing();
    // 标记本会话已看（清未读角标；列表据此判断 updatedAt>lastSeenAt）
    if (this.sessionId !== '') {
      getSessionSeenService().markSeen(this.sessionId);
    }
  }

  aboutToDisappear(): void {
    this.stopTicker();
    this.stopBreathing();                   // 清呼吸 setInterval，防销毁后回调写已释放组件
    this.clearMention();                 // 取消 @ 联想在途 debounce，防销毁后回调
    // 离开页面前把草稿即时落盘（去抖未触发的尾字不丢）
    if (this.draftTimerId !== -1) {
      clearTimeout(this.draftTimerId);
      this.draftTimerId = -1;
    }
    this.saveDraft();
    // 离开时再次标记已看：将在本页期间收到的消息也视作已读（now>=updatedAt → 列表不显未读）
    if (this.sessionId !== '') {
      getSessionSeenService().markSeen(this.sessionId);
    }
    if (this.sseListenerId !== -1) {
      getSSEClient().removeListener(this.sseListenerId);
      this.sseListenerId = -1;
    }
    // 节流窗口末次兜底可能还在排程 → 销毁前置位 + 清 timer，防回调跑重算操作已释放组件
    this.isDisposed = true;
    if (this.blocksRecomputeTimer !== -1) {
      clearTimeout(this.blocksRecomputeTimer);
      this.blocksRecomputeTimer = -1;
    }
  }

  // 前台重同步触发（EntryAbility.onForeground beginSync → resyncSeq++）：重拉消息 + 结束同步（关横幅）。
  @Monitor('sync.resyncSeq')
  onResync(monitor: IMonitor): void {
    if (this.sessionId === '') { return; }
    this.loadMessages().then((): void => { SyncStateService.endSync(); });
  }

  // 草稿持久化（per-session 输入框未发文本）：onChange 去抖写 / aboutToDisappear 即时写 / handleSend 清除。
  //   Preferences 无 hasKey，空串判空（'' 视作无草稿 → delete，避免残留空键）。
  private restoreDraft(): void {
    if (this.sessionId === '') { return; }
    getPreferencesService().getString(PreferenceKeys.draftKey(this.sessionId), '')
      .then((d: string) => { if (d !== '') { this.inputText = d; } })
      .catch(() => {});
  }

  // 读「回车发送」偏好（默认 false；Toggle 在设置页改，进对话页时 aboutToAppear 拉取最新值）。
  private loadEnterToSend(): void {
    getPreferencesService().getBoolean(PreferenceKeys.ENTER_TO_SEND, false)
      .then((v: boolean) => { this.enterToSend = v; })
      .catch(() => {});
  }

  private scheduleDraftSave(): void {
    if (this.sessionId === '') { return; }
    if (this.draftTimerId !== -1) { clearTimeout(this.draftTimerId); }
    this.draftTimerId = setTimeout(() => {
      this.draftTimerId = -1;
      this.saveDraft();
    }, 500);
  }

  private saveDraft(): void {
    if (this.sessionId === '') { return; }
    const key = PreferenceKeys.draftKey(this.sessionId);
    const ps = getPreferencesService();
    if (this.inputText === '') {
      ps.delete(key).catch(() => {});
    } else {
      ps.putString(key, this.inputText).catch(() => {});
    }
  }

  private clearDraft(): void {
    if (this.draftTimerId !== -1) { clearTimeout(this.draftTimerId); this.draftTimerId = -1; }
    if (this.sessionId === '') { return; }
    getPreferencesService().delete(PreferenceKeys.draftKey(this.sessionId)).catch(() => {});
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

  // recomputeBlocks 节流（leading + trailing，150ms 窗口）——解「发消息卡死 / 收消息不实时 / 输入框撑满」。
  //   根因：流式 SSE 每秒可触发数十次 message-received，旧实现每次都同步跑 doRecomputeBlocks
  //   （reduceChatBlocks 全量 O(n) + List 全量重排）→ 阻塞 UI 线程，绘制与输入布局被饿死。
  //   正解：窗口内【首】调用立即算（乐观发送 / 单条新消息即时显），窗口内【后续】调用合并为末次兜底
  //   （messages 已是最新，末次必应用，不丢最终态）。150ms 内最多 1 次重算，给 UI 线程留绘制 + 布局空隙。
  private blocksRecomputeTimer: number = -1;
  private blocksRecomputeInWindow: boolean = false;   // 窗口内（leading 已用，后续合并）
  private blocksRecomputePending: boolean = false;    // 窗口内有新调用 → 末次兜底
  private isDisposed: boolean = false;                // aboutToDisappear 置位，防销毁后回调跑重算
  // 输入框补全重算（slash/mention/skill）合并延迟标记。TextArea 的 onChange/onTextSelectionChange 在其【自身构建周期内】
  //   触发——若此时同步改 slashSuggestions/mentionItems/skillSuggestionItems（构建中条件渲染的联想浮层），会触发
  //   ArkUI「New UINode added while re-render」（build-phase state change），且TextArea 的 maxHeight 约束可能不生效→输入框撑大。
  //   延到 setTimeout(0)：等 TextArea 构建结束、在独立帧改 @Local → 浮层在正常渲染周期挂载。inputText/inputCursor 仍同步赋值。
  private suggestionRecomputeScheduled: boolean = false;
  private recomputeBlocks(): void {
    if (this.isDisposed) {
      return;
    }
    if (this.blocksRecomputeInWindow) {
      this.blocksRecomputePending = true;             // 窗口内后续：仅标记，等末次兜底
      return;
    }
    this.doRecomputeBlocks();                         // 窗口首调用：立即算 + 开窗口
    this.blocksRecomputeInWindow = true;
    this.blocksRecomputeTimer = setTimeout((): void => {
      this.blocksRecomputeTimer = -1;
      this.blocksRecomputeInWindow = false;
      if (this.isDisposed) {
        return;
      }
      if (this.blocksRecomputePending) {
        this.blocksRecomputePending = false;
        this.recomputeBlocks();                       // 末次兜底；递归开新窗口（持续流则持续节流）
      }
    }, 150);
  }

  private doRecomputeBlocks(): void {
    // 排队消息（isQueued：已发未被 CLI 消费，含即时排队 + 定时）不进 thread——对照 web SessionChat 过滤
    //   isQueuedForInvocation 行，仅由 QueuedMessagesBar 承载。thread 仅留已生效消息 + 失败行（可重发）。
    const visible: ChatMessage[] = this.messages.filter((m: ChatMessage): boolean => !m.isQueued);
    const reduced: ChatBlock[] = reduceChatBlocks(visible, this.agentState);
    // 工具卡分组（对照 web buildVisibleChatBlocks）：把连续同质工具调用折叠成 tool-group 块。
    //   在 reducer 之后、分隔线盖戳之前派生——组块 createdAt=首工具，日期/未读分隔据此盖戳仍保序。
    //   不入 reducer（保 reducer 纯净/不影响其单测）；hasMoreMessages 仅影响边界组的 id 锚点（跨页回灌留观察）。
    const grouped: ChatBlock[] = buildVisibleChatBlocks(reduced, this.hasMoreMessages);
    // 盖「日期分隔」渲染标记：首条或与前一块不同日 → dividerBefore（纯序列判定，无 now 依赖）。
    //   盖在 block 自身字段（同 userOptimistic/userStatus 渲染提示），避免在 ForEach 闭包里依赖捕获的
    //   index/prev——后者在「加载更旧」prepend 重排后可能因 key 复用而不刷新（对齐 ArkUI ForEach 文档：
    //   「修改数据项若键值不变，则组件不更新」）。DateDivider 文本（今天/昨天/日期）在渲染时取。
    for (let i = 0; i < grouped.length; i++) {
      const prevTs: number = i > 0 ? grouped[i - 1].createdAt : 0;
      grouped[i].dividerBefore = shouldShowDateDivider(grouped[i].createdAt, prevTs);
    }
    // 盖「未读分隔」标记：entryLastSeenAt > 0 时，首条 createdAt>entryLastSeenAt 的块前置 unreadDividerBefore。
    //   其余块一律 false（含上次无未读 / 首次进入 entryLastSeenAt=0 → 全 false，不显分隔）。
    //   新消息到达不改变「首条未读」位置（新块 createdAt 更晚，首条 >entryLastSeenAt 仍是原块）；load-older 拉的是更早块，亦不跨阈值。
    for (let i = 0; i < grouped.length; i++) {
      grouped[i].unreadDividerBefore = false;
    }
    if (this.entryLastSeenAt > 0) {
      for (let i = 0; i < grouped.length; i++) {
        if (grouped[i].createdAt > this.entryLastSeenAt) {
          grouped[i].unreadDividerBefore = true;
          break;
        }
      }
    }
    // 同 id 复用旧实例 + copyFrom 原地改 @Trace 字段 → Repeat 同 key 项内部精确刷新（流式根治，对照官方示例3/5）。
    this.blocks = this.reconcileBlocks(grouped);
    // 大纲项随 blocks 一起重算（只索引 user-text 块；大纲抽屉直接读 outlineItems）
    this.outlineItems = buildConversationOutline(grouped);
    // 灌入 LazyForEach 数据源：按签名 diff，结构变→全刷、同结构→仅变项 onDataChange 原地重渲染（流式根治）
    this.refreshDataSource();
  }

  // 同 id 复用旧实例 + copyFrom 原地改字段（@ObservedV2+@Trace → Repeat 同 key 项内部精确刷新）。
  //   根因：官方「循环渲染迁移」示例3/5——Repeat 对同 key 项复用 ListItem、不重跑 .each，内容刷新须靠 @Trace
  //   字段【原地变更】。reducer 每次产全新实例 → 直接 this.blocks=newArr 时同 key 项内容冻住（流式「一动不动」根因）。
  //   本方法把 reducer 产出的新实例按 id 对齐到旧实例，copyFrom 把可变字段原地写入旧实例（@Trace 触发刷新）；
  //   新 id（新消息 / 加载更旧历史）用新实例。返回新数组壳、元素尽量复用 → Repeat diff 命中同 key + @Trace 变更。
  private reconcileBlocks(next: ChatBlock[]): ChatBlock[] {
    const prevById: Map<string, ChatBlock> = new Map<string, ChatBlock>();
    for (let i = 0; i < this.blocks.length; i++) {
      prevById.set(this.blocks[i].id, this.blocks[i]);
    }
    const out: ChatBlock[] = [];
    for (let i = 0; i < next.length; i++) {
      const nb: ChatBlock = next[i];
      const prev: ChatBlock | undefined = prevById.get(nb.id);
      if (prev !== undefined) {
        prev.copyFrom(nb);   // 原地改 @Trace 字段 → 同 key 项内部刷新（MarkdownText content @Param 随之更新）
        out.push(prev);
      } else {
        out.push(nb);        // 新块（新消息 / 加载更旧历史）→ 新实例
      }
    }
    return out;
  }

  // 把当前展示集（filteredBlocks）灌入 LazyForEach 数据源。sigFn=blockSignature（含 toolActionStates/
  //   detailOpenSigs 等实例态）→ DataSource 据此 diff，仅对变化 index 调 onDataChange → 单项原地刷新。
  //   流式只改末块 text → 仅刷新末块（MarkdownText 保活、CJMarkdown 不重建）。
  private refreshDataSource(): void {
    this.dataSource.setItems(this.filteredBlocks, (b: ChatBlock): string => this.blockSignature(b));
  }

  // 搜索过滤变化（显隐/查询）→ 展示集结构变 → reload 数据源（filteredBlocks 已读新 searchMode/searchQuery）。
  @Monitor('searchMode')
  onSearchModeChange(_monitor: IMonitor): void { this.refreshDataSource(); }
  @Monitor('searchQuery')
  onSearchQueryChange(_monitor: IMonitor): void { this.refreshDataSource(); }

  // 块变更指纹（LazyForEach 数据源 diff 用，非 ForEach key——ForEach/LazyForEach key 恒用稳定 b.id）：
  //   反映块的「会变化的内容维度」→ 内容/state/审批态变 → 指纹变 → DataSource 对该项 onDataChange 原地重渲染。
  //   agent-text/reasoning/cli-output 用 text.length（流式追加）；tool-call 含 state/result/权限/审批态/子代理 childSig；
  //   user-text 用 userStatus；tool-group 用组内 sig；generated-image/codex-review/agent-event 稳定用 b.id。
  private blockSignature(b: ChatBlock): string {
    if (b.kind === 'agent-text' || b.kind === 'reasoning') {
      return `${b.id}#${b.text.length}`;   // 文本流式追加：length 单调增 → 签名变 → 该项 onDataChange 原地刷新（MarkdownText 保活）
    }
    if (b.kind === 'user-text') {
      // 乐观消息发送态翻转(sending→queued/failed；updateOptimisticStatus 原地改 status、id 不变)→ 签名变 → 原地刷新。
      //   尤其 failed：不修则卡在 sending，用户看不到失败红标/提示。真实消息 status 恒 sent(终态)→ 签名稳定不刷新。
      return `${b.id}#${b.userStatus}`;
    }
    if (b.kind === 'tool-call' && b.tool !== null) {
      // 工具状态翻转(running→completed/error)、结果回填、权限变更、审批态变化 → 签名变 → 该项 onDataChange 原地刷新。
      //   审批态(actionLoading/decided)入签名 → 点击/成功/失败均触发原地刷新（不走 @ObservedV2+@Trace，
      //   避 berry3 坑7「@Trace 经 @Param/@Consumer 不触发 build」风险）。actionError 不入签名：其每次变化必伴
      //   actionLoading 变化（loading mark↔''），故随该次刷新一并取最新。
      const tool: ChatToolCall = b.tool;
      const perm: string = tool.permission !== null ? tool.permission.status : '';
      const act: ToolActionState | undefined = this.toolActionStates[b.id];
      const loading: string = act !== undefined ? act.actionLoading : '';
      const decided: string = (act !== undefined && act.decided) ? '1' : '0';
      // 子代理 children 内容指纹（childSigOf）：children 流式追加/状态翻转时签名变 → 父卡原地刷新 → block @Param 取最新
      //   → 展开详情 sheet 时 TraceSection 拿到最新 children（修「子代理轨迹冻结在首次渲染」遗漏）。sheet 展开期间
      //   childSigOf 取冻结值（见 detailOpenSigs）→ 签名不变 → 父卡不刷新 → sheet/滚动稳定无闪烁。
      return `${b.id}#${tool.state}${tool.result !== null ? '1' : '0'}${perm}#${loading}${decided}#${this.childSigOf(b)}`;
    }
    if (b.kind === 'cli-output') {
      // CLI 输出流式追加（与 agent-text 同源 c.text，SSE delta 累积）→ length 增 → 签名变 → 原地刷新（同类遗漏）
      return `${b.id}#${b.text.length}`;
    }
    if (b.kind === 'tool-group') {
      // 组内工具状态翻转(running→completed/error)、结果回填、成员增减 → 签名变 → 该项原地刷新。组内 tool-call 被
      //   buildVisibleChatBlocks 折叠吸收(不透出顶层)→ 其状态只能经本 tool-group 块刷新；b.id(锚 firstId)稳定，
      //   LazyForEach 复用旧实例无变化通知时内容冻结(同类遗漏)。open 展开态随翻转刷新会丢失，但翻转低频(每工具一次)、
      //   全完成后稳定，可接受（异于 ToolCard 的 sheet+高频子代理流式，故不做冻结 pin / 不上提 open 态）。
      let sig: string = '';
      const tools: ChatBlock[] = b.groupTools;
      for (let i = 0; i < tools.length; i++) {
        const t: ChatToolCall | null = tools[i].tool;
        if (t !== null) {
          sig += `${t.state}${t.result !== null ? '1' : '0'},`;
        }
      }
      return `${b.id}#${sig}`;
    }
    return b.id;
  }

  // 子代理 children 内容签名（流式块的内容维度）：agent-text/reasoning 取 text.length、tool-call 取 state+result，
  //   其余取稳定占位。入父卡签名 → children 变化时父卡签名变 → 该项 onDataChange 原地刷新（嵌套轨迹同类流式遗漏的根因修复）。
  private childSignature(children: ChatBlock[]): string {
    let sig: string = '';
    for (let i = 0; i < children.length; i++) {
      const c: ChatBlock = children[i];
      if (c.kind === 'agent-text' || c.kind === 'reasoning') {
        sig += `${c.text.length},`;
      } else if (c.kind === 'tool-call' && c.tool !== null) {
        sig += `${c.tool.state}${c.tool.result !== null ? '1' : '0'},`;
      } else {
        sig += '.,';
      }
    }
    return sig;
  }

  // 取块的 childSig：详情 sheet 展开时返回冻结值（签名不变→父卡不刷新→sheet/滚动/TraceSection 全稳定，无闪烁）；
  //   关闭时返回实时值（children 变→签名变→原地刷新→下次展开取最新）。冻结值由 toggleToolDetail 在展开瞬间写入（=当时实时值→签名不变）。
  private childSigOf(b: ChatBlock): string {
    const frozen: string | undefined = this.detailOpenSigs[b.id];
    if (frozen !== undefined) {
      return frozen;
    }
    return this.childSignature(b.children);
  }

  // 取块的审批态（@Param 注入 ToolCard 用）：未记录返回稳定空实例（避免每帧新建；对照 ToolCard emptyTool 模式）。
  private emptyActionState: ToolActionState = new ToolActionState();
  private toolActionStateOf(blockId: string): ToolActionState {
    const s: ToolActionState | undefined = this.toolActionStates[blockId];
    return s !== undefined ? s : this.emptyActionState;
  }

  // 整体替换 toolActionStates（V2 @Local Record 原地改不追踪 → 必整体替换；blockSignature 读其字段 → 替换后签名变 → 原地刷新）。
  private setToolAction(blockId: string, loading: string, decided: boolean, error: string): void {
    const next: Record<string, ToolActionState> = {} as Record<string, ToolActionState>;
    const keys: string[] = Object.keys(this.toolActionStates);
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      const src: ToolActionState = this.toolActionStates[k];
      const c: ToolActionState = new ToolActionState();
      c.actionLoading = src.actionLoading;
      c.decided = src.decided;
      c.actionError = src.actionError;
      next[k] = c;
    }
    const s: ToolActionState = new ToolActionState();
    s.actionLoading = loading;
    s.decided = decided;
    s.actionError = error;
    next[blockId] = s;
    this.toolActionStates = next;
    // 审批态入 blockSignature → 替换后刷新数据源，单项 onDataChange 原地重渲染（显 loading/decided/error，无重建）
    this.refreshDataSource();
  }

  // tool 详情 sheet 展开/收起同步（ToolCard.isDetailOpen 经 @Monitor→onDetailOpenChange 回调）：
  //   展开→冻结当前 childSig 入 detailOpenSigs（blockSignature 取冻结值→签名不变→父卡不刷新→sheet/滚动稳定无闪烁）；
  //   收起→移除冻结（签名恢复随实时 children→若有变化则刷新→下次展开取最新）。V2 @Local Record 原地改不追踪→整体替换。
  private toggleToolDetail(blockId: string, open: boolean): void {
    const already: boolean = this.detailOpenSigs[blockId] !== undefined;
    if (open === already) {
      return;   // 无变化（aboutToAppear 恢复 isDetailOpen 触发的 @Monitor 命中此 no-op，避 build 期无谓重算）
    }
    const next: Record<string, string> = {} as Record<string, string>;
    const keys: string[] = Object.keys(this.detailOpenSigs);
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      if (!open && k === blockId) {
        continue;   // 收起：跳过该 key（等价 delete，避 ArkTS delete 动态操作）
      }
      next[k] = this.detailOpenSigs[k];
    }
    if (open) {
      // 冻结当前 children 签名（=展开瞬间实时值 → blockSignature 不变 → 父卡不刷新 → sheet 无闪烁展开）
      let children: ChatBlock[] = [];
      for (let i = 0; i < this.blocks.length; i++) {
        if (this.blocks[i].id === blockId) {
          children = this.blocks[i].children;
          break;
        }
      }
      next[blockId] = this.childSignature(children);
    }
    this.detailOpenSigs = next;
    // childSigOf 读 detailOpenSigs → 冻结/解冻后刷新数据源（展开态切换时该项原地刷新）
    this.refreshDataSource();
  }

  // 审批动作执行（自 ToolCard doXxx 迁移）：基于块 permission 调 HubClient，更新 toolActionStates。
  //   kind 取自 ActionRow actionKey（allow/session/alledits/deny/codexYes/codexSession/abort）。
  //   loadingMark 对齐原 doXxx：codexYes→'allow'、codexSession→'session'（PermissionFooter 据此显 spinner）。
  private async handleToolAction(b: ChatBlock, kind: string): Promise<void> {
    const tool: ChatToolCall | null = b.tool;
    const p: ToolPermission | null = tool !== null ? tool.permission : null;
    if (p === null) {
      return;
    }
    const cur: ToolActionState | undefined = this.toolActionStates[b.id];
    if (cur !== undefined && cur.actionLoading !== '') {
      return;   // 防重入（对齐原 doXxx actionLoading 守卫）
    }
    const loadingMark: string = kind === 'codexYes' ? 'allow' : (kind === 'codexSession' ? 'session' : kind);
    const prevDecided: boolean = cur !== undefined && cur.decided;
    let failMsg: string = t('tool.approveFailed');
    if (kind === 'deny' || kind === 'abort') {
      failMsg = t('tool.denyFailed');
    }
    this.setToolAction(b.id, loadingMark, prevDecided, '');
    let ok: boolean = false;
    try {
      if (kind === 'allow') {
        ok = await getHubClient().approvePermission(this.sessionId, p.id);
      } else if (kind === 'session') {
        const opts: ApproveOptions = new ApproveOptions();
        let ident: string = tool !== null ? tool.name : '';
        if (ident === 'Bash' && tool !== null) {
          const cmd: string = getInputStrAny(tool.input, ['command', 'cmd']);
          ident = cmd !== '' ? `Bash(${cmd})` : 'Bash';
        }
        opts.allowTools = [ident];
        ok = await getHubClient().approvePermission(this.sessionId, p.id, opts);
      } else if (kind === 'alledits') {
        const opts: ApproveOptions = new ApproveOptions();
        opts.mode = 'acceptEdits';
        ok = await getHubClient().approvePermission(this.sessionId, p.id, opts);
      } else if (kind === 'deny') {
        ok = await getHubClient().denyPermission(this.sessionId, p.id);
      } else if (kind === 'codexYes') {
        const opts: ApproveOptions = new ApproveOptions();
        opts.decision = 'approved';
        ok = await getHubClient().approvePermission(this.sessionId, p.id, opts);
      } else if (kind === 'codexSession') {
        const opts: ApproveOptions = new ApproveOptions();
        opts.decision = 'approved_for_session';
        ok = await getHubClient().approvePermission(this.sessionId, p.id, opts);
      } else if (kind === 'abort') {
        ok = await getHubClient().denyPermission(this.sessionId, p.id, 'abort');
      }
    } catch (e) {
      this.setToolAction(b.id, '', prevDecided, errMsg(e, failMsg));
      return;
    }
    if (ok) {
      this.setToolAction(b.id, '', true, '');
      this.refreshAfterDecision();
    } else {
      this.setToolAction(b.id, '', prevDecided, failMsg);
    }
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

  // 最新有效 thread-goal（对照 reducer.ts getLatestThreadGoal）：读 @Local messages 派生，同
  //   latestUsage 范式——messages 整体重赋值即重算，免 seed/live-sync 三点接线（乐观 user 消息已在
  //   list 内，complete 抑制 / cleared 清空逻辑均可见）。仅 codex 由 StatusBar.ets shouldShowGoalChip 门控显隐。
  private get threadGoal(): ThreadGoal | null { return getLatestThreadGoal(this.messages); }

  // 标题栏副标题：agent 名 + model 显示名 + worktree 分支（对照上游 SessionHeader 副标题多 span：flavor/model/worktree）。
  //   鸿蒙简化为单行（上游 flex-wrap 多 span），长则省略号截断。flavor/model/worktree 任一可用即显（不再因 flavor='' 整体隐藏）。
  private get chatSubtitle(): string {
    // flavor/model/worktree 任一可用即显（解除原 flavor==='' 整体隐藏门控）。
    // model 始终显：modelDisplayName 对 '' / 'auto' 返回「默认」，与会话配置面板一致——避免模型名不显示。
    const agent: string = this.flavor !== '' ? agentDisplayName(this.flavor) : '';
    const model: string = modelDisplayName(this.flavor, this.model);   // 恒非空
    let s: string = agent !== '' ? `${agent} · ${model}` : model;
    if (this.worktreeBranch !== '') { s = `${s} · ${t('session.item.worktree')}: ${this.worktreeBranch}`; }
    return s;
  }

  // 标题内容已下沉到 ChatTopBar（hideTitleBar 后自建栏内联 flavor 徽章 + 标题/副标题）。

  @Builder ContextStatusBar() {
    Row({ space: 8 }) {
      Text(this.contextLabel).fontSize(fs(11)).fontColor(this.contextColor)
      if (this.cacheLabel !== '') {
        Text(this.cacheLabel).fontSize(fs(11)).fontColor(this.c.textTertiary)
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

  // 进文件浏览页（git 改动 / 目录树 / 搜索；对照 web /sessions/$id/files）
  private openFiles(): void {
    if (this.sessionId === '' || this.navPathStack === null) { return; }
    const p: FilesRouteParams = new FilesRouteParams();
    p.sessionId = this.sessionId;
    this.navPathStack.pushPath({ name: 'FilesPage', param: p });
  }

  // 正文裸文件路径点击 → 进文件查看页（对照上游 hapi-file: 链接 → FileViewer）。
  //   showDiff=false（只看内容）；不带行号（FileViewerRouteParams 无 line 字段，上游 web 也不传行号）。
  private openFilePath(path: string): void {
    if (path === '' || this.sessionId === '' || this.navPathStack === null) { return; }
    const p: FileViewerRouteParams = new FileViewerRouteParams();
    p.sessionId = this.sessionId;
    p.path = path;
    p.showDiff = false;
    this.navPathStack.pushPath({ name: 'FileViewerPage', param: p });
  }

  // 进终端页（session 工作目录开交互 shell；对照 web /sessions/$id/terminal）
  private openTerminal(): void {
    if (!this.isActive || this.sessionId === '' || this.navPathStack === null) { return; }
    const p: TerminalRouteParams = new TerminalRouteParams();
    p.sessionId = this.sessionId;
    this.navPathStack.pushPath({ name: 'TerminalPage', param: p });
  }

  // 进语音页（ElevenLabs Conversational AI；对照 web /sessions/$id/realtime）
  private openVoice(): void {
    if (!this.isActive || this.sessionId === '' || this.navPathStack === null) { return; }
    const p: VoiceRouteParams = new VoiceRouteParams();
    p.sessionId = this.sessionId;
    this.navPathStack.pushPath({ name: 'VoicePage', param: p });
  }

  // —— 会话生命周期（⋯ 下拉自带；逐字镜像 SessionActionMenu:90-204，行为对齐上游）——
  // 重命名：预填当前标题，开重命名 sheet
  private startRename(): void {
    this.renameText = this.sessionTitle;
    this.showRename = true;
  }

  private closeRename(): void {
    this.showRename = false;
    this.renameText = '';
  }

  // 确认重命名：空或未改不请求；成功回写 sessionTitle + 关面板；失败保留面板（toast）
  private async confirmRename(): Promise<void> {
    if (this.renameActing || this.sessionId === '') {
      return;
    }
    const name = this.renameText.trim();
    if (name.length === 0 || name === this.sessionTitle) {
      this.closeRename();
      return;
    }
    this.renameActing = true;
    try {
      const ok = await getHubClient().renameSession(this.sessionId, name);
      if (ok) {
        this.sessionTitle = name;
        showToast(t('sessionMenu.renamed'));
        this.closeRename();
      } else {
        showToast(t('sessionMenu.renameFailed'));
      }
    } catch (e) {
      showToast(t('sessionMenu.renameFailed'));
    } finally {
      this.renameActing = false;
    }
  }

  // 切换到远程（仅 active）：关下拉 → POST /switch → toast（无本地态变更，不阻塞）
  private async startSwitchRemote(): Promise<void> {
    if (this.sessionActing || this.sessionId === '') {
      return;
    }
    this.sessionActing = true;
    try {
      const ok = await getHubClient().switchSession(this.sessionId);
      showToast(ok ? t('sessionMenu.switchedRemote') : t('sessionMenu.switchRemoteFailed'));
    } catch (e) {
      showToast(t('sessionMenu.switchRemoteFailed'));
    } finally {
      this.sessionActing = false;
    }
  }

  // 归档二次确认（危险操作，confirm 红字）
  private confirmArchive(): void {
    this.getUIContext().showAlertDialog({
      title: t('sessionMenu.archiveTitle'),
      message: t('sessionMenu.archiveConfirm', kv('name', this.sessionTitle)),
      autoCancel: true,
      confirm: {
        value: t('sessionMenu.archive'),
        fontColor: this.c.error,
        action: () => { this.doArchive(); }
      }
    });
  }

  // 删除二次确认（硬删除不可恢复，confirm 红字）
  private confirmDelete(): void {
    this.getUIContext().showAlertDialog({
      title: t('sessionMenu.deleteTitle'),
      message: t('sessionMenu.deleteConfirm', kv('name', this.sessionTitle)),
      autoCancel: true,
      confirm: {
        value: t('sessionMenu.delete'),
        fontColor: this.c.error,
        action: () => { this.doDelete(); }
      }
    });
  }

  // 执行归档：成功 isActive=false（菜单翻删除，不离开页）；失败 toast
  private async doArchive(): Promise<void> {
    if (this.sessionActing || this.sessionId === '') {
      return;
    }
    this.sessionActing = true;
    try {
      const ok = await getHubClient().archiveSession(this.sessionId);
      if (ok) {
        this.isActive = false;
        showToast(t('sessionMenu.archived'));
      } else {
        showToast(t('sessionMenu.archiveFailed'));
      }
    } catch (e) {
      showToast(t('sessionMenu.archiveFailed'));
    } finally {
      this.sessionActing = false;
    }
  }

  // 执行删除：成功 pop 回列表；失败 toast。清该会话生成图片盘文件 + 索引（hash 不可逆→跨重启孤儿留观察）
  private async doDelete(): Promise<void> {
    if (this.sessionActing || this.sessionId === '') {
      return;
    }
    this.sessionActing = true;
    try {
      const ok = await getHubClient().deleteSession(this.sessionId);
      if (ok) {
        getGeneratedImageCache().clearSession(this.sessionId);
        showToast(t('sessionMenu.deleted'));
        HapticService.tap('delete');
        if (this.navPathStack !== null) {
          this.navPathStack.pop();
        }
      } else {
        showToast(t('sessionMenu.deleteFailed'));
        HapticService.tap('error');
      }
    } catch (e) {
      showToast(t('sessionMenu.deleteFailed'));
      HapticService.tap('error');
    } finally {
      this.sessionActing = false;
    }
  }

  // ⋯ 下拉「归档/删除」分发：active→归档，否则→删除（永不并存，对照上游 SessionActionMenu）
  private onDestructiveTap(): void {
    if (this.isActive) {
      this.confirmArchive();
    } else {
      this.confirmDelete();
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
        this.worktreeBranch = session.worktreeBranch;
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
      // 拉服务端斜杠命令（用户/项目/插件；失败静默返 [] 回落内置，不阻塞消息展示）——对照上游 useSlashCommands
      this.serverSlashCommands = serverCommandsToSlash(await getHubClient().getSlashCommands(this.sessionId));
      // 拉 $ 技能 + 最近使用 map（失败静默返 [] / 空 map；技能联想数据源）——对照上游 useSkills + recent-skills
      this.serverSkills = await getHubClient().getSkills(this.sessionId);
      this.recentSkills = await loadRecentSkills(getPreferencesService());
      this.isPinnedToBottom = true;
      // 进会话定位：有未读（entryLastSeenAt>0 且存在更新的块）→ 滚到首条未读、不贴底（新消息到达显浮标）；
      //   否则滚底（对照上游总滚底行为）。首次进入 entryLastSeenAt=0 → 无未读 → 滚底。
      if (this.entryLastSeenAt > 0 && this.hasUnreadBlock()) {
        this.isPinnedToBottom = false;
        this.scrollToFirstUnread();
      } else {
        this.settleScrollToBottom();
      }
    } catch (e) {
      this.loadError = e instanceof Error ? e.message : t('chat.loadError');
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
        const merged: ChatMessage[] = mergeMessage(this.messages, msg);
        this.setMessages(merged);
        // 贴底 → 跟随滚底；滚在上方读历史 → 不打断，累计新消息计数显浮标（对照上游 NewMessagesIndicator 思路，扩到实时新消息）
        if (this.isPinnedToBottom) {
          this.maybeScrollToBottom();
        } else {
          this.newMessagesCount = this.newMessagesCount + 1;
        }
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
    const attachments = this.pendingAttachments;   // 捕获待发附件（发送后清空）
    if ((text === '' && attachments.length === 0) || this.isSending || this.sessionId === '') {
      return;
    }
    this.localIdCounter = this.localIdCounter + 1;
    const localId = `local-${Date.now()}-${this.localIdCounter}`;
    // attachments 与 scheduledAt 互斥：有附件时不定时（HubClient 亦会丢弃 scheduledAt）
    const schedule = attachments.length > 0 ? 0 : this.pendingSchedule;   // 捕获待发定时（发送后清空）

    const optimistic = new ChatMessage();
    optimistic.id = localId;
    optimistic.localId = localId;
    optimistic.role = 'user';
    optimistic.text = text;
    optimistic.status = 'sending';
    optimistic.isOptimistic = true;
    optimistic.createdAt = Date.now();
    optimistic.scheduledAt = schedule;       // 定时乐观行：QueuedMessagesBar 显「⏰ X 后发送」
    optimistic.attachments = attachments;    // 乐观携带附件（含图片 previewUrl）→ 历史立即显缩略图

    this.setMessages(this.messages.concat([optimistic]));
    this.inputText = '';
    this.clearDraft();                // 已发文本落进消息流，清掉草稿（防重进误恢复）
    this.pendingSchedule = 0;                // 已捕获到 schedule，清空待发态
    this.pendingAttachments = [];            // 已捕获到 attachments，清空待发区
    this.slashSuggestions = [];               // 发送后清空残留补全（按钮发送不触发 recompute）
    this.clearMention();                      // 发送后清 @ 联想（含取消在途 debounce）
    this.clearSkill();                        // 发送后清 $ 联想
    this.inputCursorStart = 0;
    this.inputCursorEnd = 0;
    this.isSending = true;
    if (schedule <= 0) {
      this.isThinking = true;                // 即时发送才显生成中（定时未触发，agent 未跑）
    }
    this.scrollToBottom();

    try {
      // 非活跃会话：发送前先 resume（对齐上游 useSendMessage.resolveSessionId——
      // session 非 active 时先复活拿【可能新的】sessionId 再发，否则 POST messages 撞 requireActive）。
      if (!this.isActive) {
        try {
          const resumedId = await getHubClient().resumeSession(this.sessionId, this.permissionMode);
          if (resumedId !== '' && resumedId !== this.sessionId) {
            this.sessionId = resumedId;   // 后续 SSE 事件过滤 + 发送都走新 id
          }
          this.isActive = true;
        } catch (e) {
          this.updateOptimisticStatus(localId, 'failed');
          showToast(t('chat.resumeFailed'));
          return;
        }
      }
      const ok = await getHubClient().sendMessage(this.sessionId, text, localId, schedule, attachments);
      this.updateOptimisticStatus(localId, ok ? 'queued' : 'failed');
      HapticService.tap(ok ? 'send' : 'error');   // 触感：成功轻点 / 失败警示震
    } catch (e) {
      this.updateOptimisticStatus(localId, 'failed');
      HapticService.tap('error');
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

  // 停止生成：中止会话运行（对照 web abortSession）。isAborting 防重入 + 驱动 abort 按钮 spinner；
  //   thread 停后（await resolve）复位，对照上游 isAborting 在 threadIsRunning 转 false 后清的 effect。
  private async handleStop(): Promise<void> {
    if (this.isAborting) { return; }
    this.isAborting = true;
    HapticService.tap('error');
    try {
      await getHubClient().abortSession(this.sessionId);
    } catch (e) {
      // 忽略
    } finally {
      this.isThinking = false;
      this.isAborting = false;
    }
  }

  // —— 排队消息：编辑 / 取消（对照 web QueuedMessagesBar edit + useCancelQueuedMessage）——

  // 编辑 = 回填 composer（文本 + 恢复定时）+ 移除本行。有服务端 id 则顺带 cancel（服务器删）。
  private async editQueued(m: ChatMessage): Promise<void> {
    this.inputText = m.text;
    this.pendingSchedule = (m.scheduledAt > 0 && m.scheduledAt > Date.now()) ? m.scheduledAt : 0;
    this.slashSuggestions = [];               // 回填后清残留补全（光标未定位，不重算）
    this.clearMention();                      // 回填后清 @ 联想（草稿可能含 @，但不主动联想）
    this.clearSkill();                        // 回填后清 $ 联想
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
      showToast(t('chat.cancelFailed'));
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
    this.scheduleCustomMode = false;
  }

  // 切到自定义绝对时间分支：用「当前+1分钟」播种 DatePicker/TimePicker（保证默认值落在合法未来区间）。
  private openCustomSchedule(): void {
    const seed: Date = new Date(Date.now() + 60 * 1000);
    this.pickDate = seed;
    this.pickHour = seed.getHours();
    this.pickMinute = seed.getMinutes();
    this.scheduleCustomMode = true;
  }

  // 确认自定义定时：pickDate 的 Y/M/D + pickHour/pickMinute 合成 epoch-ms，clamp 到 [now, now+7d]
  //   （对齐上游 apiTypes.ts refine：.positive() + ≤ now+7d；无 past 下限，故 past 选择就近 clamp 成 now）。
  private confirmCustomSchedule(): void {
    const d: Date = new Date(this.pickDate.getTime());
    d.setHours(this.pickHour, this.pickMinute, 0, 0);
    const now: number = Date.now();
    const max: number = now + 7 * 24 * 3600 * 1000;
    const target: number = d.getTime();
    this.pendingSchedule = Math.min(Math.max(target, now), max);
    this.scheduleSheetOpen = false;
    this.scheduleCustomMode = false;
  }

  // —— 斜杠命令补全（对照 web useActiveWord + useSlashCommands.getSuggestions）——
  //   onTextSelectionChange / onChange 触发：以光标选区在 inputText 回溯找 '/' 前缀活动词，
  //   命中则按 flavor 取内置命令评分（精确/前缀/包含/Levenshtein），取前 6 条；否则清空。
  // 把 slash/mention/skill 三项补全重算合并到下一帧执行（TextArea 回调期外）。
  //   TextArea 的 onChange/onTextSelectionChange 在组件自身构建周期内触发，同步改联想 @Local 会触发
  //   「New UINode added while re-render」→ 延到 setTimeout(0) 在构建结束后跑。inputText/光标已同步赋值，
  //   延迟仅影响联想浮层显隐一帧（不可察）。多次连续输入（快速打字）合并为一次重算（去抖合并，非节流）。
  private scheduleSuggestionRecompute(): void {
    if (this.suggestionRecomputeScheduled) {
      return;
    }
    this.suggestionRecomputeScheduled = true;
    setTimeout((): void => {
      this.suggestionRecomputeScheduled = false;
      if (this.isDisposed) {
        return;
      }
      this.recomputeSlash();
      this.recomputeMention();
      this.recomputeSkill();
    }, 0);
  }

  private recomputeSlash(): void {
    const aw = findActiveWord(this.inputText, this.inputCursorStart, this.inputCursorEnd, ['/']);
    if (aw === null || !aw.activeWord.startsWith('/')) {
      this.slashSuggestions = [];
      this.slashSelectedIndex = 0;
      return;
    }
    // builtin 在前、server 在后 → mergeSlashCommands 同名 server 覆盖 builtin（对照上游 useSlashCommands:59）
    const all: SlashCommand[] = mergeSlashCommands(
      getBuiltinSlashCommands(this.flavor).concat(this.serverSlashCommands));
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

  // —— @ 文件提及联想（数据源 GET /sessions/:id/files?query=；非上游移植，纯新增）——
  //   复用 ActiveWord 的 '@' 前缀分支（findEnd 对文件路径的 / . 不中断）：光标处回溯找 '@' 活动词，
  //   命中则取 '@' 后的 query，debounce 200ms 查 searchSessionFiles（limit 20），结果回填 mentionItems。
  //   mentionQueryId 防竞态：快速输入只认最后一次返回；session 间切换/页面销毁需 clearMention 清状态。
  private recomputeMention(): void {
    const aw = findActiveWord(this.inputText, this.inputCursorStart, this.inputCursorEnd, ['@']);
    if (aw === null || !aw.activeWord.startsWith('@')) {
      this.clearMention();
      return;
    }
    // '@' 后的查询串（活动词去掉前缀 '@'）
    const query: string = aw.activeWord.substring(1);
    if (this.mentionDebounceId !== -1) {
      clearTimeout(this.mentionDebounceId);
      this.mentionDebounceId = -1;
    }
    this.mentionDebounceId = setTimeout((): void => { this.fetchMentionSuggestions(query); }, 200);
  }

  private fetchMentionSuggestions(query: string): void {
    this.mentionDebounceId = -1;
    const myId: number = ++this.mentionQueryId;
    getHubClient().searchSessionFiles(this.sessionId, query, 20)
      .then((items: FileSearchItem[]): void => {
        if (myId !== this.mentionQueryId) { return; }     // 已有更新查询在途，丢弃过期结果
        // 仅展示文件项（folder 也保留——可能想 @ 一个目录）；空结果关浮层
        this.mentionItems = items;
        this.mentionSelectedIndex = 0;
      })
      .catch((): void => {
        if (myId !== this.mentionQueryId) { return; }
        this.mentionItems = [];
        this.mentionSelectedIndex = 0;
      });
  }

  // 清联想状态（发送/切会话/页面销毁调用；同时取消在途 debounce 避免泄内存与过期回调）
  private clearMention(): void {
    if (this.mentionDebounceId !== -1) {
      clearTimeout(this.mentionDebounceId);
      this.mentionDebounceId = -1;
    }
    this.mentionQueryId++;                                // 使在途请求结果失效
    this.mentionItems = [];
    this.mentionSelectedIndex = 0;
  }

  // 选中某文件：applySuggestion 把 '@...' 活动词替换为 '@filePath '（filePath 缺省回退 fullPath/fileName）。
  //   用 filePath（相对路径）而非 fullPath：agent 在工作目录运行，相对路径定位更准。
  private selectMention(item: FileSearchItem): void {
    const ref: string = item.filePath !== '' ? item.filePath
      : (item.fullPath !== '' ? item.fullPath : item.fileName);
    const applied = applySuggestion(this.inputText, this.inputCursorStart, this.inputCursorEnd,
      `@${ref}`, ['@'], true);
    this.inputText = applied.text;
    this.inputCursorStart = applied.cursorPosition;
    this.inputCursorEnd = applied.cursorPosition;
    this.clearMention();
    this.textAreaController.caretPosition(applied.cursorPosition);
  }

  // —— $ 技能联想（对照 web useSkills.getSuggestions + lib/recent-skills）——
  //   复用 ActiveWord 的 '$' 前缀分支（STOP_CHARACTERS 不含 '-'，$skill-name 不断词）：
  //   光标处回溯找 '$' 活动词，命中则用 serverSkills + recentSkills 评分（精确/前缀/包含/Levenshtein）取前 6。
  private recomputeSkill(): void {
    const aw = findActiveWord(this.inputText, this.inputCursorStart, this.inputCursorEnd, ['$']);
    if (aw === null || !aw.activeWord.startsWith('$')) {
      this.clearSkill();
      return;
    }
    const ranked: SkillItem[] = skillSuggestions(this.serverSkills, aw.activeWord, this.recentSkills);
    this.skillSuggestionItems = ranked.length > 6 ? ranked.slice(0, 6) : ranked;
    this.skillSelectedIndex = 0;
  }

  private clearSkill(): void {
    this.skillSuggestionItems = [];
    this.skillSelectedIndex = 0;
  }

  // 选中某技能：applySuggestion 把 '$...' 活动词替换为 '$name '；标记最近使用（本地 map 即时更新 + 异步落盘）。
  private selectSkill(skill: SkillItem): void {
    const applied = applySuggestion(this.inputText, this.inputCursorStart, this.inputCursorEnd,
      `$${skill.name}`, ['$'], true);
    this.inputText = applied.text;
    this.inputCursorStart = applied.cursorPosition;
    this.inputCursorEnd = applied.cursorPosition;
    this.clearSkill();
    this.textAreaController.caretPosition(applied.cursorPosition);
    // recency：本地即时置顶（再联想排序立即生效），异步落盘（失败静默不阻塞）
    this.recentSkills.set(skill.name, Date.now());
    markSkillUsed(skill.name, getPreferencesService()).catch((): void => {});
  }

  // —— 附件上传（对照 web client.ts uploadFile；数据流：picker 选 → 读 base64 → POST /upload → 入待发列）——
  //   非 multipart：上游收 JSON {filename, content: base64, mimeType}，返 path 回填 AttachmentMetadata。
  //   DecryptedMessage 不带 attachments 字段，故附件只在「待发区」chip 可见；发送后由 agent 服务端消费（协议忠实）。

  // 📎 按钮：一次选多个文件 → 逐个读 base64 → uploadFile → 成功入 pendingAttachments。
  //   单文件失败不阻断其余（toast 汇总 okCount/总数）；用户取消静默（picked 为空）。
  // 附件上传（拍照/照片/文件统一入口；AttachmentPickerPanel 已用系统 picker 选+读完，这里只 upload 入待发列）。
  //   单个失败跳过继续其余；全失败 toast；部分失败 toast ok/total。sessionId 空或空数组直接 return。
  private async uploadPickedFiles(picked: PickedFile[]): Promise<void> {
    if (this.sessionId === '' || picked.length === 0) { return; }
    this.isUploading = true;
    try {
      let okCount: number = 0;
      let lastError: string = '';
      for (let i = 0; i < picked.length; i++) {
        const pf: PickedFile = picked[i];
        const result = await getHubClient().uploadFile(this.sessionId, pf.filename, pf.base64Content, pf.mimeType);
        if (!result.success || result.path === '') {
          lastError = result.error !== '' ? result.error : t('chat.uploadFailed');
          continue;   // 单个失败跳过，继续其余
        }
        const meta: AttachmentMetadata = new AttachmentMetadata();
        meta.id = `att-${Date.now()}-${this.nextAttachmentSeq}`;
        this.nextAttachmentSeq += 1;
        meta.filename = pf.filename;
        meta.mimeType = pf.mimeType;
        meta.size = pf.size;
        meta.path = result.path;
        // 图片 <5MB：拼 data: URI 作 previewUrl（对照上游 attachmentAdapter.ts MAX_PREVIEW_BYTES=5MB），
        //   使「刚发的图」在历史里立即显缩略图（乐观 + 服务端回推均携带此 previewUrl）。非图片/过大留空 → 文件卡片。
        if (isImageMimeType(pf.mimeType) && pf.size < 5 * 1024 * 1024) {
          meta.previewUrl = `data:${pf.mimeType};base64,${pf.base64Content}`;
        }
        this.pendingAttachments = this.pendingAttachments.concat([meta]);
        okCount += 1;
      }
      if (okCount === 0) {
        showToast(lastError !== '' ? lastError : t('chat.uploadFailed'));
      } else if (okCount < picked.length) {
        showToast(t('chat.attachPartialFail', kv2('ok', okCount, 'total', picked.length)));
      }
    } catch (e) {
      showToast(t('chat.uploadFailed'));
    } finally {
      this.isUploading = false;
    }
  }

  // 移除待发附件：调 deleteUploadFile 清服务端临时文件 + 本地数组剔除（防残留占空间）。
  private async removeAttachment(meta: AttachmentMetadata): Promise<void> {
    this.pendingAttachments = this.pendingAttachments.filter((m: AttachmentMetadata): boolean => m.id !== meta.id);
    if (meta.path !== '') {
      try { await getHubClient().deleteUploadFile(this.sessionId, meta.path); } catch (e) { /* 删失败忽略，反正不入消息 */ }
    }
  }

  // 待发附件预览（对照 chatcube AttachmentPreview：水平 Scroll，置卡片内 InputBarRow 之上；
  //   空时不渲染。瓦片见 AttachmentTile——72×72，图片 data:URI 直显 / 文件 doc 图标+名，叠层删除键）。
  @Builder
  private AttachmentsBar() {
    if (this.pendingAttachments.length > 0) {
      Scroll() {
        Row() {
          ForEach(this.pendingAttachments, (meta: AttachmentMetadata) => {
            this.AttachmentTile(meta)
          }, (meta: AttachmentMetadata) => meta.id)
        }
        .justifyContent(FlexAlign.Start)
        .padding({ left: 8, right: 8, top: 8, bottom: 4 })
      }
      .width('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
    }
  }

  // 单个附件瓦片（对照 chatcube AttachmentItem：72×72 Stack，TopEnd 叠 18×18 半透黑删除键 margin-4 咬角）。
  //   图片(isImageMimeType && previewUrl 非空)→ Image data:URI r8 Cover；否则→ doc 图标+文件名 bg 块。
  @Builder
  private AttachmentTile(meta: AttachmentMetadata) {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (isImageMimeType(meta.mimeType) && meta.previewUrl !== '') {
        Image(meta.previewUrl)
          .width(72)
          .height(72)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .draggable(false)
      } else {
        Column() {
          SymbolGlyph(this.attachmentIcon(meta.mimeType))
            .fontSize(fs(22))
            .fontColor([this.c.textSecondary])
          Text(meta.filename)
            .fontSize(fs(10))
            .fontColor(this.c.textTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 58 })
            .margin({ top: 4 })
        }
        .width(72)
        .height(72)
        .borderRadius(8)
        .backgroundColor(this.c.bg)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      // 删除键（右上叠层，18×18 半透黑底白 ✕，margin-4 咬出瓦片角，对照 chatcube AttachmentItem:482-493）
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(fs(10))
          .fontColor([Color.White])
      }
      .width(18)
      .height(18)
      .backgroundColor('rgba(0, 0, 0, 0.6)')
      .margin({ top: -4, right: -4 })
      .onClick(() => { this.removeAttachment(meta); })
    }
    .width(72)
    .height(72)
    .margin({ right: 8 })
  }

  // 文件类型 → 符号字形（chip 左侧点缀；图片 gallery / pdf book / 其余 doc）。轻量视觉，无需精确。
  private attachmentIcon(mime: string): Resource {
    if (mime.startsWith('image/')) { return $r('sys.symbol.picture'); }
    if (mime === 'application/pdf') { return $r('sys.symbol.book'); }
    return $r('sys.symbol.doc');
  }

  // —— 会话内即时配置（对照 web setPermissionMode/setModel/...，5 端点）——
  //   每 tap 即发：乐观更新本地 @Local（overlay 立即高亮新值）→ 调 REST → 失败回滚 + toast。
  //   model/effort/reasoning '' 即发 null 复位（HubClient 内部转 null）。

  private async applyModel(model: string): Promise<void> {
    const prev = this.model;
    this.model = model;
    const ok = await getHubClient().setModel(this.sessionId, model);
    if (!ok) { this.model = prev; showToast(t('chat.setModelFailed')); }
  }
  private async applyPermissionMode(mode: string): Promise<void> {
    const prev = this.permissionMode;
    this.permissionMode = mode;
    const ok = await getHubClient().setPermissionMode(this.sessionId, mode);
    if (!ok) { this.permissionMode = prev; showToast(t('chat.setPermissionFailed')); }
  }
  private async applyCollaborationMode(mode: string): Promise<void> {
    const prev = this.collaborationMode;
    this.collaborationMode = mode;
    const ok = await getHubClient().setCollaborationMode(this.sessionId, mode);
    if (!ok) { this.collaborationMode = prev; showToast(t('chat.setCollaborationFailed')); }
  }
  private async applyEffort(effort: string): Promise<void> {
    const prev = this.effort;
    this.effort = effort;
    const ok = await getHubClient().setEffort(this.sessionId, effort);
    if (!ok) { this.effort = prev; showToast(t('chat.setEffortFailed')); }
  }
  private async applyReasoningEffort(effort: string): Promise<void> {
    const prev = this.modelReasoningEffort;
    this.modelReasoningEffort = effort;
    const ok = await getHubClient().setModelReasoningEffort(this.sessionId, effort);
    if (!ok) { this.modelReasoningEffort = prev; showToast(t('chat.setReasoningFailed')); }
  }

  // —— 消息长按菜单（复制 / 重发 / 分享）——
  // 长按 user/agent 气泡 → 底部动作 sheet（复用 SessionActionMenu 的 bindSheet 模式，零 API 风险；
  //   移动端主流长按交互，对照 chatcube MessageBubble 菜单 + 上游 copy/retry 语义）。

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
      .then((): void => { showToast(t('common.copySuccess')); })
      .catch((): void => { showToast(t('chat.copyFailed')); });
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
      showToast(t('chat.shareUnavailable'));
      return;
    }
    const ctx: common.UIAbilityContext = hostContext as common.UIAbilityContext;
    const r = await getShareService().shareText(ctx, text);
    if (!r.success) {
      showToast(t('chat.shareFailed'));
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
      showToast(t('chat.noMessagesToExport'));
      return;
    }
    const text: string = this.buildExportText();
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined || hostContext === null) {
      showToast(t('chat.shareUnavailable'));
      return;
    }
    const ctx: common.UIAbilityContext = hostContext as common.UIAbilityContext;
    const title: string = this.sessionTitle !== '' ? this.sessionTitle : t('chat.exportTitle');
    const r = await getShareService().shareText(ctx, text, title);
    if (!r.success) {
      showToast(t('chat.shareFailed'));
    }
  }

  // 拼导出纯文本：标题 + 逐块（跨日日期分隔行 + HH:mm 角色 + 正文）。
  //   - 工具调用（tool-call）/ 思考过程（reasoning）不导出（只导出 user/agent 对话，转录更干净）；
  //   - 日期分隔复用 block.dividerBefore（recomputeBlocks 盖戳，与屏幕 DateDivider 同款）+ formatDateDivider；
  //   - 无 markdown 语法（#/**/> 等），便于粘贴到任意纯文本目标。
  //   已知边角：若某新日首块恰好是被跳过的工具调用/思考过程，其 dividerBefore 分隔随之丢失（导出断档，屏幕正常）。
  private buildExportText(): string {
    const lines: string[] = [];
    const title: string = this.sessionTitle !== '' ? this.sessionTitle : t('chat.defaultTitle');
    lines.push(title);
    lines.push('');
    for (let i = 0; i < this.blocks.length; i++) {
      const b: ChatBlock = this.blocks[i];
      if (b.kind === 'tool-call' || b.kind === 'reasoning' || b.kind === 'generated-image' || b.kind === 'agent-event') {
        continue;   // 工具调用 / 思考过程 / 生成图片 / 系统事件不导出（只导出 user/agent 文本对话）
      }
      if (b.dividerBefore) {
        lines.push(`——— ${formatDateDivider(b.createdAt)} ———`);
        lines.push('');
      }
      const clock: string = b.createdAt > 0 ? formatClock(b.createdAt) : '--:--';
      lines.push(b.kind === 'user-text' ? t('chat.exportUser', kv('time', clock)) : t('chat.exportAssistant', kv('time', clock)));
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

  // 该 agent-text / cli-output 块是否「正在流式」：是当前最后一块 + 会话 thinking 中。
  //   reasoning 走 isReasoningStreaming；其余文本块（agent-text/cli-output）走本方法。
  //   决定 MarkdownText 的 isInputEnded / incrementalAnalysis：流式时增量重渲、结束时一次性最终解析。
  //   末块判定用 id 比较，避免依赖 ForEach 下标。
  private isBlockStreaming(b: ChatBlock): boolean {
    if (!this.isThinking) {
      return false;
    }
    const n: number = this.blocks.length;
    if (n === 0 || this.blocks[n - 1].id !== b.id) {
      return false;
    }
    return b.kind === 'agent-text' || b.kind === 'cli-output';
  }

  // 滚动控制（仅贴底时跟随，上滑读历史不打断，对照 chatcube alignToBottomIfPinned）
  private scrollToBottom(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 120);
  }

  // 初始滚动定锚：进会话按延迟数组排多次 scrollEdge（对照上游 HappyThread INITIAL_SCROLL_SETTLE_DELAYS_MS），
  //   抵消流式布局/图片加载导致的首帧高度抖动，确保真的贴底。用户上滑 → cancelSettling 放弃后续重试。
  private settleScrollToBottom(): void {
    this.cancelSettling();
    this.settlingCancelled = false;
    const delays: number[] = [0, 16, 50, 120, 250, 500, 900, 1400, 1800];
    for (let i = 0; i < delays.length; i++) {
      const id: number = setTimeout(() => {
        if (this.settlingCancelled) { return; }
        this.scroller.scrollEdge(Edge.Bottom);
      }, delays[i]);
      this.settlingTimerIds.push(id);
    }
  }

  private cancelSettling(): void {
    this.settlingCancelled = true;
    for (let i = 0; i < this.settlingTimerIds.length; i++) {
      clearTimeout(this.settlingTimerIds[i]);
    }
    this.settlingTimerIds = [];
  }

  private maybeScrollToBottom(): void {
    if (this.isPinnedToBottom) {
      this.scrollToBottom();
    }
  }

  // 是否存在「进入时未读」块（unreadDividerBefore 戳中至少一块）—— 决定进会话滚到首条未读 vs 滚底。
  private hasUnreadBlock(): boolean {
    for (let i = 0; i < this.blocks.length; i++) {
      if (this.blocks[i].unreadDividerBefore) { return true; }
    }
    return false;
  }

  // 滚到首条未读块（unreadDividerBefore 戳中的块；进会话定位用，此时非过滤态 → blocks 索引即 List 索引）。
  private scrollToFirstUnread(): void {
    let idx: number = -1;
    for (let i = 0; i < this.blocks.length; i++) {
      if (this.blocks[i].unreadDividerBefore) { idx = i; break; }
    }
    if (idx < 0) { return; }
    setTimeout((): void => { this.scroller.scrollToIndex(idx, false, ScrollAlign.START); }, 120);
  }

  // 「↓N条新消息」浮标点击：贴底 + 清计数 + 滚底。
  private jumpToBottomFromButton(): void {
    this.isPinnedToBottom = true;
    this.newMessagesCount = 0;
    this.scrollToBottom();
  }

  // 未读分隔线（首条未读块前；主色 dot + 文案，居中）。上游无对照，客户端自创。
  @Builder
  private UnreadDivider() {
    Row({ space: 6 }) {
      Column()
        .width(5)
        .height(5)
        .borderRadius(2.5)
        .backgroundColor(this.c.primary)
      Text(t('chat.unreadDivider'))
        .fontSize(fs(11))
        .fontColor(this.c.primary)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 8, bottom: 4 })
  }

  // 「↓N条新消息」浮标（贴底悬浮于列表上方；滚在上方时有新消息到达显形）。
  @Builder
  private NewMessagesButton() {
    Row({ space: 6 }) {
      Text('↓')
        .fontSize(fs(13))
        .fontColor(this.c.primary)
      Text(this.newMessagesCount > 0 ? t('chat.newMessages', kv('n', this.newMessagesCount)) : t('chat.newMessagesShort'))
        .fontSize(fs(13))
        .fontColor(this.c.primary)
        .fontWeight(FontWeight.Medium)
    }
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .borderRadius(18)
    .backgroundColor(this.c.bg)
    .border({ width: 1, color: this.c.primary })
    .margin({ bottom: 8 })
    .onClick(() => { this.jumpToBottomFromButton(); })
  }

  private statusText(s: string): string {
    if (s === 'sending') {
      return t('chat.statusSending');
    }
    if (s === 'queued') {
      return t('chat.statusQueued');
    }
    if (s === 'failed') {
      return t('chat.statusFailed');
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
          if (b.text !== '') {
            this.UserBubbleText(b.text)
          }
          if (b.attachments.length > 0) {
            this.AttachmentGrid(b.attachments, b.text !== '')
          }
          if (b.userOptimistic) {
            Text(this.statusText(b.userStatus))
              .fontSize(fs(10))
              .fontColor('rgba(255,255,255,0.75)')
              .margin({ top: 2 })
          }
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(b.userStatus === 'failed'
          ? this.c.error
          : (getChatSurfaceColorsState().userMessageBg || this.c.primary))
        .borderRadius({ topLeft: 16, topRight: 16, bottomLeft: 16, bottomRight: 4 })
        .constraintSize({ maxWidth: '78%' })
        .alignItems(HorizontalAlign.End)

        if (b.createdAt > 0) {
          Text(formatClock(b.createdAt))
            .fontSize(fs(10))
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

  // 用户气泡正文：抽前导指令（/slash·$skill）显成独立 chip，剩余 body 作正文（对照 web user-bubble.tsx
  //   UserBubbleContent）。鸿蒙简化为「chip 行（Flex wrap）+ 正文 Text」恒堆叠——上游 inline 模式
  //   （chip 与单行 body 同流换行）在 ArkUI 混排换行不稳，移动端堆叠更稳，视觉差异可忽略。
  // @Builder 内禁局部 const 声明（arkts 10905209：only UI component syntax），
  //   故把 extractLeadingDirectives 的两段结果拆成无状态 helper，Builder 内多次调用（用户气泡文本短，重复计算可接受）。
  private directivesOf(text: string): string[] {
    return extractLeadingDirectives(text).directives;
  }
  private bodyOf(text: string): string {
    return extractLeadingDirectives(text).body;
  }

  @Builder
  private UserBubbleText(text: string) {
    if (this.directivesOf(text).length > 0) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.directivesOf(text), (d: string) => {
          this.DirectiveChipPill(d)
        }, (d: string, idx: number) => `${d}@${idx}`)
      }
      .margin({ bottom: this.bodyOf(text) !== '' ? 6 : 0 })
    }
    if (this.bodyOf(text) !== '') {
      Text(this.bodyOf(text))
        .fontSize(fs(15))
        .fontColor(this.c.bubbleUserText)
    }
  }

  // 指令 chip（对照 web DirectiveChip）：wand_and_stars + label 的圆角 pill，半透明白叠在彩色气泡上（Palette 无
  //   chip 专用色，rgba(255,255,255,0.22) 在任意 userMessageBg 上皆成立；字色复用 bubbleUserText 白）。
  @Builder
  private DirectiveChipPill(value: string) {
    Row({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.wand_and_stars'))
        .fontSize(fs(12))
        .fontColor([this.c.bubbleUserText])
      Text(formatDirectiveLabel(value))
        .fontSize(fs(13))
        .fontColor(this.c.bubbleUserText)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
    .borderRadius(12)
    .backgroundColor('rgba(255,255,255,0.22)')
    .alignItems(VerticalAlign.Center)
    .margin({ right: 6, bottom: 6 })
  }

  // 用户附件渲染（对照 web MessageAttachments.tsx）：images（图片 && previewUrl 非空）→ FlexWrap 缩略图网格
  //   （点击 ImagePreviewSheet 放大）；files（其余）→ 文件卡片（图标 + 文件名 + 大小）。两组分开渲染。
  private imageAttachments(attachments: AttachmentMetadata[]): AttachmentMetadata[] {
    return attachments.filter((m: AttachmentMetadata): boolean => isImageMimeType(m.mimeType) && m.previewUrl !== '');
  }
  private fileAttachments(attachments: AttachmentMetadata[]): AttachmentMetadata[] {
    return attachments.filter((m: AttachmentMetadata): boolean => !isImageMimeType(m.mimeType) || m.previewUrl === '');
  }
  @Builder
  private AttachmentGrid(attachments: AttachmentMetadata[], hasText: boolean) {
    Column({ space: 6 }) {
      if (this.imageAttachments(attachments).length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.imageAttachments(attachments), (meta: AttachmentMetadata) => {
            Image(meta.previewUrl)
              .width(96)
              .height(96)
              .objectFit(ImageFit.Cover)
              .borderRadius(8)
              .draggable(false)
              .margin({ right: 6, bottom: 6 })
              .onClick(() => {
                this.attachmentPreviewSrc = meta.previewUrl;
                this.attachmentPreviewOpen = true;
              })
          }, (meta: AttachmentMetadata) => meta.id)
        }
        .width('100%')
      }
      if (this.fileAttachments(attachments).length > 0) {
        Column({ space: 4 }) {
          ForEach(this.fileAttachments(attachments), (meta: AttachmentMetadata) => {
            Row({ space: 8 }) {
              SymbolGlyph(this.attachmentIcon(meta.mimeType))
                .fontSize(fs(16))
                .fontColor([this.c.textTertiary])
              Column() {
                Text(meta.filename)
                  .fontSize(fs(13))
                  .fontColor(this.c.bubbleUserText)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(formatFileSize(meta.size))
                  .fontSize(fs(11))
                  .fontColor('rgba(255,255,255,0.75)')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .borderRadius(8)
            .backgroundColor('rgba(255,255,255,0.15)')
            .alignItems(VerticalAlign.Center)
          }, (meta: AttachmentMetadata) => meta.id)
        }
        .width('100%')
      }
    }
    .width('100%')
    .margin({ top: hasText ? 8 : 0 })
    .alignItems(HorizontalAlign.Start)
  }

  // agent 文本气泡（靠左、表面色，Markdown 渲染）+ 时间（HH:mm，气泡下方左对齐）+ 元数据脚注（可折叠）
  @Builder
  private AgentBubble(b: ChatBlock) {
    Row() {
      // 左簇：气泡 + 时间 + 脚注，整体左对齐（时间/脚注贴气泡左下）
      Column() {
        Column() {
          MarkdownText({
            content: b.text,
            linkFilePaths: true,
            // 流式末块：isInputEnded=false + incrementalAnalysis=true → CJMarkdown 增量重渲（防冻结根因）；
            //   结束翻转时 isInputEnded 变 true → 签名变 → 一次性最终完整解析（非 per-token，可接受）。
            isInputEnded: !this.isBlockStreaming(b),
            incrementalAnalysis: this.isBlockStreaming(b),
            onOpenFilePath: (path: string): void => { this.openFilePath(path); }
          })
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(this.c.surface)
        .borderRadius(16)
        // 满宽：与 ReasoningBubble/ToolCard 等左侧卡片宽度一致（旧 maxWidth:'85%' 导致 AI 回复比思考气泡窄、
        //   且长 Markdown 行/代码块超 85% 被 clip(true) 裁掉右边内容）。列表已有左右 12vp padding，满宽不贴边。
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .clip(true)

        if (b.createdAt > 0) {
          Text(formatClock(b.createdAt))
            .fontSize(fs(10))
            .fontColor(this.c.textTertiary)
            .margin({ top: 3, left: 2 })
        }

        // 元数据脚注开关（对照 web MessageMetadata toggle）：仅当有可显标签（Invoke/Model/Tier/Usage）时出现。
        if (this.metaForBlock(b).length > 0) {
          Text(this.expandedMeta.has(b.id) ? t('chat.hideInfo') : t('chat.showInfo'))
            .fontSize(fs(10))
            .fontColor(this.c.textTertiary)
            .margin({ top: 2, left: 2 })
            .onClick(() => {
              const s: Set<string> = new Set<string>(this.expandedMeta);
              if (s.has(b.id)) {
                s.delete(b.id);
              } else {
                s.add(b.id);
              }
              this.expandedMeta = s;
            })
        }

        // 展开后：脚注标签纵向堆叠（每条一行，三级文字色）。对照 web 一条 label 一项。
        if (this.expandedMeta.has(b.id)) {
          Column() {
            ForEach(this.metaForBlock(b), (label: string) => {
              Text(label)
                .fontSize(fs(10))
                .fontColor(this.c.textTertiary)
            }, (label: string) => label)
          }
          .margin({ top: 2, left: 2 })
          .alignItems(HorizontalAlign.Start)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    // priorityGesture（非 gesture）：让本气泡长按压过内嵌 MarkdownText(CJMarkdown) 的长按（文本选择），
    // 否则长按 agent 气泡会被 markdown 吞掉、不开菜单。仅同型手势竞争 → 不影响链接点按。
    .priorityGesture(LongPressGesture({ duration: 500, repeat: false })
      .onAction(() => { this.openMessageMenu(b); }))
  }

  // agent-text 气泡的元数据标签：model 用消息自身（b.model），缺失（REST 历史无 data.model）回退会话 model。
  private metaForBlock(b: ChatBlock): string[] {
    const effectiveModel: string = b.model !== '' ? b.model : this.model;
    return buildMessageMetadataLabels(b.invokedAt, b.durationMs, b.usage, effectiveModel);
  }

  // agent-event 系统消息条：text 与 icon token 分离（icon 由渲染侧 eventGlyph 映射 sys.symbol；icon 空→仅 text）。
  private eventLabel(b: ChatBlock): string {
    if (b.event === null) { return ''; }
    return getEventPresentation(b.event).text;
  }
  private eventIconName(b: ChatBlock): string {
    if (b.event === null) { return ''; }
    return getEventPresentation(b.event).icon;   // '' = 无图标
  }

  // 居中灰条系统消息（api-error / 用量限额 / 上下文压缩 等 agent 事件）。复用 DateDivider 居中 pill 样式。
  @Builder
  private EventMessageBar(b: ChatBlock) {
    Row() {
      Row({ space: 4 }) {
        if (this.eventIconName(b) !== '') {
          SymbolGlyph(eventGlyph(this.eventIconName(b)))
            .fontSize(fs(11))
            .fontColor([this.c.textTertiary])
        }
        Text(this.eventLabel(b))
          .fontSize(fs(11))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.textTertiary)
      }
      .padding({ left: 10, right: 10, top: 3, bottom: 3 })
      .backgroundColor(Color.Transparent)
      .borderRadius(8)
      .border({ width: 0.5, color: this.c.border })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 10, bottom: 6 })
  }

  // 空态：无消息且非生成中
  @Builder
  private EmptyState() {
    Column({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.message'))
        .fontSize(fs(40))
      Text(t('chat.emptyTitle'))
        .fontSize(fs(15))
        .fontColor(this.c.textPrimary)
      Text(t('chat.emptyHint'))
        .fontSize(fs(12))
        .fontColor(this.c.textTertiary)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  // 加载骨架屏：首屏拉消息中（isLoading 且尚无块）显形——对照上游 HappyThread MessageSkeleton
  @Builder
  private MessageSkeleton() {
    Column({ space: 10 }) {
      Row().width('60%').height(36).borderRadius(12).backgroundColor(this.c.surface).opacity(0.7)
      Row().width('75%').height(44).borderRadius(12).backgroundColor(this.c.surface).opacity(0.7)
      Row().width('45%').height(32).borderRadius(12).backgroundColor(this.c.surface).opacity(0.7)
      Row().width('83%').height(52).borderRadius(12).backgroundColor(this.c.surface).opacity(0.7)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 20, right: 20 })
  }

  // 生成中指示器（贴底，靠左；右附小停止键——排队混合方案：生成中发 send 键排队，停止移到此处）
  @Builder
  private TypingIndicator() {
    Row() {
      Text(t('chat.thinking'))
        .fontSize(fs(14))
        .fontColor(this.c.textTertiary)
        .padding({ left: 14, right: 14, top: 9, bottom: 9 })
        .backgroundColor(this.c.surface)
        .borderRadius(16)
      // 小停止键：isAborting 显 spinner，否则 stop 图标（与发 send 键空态 pause 同走 handleStop）
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        if (this.isAborting) {
          LoadingProgress().width(fs(14)).height(fs(14)).color(this.c.textSecondary)
        } else {
          SymbolGlyph($r('sys.symbol.stop_circle_fill'))
            .fontSize(fs(14))
            .fontColor([this.c.textSecondary])
        }
      }
      .width(32)
      .height(32)
      .backgroundColor(this.c.surface)
      .borderRadius(16)
      .margin({ left: 8 })
      .onClick(() => { this.handleStop(); })
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
  }

  // 顶部「加载更早消息」指示器（isLoadingOlder 时显示在列表上方）
  @Builder
  private LoadingOlderBar() {
    Row({ space: 6 }) {
      LoadingProgress().width(16).height(16).color(this.c.textTertiary)
      Text(t('chat.loadingOlder'))
        .fontSize(fs(12))
        .fontColor(this.c.textTertiary)
    }
    .width('100%')
    .height(28)
    .justifyContent(FlexAlign.Center)
  }

  // 发送键是否有可发内容（文本或待发附件；对照 chatcube computeHasContent）
  private composerHasContent(): boolean {
    return this.inputText.trim() !== '' || this.pendingAttachments.length > 0;
  }
  // 发送键图标（对照 chatcube getSendButtonSymbol + 排队混合方案）：
  //   生成中 + 有新内容 → paperplane_right_fill（点击=排队下一条，handleSend 不挡 isThinking）；
  //   生成中 + 无内容 → pause（点击=停止）；非生成中有内容 → 实心纸飞机；空 → 轮廓纸飞机。
  private sendSymbol(): Resource {
    if (this.isThinking) {
      return this.composerHasContent() ? $r('sys.symbol.paperplane_right_fill') : $r('sys.symbol.pause');
    }
    if (this.composerHasContent()) { return $r('sys.symbol.paperplane_right_fill'); }
    return $r('sys.symbol.paperplane');
  }
  // 发送键透明度（对照 chatcube getSendButtonOpacity：恒 1，仅 blocking 附件才 0.45；本项目无该态→恒 1）。
  private sendOpacity(): number { return 1; }

  // —— 发送键动效驱动（对照 chatcube ChatInputBar:651-753 的 @Monitor + 呼吸 + animateSendButton）——
  // @Monitor 回调若同步改 @Local（sendIconTrigger/breathOpacity/sendBtnScale），其变更会与 isThinking 翻转触发的
  //   那次 build 批进同一 render pass → ArkUI 报「New UINode added during re-render」（build 期改状态）。
  //   故整体延后到下一事件循环（setTimeout 0）：让 think 翻转的 build 先提交完，再改这些派生态 → 无 build 期争抢。
  @Monitor('isThinking')
  onThinkingChanged(): void {
    setTimeout((): void => {
      if (this.isDisposed) { return; }
      this.sendIconTrigger++;
      this.lastHasContent = this.composerHasContent();
      this.updateBreathing();
      this.animateSendButton();
    }, 0);
  }
  // 内容态翻转才 bump 触发器（省冗余变形；生成中 pause↔paperplane 切换亦由此驱动）+ 同步呼吸。
  @Monitor('inputText', 'pendingAttachments')
  onComposerContentChanged(): void {
    const hasContent = this.composerHasContent();
    this.updateBreathing();
    if (hasContent === this.lastHasContent) { return; }
    this.lastHasContent = hasContent;
    this.sendIconTrigger++;
  }
  @Monitor('attachmentPanelOpen')
  onAttachmentPanelOpenChanged(): void { this.attachIconTrigger++; }

  // 附件面板开合（硬复刻 chatcube openAttachmentPanel/closeAttachmentPanel：animateTo 驱动高度，
  //   非「声明式 .animation + 三目 height」——后者触发 ArkUI「动态高+绝对定位+clip 不绘制子内容」坑）。
  private toggleAttachmentPanel(): void {
    if (this.attachmentPanelOpen) { this.closeAttachmentPanel(); } else { this.openAttachmentPanel(); }
  }
  private openAttachmentPanel(): void {
    this.getUIContext().animateTo({ duration: 260, curve: Curve.FastOutSlowIn }, (): void => {
      this.attachmentPanelOpen = true;
      this.attachmentPanelHeightVp = this.attachPanelHeight;
    });
  }
  private closeAttachmentPanel(): void {
    this.getUIContext().animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, (): void => {
      this.attachmentPanelHeightVp = 0;
      this.attachmentPanelOpen = false;
    });
  }

  // 呼吸仅在「生成中且无新内容」(pause 态) 跑；内容出现或停止即停（对照 chatcube updateBreathing）。
  // ⚠️ 暂关呼吸动画：breathOpacity 是 ChatPage @Local、被 build 读 → setInterval 每 850ms 翻转它会【整体重建
  //   ChatPage】（全 List/bindSheet/InputBar 重算）→ 生成中持续卡顿、输入框布局被饿死撑大（用户报告症状）。
  //   chatcube 里 InputBar 是独立子组件、呼吸只重建按钮；本页 InputBar 是内联 @Builder、无此隔离。
  //   正解后续：把 InputBar 抽成独立 @ComponentV2 子组件、breathOpacity 下沉其内部 → 仅按钮重渲。届时再开呼吸。
  private updateBreathing(): void {
    this.breathOpacity = 1;   // 恒不透明（呼吸关停）；保留方法以免动 onThinkingChanged/aboutToAppear 调用点
  }
  private startBreathing(): void {
    this.breathOpacity = 1;   // 呼吸关停：不启 setInterval（避全页 850ms 重建风暴）
  }
  private stopBreathing(): void {
    if (this.breatheTimerId >= 0) { clearInterval(this.breatheTimerId); this.breatheTimerId = -1; }
    this.breathOpacity = 1;
  }
  // 发送键状态切换弹跳（isThinking 起 0.9 回弹到 1，对照 chatcube animateSendButton）。
  private animateSendButton(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
      this.sendBtnScale = this.isThinking ? 0.9 : 1;
    });
  }

  // 输入栏（chatcube 同款：ComposerToolbar 工具条 + 附件面板 + 圆角卡片[模型键|TextArea|定时|+|发送]）
  @Builder
  private InputBar() {
    Column({ space: 4 }) {
      // 工具条（旧顶部 StatusBar 全部状态下沉：状态点 + 思考强度 chip + 权限 chip + codex fast/goal/collab）
      ComposerToolbar({
        isThinking: this.isThinking,
        agentState: this.agentState,
        permissionMode: this.permissionMode,
        collaborationMode: this.collaborationMode,
        modelReasoningEffort: this.modelReasoningEffort,
        model: this.model,
        flavor: this.flavor,
        effort: this.effort,
        threadGoal: this.threadGoal,
        onSetEffort: (e: string): void => { this.applyEffort(e); },
        onSetReasoningEffort: (e: string): void => { this.applyReasoningEffort(e); },
        onOpenConfig: (): void => { this.configSheetOpen = true; }
      })

      // 斜杠补全浮层（输入 / 触发；挂输入行正上方，对照 web 建议列表）
      if (this.slashSuggestions.length > 0) {
        SlashMenu({
          suggestions: this.slashSuggestions,
          selectedIndex: this.slashSelectedIndex,
          onSelect: (cmd: SlashCommand): void => { this.selectSlash(cmd); }
        })
      }
      // @ 文件提及联想浮层（输入 @ 触发；与斜杠浮层互斥——一次只可能有一个前缀活动词）
      if (this.mentionItems.length > 0) {
        MentionMenu({
          items: this.mentionItems,
          selectedIndex: this.mentionSelectedIndex,
          onSelect: (item: FileSearchItem): void => { this.selectMention(item); }
        })
      }
      // $ 技能联想浮层（输入 $ 触发；与斜杠/@ 浮层互斥——一次只可能有一个前缀活动词）
      if (this.skillSuggestionItems.length > 0) {
        SkillsMenu({
          items: this.skillSuggestionItems,
          selectedIndex: this.skillSelectedIndex,
          onSelect: (skill: SkillItem): void => { this.selectSkill(skill); }
        })
      }
      // —— 输入卡片 + 附件面板（chatcube ChatPage:2685-2718 视觉复刻：panel 叠在 card 底 padding 留白条上）。
      //    根因：chatcube 用 position({y:'100%'}).translate({y:'-100%'}) 绝对底锚——但 ArkUI 中「绝对定位 + 百分比
      //    偏移」的子节点不参与测量、不绘制内容（dumpLayout 节点消失 + 截图空白双证）。chatcube 可用因其 card+panel
      //    同锚「全屏父容器」；本项目页根是 Column（非全屏 Stack），绝对底锚失效。改用 Stack({alignContent:Bottom})
      //    叠层：Stack 正常测量并绘制子节点（card 底层 + panel 顶层贴底），高=attachmentPanelHeightVp 由 animateTo
      //    驱动，覆盖 card 底 padding 留白条——视觉/动效与 chatcube 一致（面板上滑覆盖、输入行随卡片整体抬升）。
      Stack({ alignContent: Alignment.Bottom }) {
        // 卡片本体（对照 chatcube ChatInputBar.build：r24 + blur COMPONENT_REGULAR + 0.5vp 边框 + shadow32）
        Column() {
          // 待发附件瓦片栏（置卡片内 InputBarRow 之上，对照 chatcube AttachmentPreview；空时不渲染）
          this.AttachmentsBar()
          Row() {
            // 模型键（最左 40×40 圆；对照 chatcube ModelButton：model!==''→28×28 r7 盒 ai_edit；model===''→裸 ai_edit 22px；onClick 开模型+权限同一 sheet）
            Button({ type: ButtonType.Circle, stateEffect: false }) {
              if (this.model !== '') {
                Column() {
                  SymbolGlyph($r('sys.symbol.ai_edit'))
                    .fontSize(fs(14))
                    .fontColor([this.c.textTertiary])
                }
                .width(28)
                .height(28)
                .borderRadius(7)
                .backgroundColor(this.c.surfaceSelected)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
              } else {
                SymbolGlyph($r('sys.symbol.ai_edit'))
                  .fontSize(fs(22))
                  .fontColor([this.c.textSecondary])
              }
            }
            .width(40)
            .height(40)
            .backgroundColor(this.modelBtnPressed ? this.c.surfaceSelected : Color.Transparent)
            .scale({ x: this.modelBtnPressed ? 0.95 : 1, y: this.modelBtnPressed ? 0.95 : 1 })
            .animation({ duration: 150, curve: Curve.EaseOut })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) { this.modelBtnPressed = true; }
              else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.modelBtnPressed = false; }
            })
            .onClick(() => { this.configSheetOpen = true; })

            // 多行输入（透明底撑满；聚焦即收起附件面板，对照 chatcube onInputFocus）
            TextArea({ text: this.inputText, placeholder: t('chat.inputPlaceholder'), controller: this.textAreaController })
              .id('chatInputTextArea')
              .layoutWeight(1)
              .fontSize(fs(16))
              .fontColor(this.c.textPrimary)
              .placeholderColor(this.c.textTertiary)
              .placeholderFont({ size: fs(16) })
              .enterKeyType(this.enterToSend ? EnterKeyType.Send : EnterKeyType.NEW_LINE)
              .constraintSize({ minHeight: 40, maxHeight: 120 })
              .backgroundColor(Color.Transparent)
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .onChange((v: string) => {
                this.inputText = v;
                this.scheduleSuggestionRecompute();
                this.scheduleDraftSave();
              })
              .onSubmit(() => {
                // 回车发送（对照 chatcube InputTextArea.onSubmit）：enterToSend 开 → 键盘「发送」键触发。
                //   协议不变——handleSend 自守 isSending；不拦 isThinking 故生成中回车=排队发送(与发送键一致)。
                //   副作用：粘贴尾随换行不再自动发送(Send 键不插 \n)，与 chatcube 一致。
                if (this.enterToSend && !this.isSending && this.composerHasContent()) {
                  this.handleSend();
                }
              })
              .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
                this.inputCursorStart = selectionStart;
                this.inputCursorEnd = selectionEnd;
                this.scheduleSuggestionRecompute();
              })
              .onFocus(() => { this.closeAttachmentPanel(); })

            // 定时键（40×40；开 ScheduleSheet 选预设；已设定时显警告色）
            Button({ type: ButtonType.Circle, stateEffect: false }) {
              SymbolGlyph($r('sys.symbol.clock'))
                .fontSize(fs(18))
                .fontColor([this.pendingSchedule > 0 ? this.c.warning : this.c.textSecondary])
            }
            .width(40)
            .height(40)
            .backgroundColor(Color.Transparent)
            .onClick(() => { this.scheduleSheetOpen = true; })

            // 附件「+」键（40×40；plus↔xmark 变形；上传中显 spinner）
            Button({ type: ButtonType.Circle, stateEffect: false }) {
              if (this.isUploading) {
                LoadingProgress().width(fs(18)).height(fs(18)).color(this.c.textSecondary)
              } else {
                SymbolGlyph(this.attachmentPanelOpen ? $r('sys.symbol.xmark') : $r('sys.symbol.plus'))
                  .fontSize(fs(20))
                  .fontColor([this.c.textSecondary])
                  .symbolEffect(new ReplaceSymbolEffect(EffectScope.WHOLE), this.attachIconTrigger)
              }
            }
            .width(40)
            .height(40)
            .backgroundColor(Color.Transparent)
            .onClick(() => { this.toggleAttachmentPanel(); })

            // 发送键（对照 chatcube SendButton：ReplaceSymbolEffect 变形 + pause 呼吸 + 按下态阴影/缩放 + 品牌色调阴影）
            Button({ type: ButtonType.Circle, stateEffect: false }) {
              SymbolGlyph(this.sendSymbol())
                .fontSize(this.isThinking ? fs(20) : fs(22))
                .fontColor([this.c.bubbleUserText])
                .symbolEffect(new ReplaceSymbolEffect(EffectScope.WHOLE), this.sendIconTrigger)
                .opacity(this.breathOpacity)
                .animation({ duration: 850, curve: Curve.EaseInOut })
            }
            .width(40)
            .height(40)
            .backgroundColor(this.c.primary)
            .opacity(this.sendOpacity())
            .shadow({
              radius: this.sendBtnPressed ? 24 : 16,
              color: this.withAlpha(this.c.primary, this.sendBtnPressed ? '66' : '40'),
              offsetX: 0,
              offsetY: this.sendBtnPressed ? 6 : 4
            })
            .scale({
              x: this.sendBtnPressed ? 0.95 * this.sendBtnScale : this.sendBtnScale,
              y: this.sendBtnPressed ? 0.95 * this.sendBtnScale : this.sendBtnScale
            })
            .animation({ duration: 200, curve: Curve.EaseInOut })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) { this.sendBtnPressed = true; }
              else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.sendBtnPressed = false; }
            })
            .onClick(() => {
              // 排队混合：生成中 + 有新内容 → 排队发送（handleSend 不挡 isThinking）；生成中 + 空 → 停止；否则有内容才发。
              if (this.isThinking) {
                if (this.composerHasContent()) { this.handleSend(); } else { this.handleStop(); }
                return;
              }
              if (this.composerHasContent()) { this.handleSend(); }
            })
          }
          .width('100%')
          .padding({ left: 6, right: 6, top: 6, bottom: 6 })
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .borderRadius(24)
        .backgroundColor(this.c.surface)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .border({ width: 0.5, color: this.c.border })
        .shadow({ radius: 32, color: 'rgba(0,0,0,0.1)', offsetX: 0, offsetY: 8 })
        // chatcube 抬升：底 padding=attachmentPanelHeightVp，面板开时卡片内容随 InputBar 上移、底部留出覆盖区。
        .padding({ bottom: this.attachmentPanelHeightVp })
        .animation({ duration: 260, curve: Curve.FastOutSlowIn })

        // 附件面板（Stack 顶层、alignContent.Bottom 贴底：高=attachmentPanelHeightVp 由 animateTo 驱动，clip 随高揭示；
        //   覆盖 card 底 padding 留白条。弃 position/translate 绝对底锚——ArkUI 不绘制其内容）。
        Column() {
          AttachmentPickerPanel({
            onSelect: (picked: PickedFile[]): void => { this.uploadPickedFiles(picked); },
            onClose: (): void => { this.closeAttachmentPanel(); }
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .height(this.attachmentPanelHeightVp)
        .opacity(this.attachmentPanelOpen ? 1 : 0)
        .backgroundColor(this.c.surface)
        .clip(true)
        .enabled(this.attachmentPanelOpen)
        .animation({ duration: 260, curve: Curve.FastOutSlowIn })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
    .backgroundColor(this.c.bg)
  }

  // 定时选择 sheet（对照 web ScheduleTimePicker 预设：+5m/+30m/+1h/+4h；MVP 仅预设，绝对时间后续加）
  @Builder
  private scheduleOption(label: string, offsetMs: number) {
    Row() {
      Text(label)
        .fontSize(fs(15))
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
      Text(t('chat.scheduleSend'))
        .fontSize(fs(16))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.textPrimary)
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 4 })

      if (this.scheduleCustomMode) {
        // 自定义绝对时间分支：DatePicker 选日期（限定 [now, now+7d]，对齐上游 refine 上限）+ TimePicker 选时分
        DatePicker({
          start: new Date(),
          end: new Date(Date.now() + 7 * 24 * 3600 * 1000),
          selected: this.pickDate
        })
          .selectedTextStyle({ color: this.c.textPrimary, font: { size: 18, weight: FontWeight.Medium } })
          .textStyle({ color: this.c.textTertiary, font: { size: 16, weight: FontWeight.Regular } })
          .onDateChange((value: Date) => { this.pickDate = value; })

        TimePicker({ selected: this.pickDate })
          .selectedTextStyle({ color: this.c.textPrimary, font: { size: 18, weight: FontWeight.Medium } })
          .textStyle({ color: this.c.textTertiary, font: { size: 16, weight: FontWeight.Regular } })
          .onChange((value: TimePickerResult) => {
            this.pickHour = value.hour;
            this.pickMinute = value.minute;
          })

        // 当前合成时间预览（用 pendingSchedule 同款格式）
        Text(this.customSchedulePreview())
          .fontSize(fs(12))
          .fontColor(this.c.textTertiary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 4, bottom: 8 })

        Row({ space: 12 }) {
          Button(t('common.back'))
            .layoutWeight(1)
            .height(42)
            .backgroundColor(this.c.surface)
            .fontColor(this.c.textPrimary)
            .onClick(() => { this.scheduleCustomMode = false; })
          Button(t('common.confirm'))
            .layoutWeight(1)
            .height(42)
            .backgroundColor(this.c.primary)
            .fontColor(this.c.bubbleUserText)
            .onClick(() => { this.confirmCustomSchedule(); })
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 16 })
      } else {
        // 预设分支（对照 web ScheduleTimePicker：+5m/+30m/+1h/+4h）
        this.scheduleOption(t('chat.scheduleIn5m'), 5 * 60 * 1000)
        this.scheduleOption(t('chat.scheduleIn30m'), 30 * 60 * 1000)
        this.scheduleOption(t('chat.scheduleIn1h'), 60 * 60 * 1000)
        this.scheduleOption(t('chat.scheduleIn4h'), 4 * 60 * 60 * 1000)

        // 进自定义绝对时间分支（DatePicker+TimePicker）
        Row() {
          Text(t('chat.scheduleCustom'))
            .fontSize(fs(15))
            .fontColor(this.c.primary)
            .layoutWeight(1)
          Text('›')
            .fontSize(fs(18))
            .fontColor(this.c.textTertiary)
        }
        .width('100%')
        .height(48)
        .padding({ left: 20, right: 20 })
        .onClick(() => { this.openCustomSchedule(); })

        if (this.pendingSchedule > 0) {
          Row() {
            Text(t('chat.scheduleClear'))
              .fontSize(fs(15))
              .fontColor(this.c.error)
              .layoutWeight(1)
          }
          .width('100%')
          .height(48)
          .padding({ left: 20, right: 20 })
          .onClick(() => { this.clearSchedule(); })
        }
      }
    }
    .width('100%')
    .backgroundColor(this.c.bg)
  }

  // 自定义定时预览文案：合成 Y/M/D + H:m + 相对描述（clamp 前的原值；confirmCustomSchedule 再 clamp）。
  private customSchedulePreview(): string {
    const d: Date = new Date(this.pickDate.getTime());
    d.setHours(this.pickHour, this.pickMinute, 0, 0);
    const hh: string = this.pickHour < 10 ? `0${this.pickHour}` : `${this.pickHour}`;
    const mm: string = this.pickMinute < 10 ? `0${this.pickMinute}` : `${this.pickMinute}`;
    const absPart: string = t('chat.scheduleAbsTime', kv4('m', d.getMonth() + 1, 'd', d.getDate(), 'hh', hh, 'mm', mm));
    const relPart: string = formatScheduledIn(d.getTime(), Date.now());
    return `${absPart}（${relPart}）`;
  }

  // 会话配置 sheet（包 SessionConfigOverlay；当前值/回调全接本页 @Local 与 applyXxx）
  @Builder
  private ConfigSheet() {
    SessionConfigOverlay({
      sessionId: this.sessionId,
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

  // 对话大纲 sheet（包 OutlinePanel；items 由 recomputeBlocks 维护，tap 调 jumpToOutline）
  @Builder
  private OutlineSheet() {
    OutlinePanel({
      items: this.outlineItems,
      onJump: (blockId: string): void => { this.jumpToOutline(blockId); }
    })
  }

  // 重命名 sheet（⋯ 下拉「重命名」开；TextInput 预填当前标题 + 取消/保存，镜像 SessionActionMenu RenameSheet）
  @Builder
  private RenameSheet() {
    Column() {
      TextInput({ text: this.renameText, placeholder: t('sessionMenu.sessionNamePlaceholder'), controller: this.renameInputController })
        .fontSize(fs(16))
        .fontColor(this.c.textPrimary)
        .placeholderColor(this.c.textTertiary)
        .backgroundColor(this.c.surface)
        .borderRadius(12)
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .maxLength(255)
        .defaultFocus(true)
        .onChange((v: string) => { this.renameText = v; })
        .onSubmit(() => { this.confirmRename(); })

      Row({ space: 10 }) {
        Button(t('common.cancel'))
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.c.surface)
          .fontColor(this.c.textPrimary)
          .borderRadius(12)
          .onClick(() => { this.closeRename(); })
        Button(this.renameActing ? t('sessionMenu.saving') : t('sessionMenu.save'))
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.c.primary)
          .fontColor(this.c.bubbleUserText)
          .borderRadius(12)
          .enabled(!this.renameActing && this.renameText.trim().length > 0)
          .onClick(() => { this.confirmRename(); })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 20 })
    .backgroundColor(this.c.bg)
  }

  // 大纲跳转：在 filteredBlocks 内查 blockId 的 index → scrollToIndex(START) → 关抽屉。
  //   LazyForEach 数据源镜像 filteredBlocks → 索引一致；目标必在数组内（大纲即从 blocks 派生），无需上游 load-older 翻页循环。
  private jumpToOutline(blockId: string): void {
    const list: ChatBlock[] = this.filteredBlocks;
    let idx: number = -1;
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === blockId) { idx = i; break; }
    }
    this.outlineOpen = false;
    if (idx < 0) { return; }   // 理论不发生（大纲源于 blocks）；防御性静默
    // 延迟一帧等抽屉关闭动画后再滚，避免 sheet 仍在时滚动被遮挡
    setTimeout((): void => { this.scroller.scrollToIndex(idx, true, ScrollAlign.START); }, 120);
  }

  // 液态顶栏（hideTitleBar 后自建，复刻 VoicePage 自建栏模式）。
  //   全宽毛玻璃片（COMPONENT_ULTRA_THICK + 半透明 surface 底 + 底部发丝线）+ 液态圆钮。
  //   左返回(导航) + 标题列(flavor 徽章 + 标题/副标题) + 搜索/⋯ 两液态 chip（3→2 瘦身：config 收进 ⋯）。
  @Builder
  private ChatTopBar() {
    Row({ space: 8 }) {
      // 返回（液态圆钮；hideTitleBar 去掉系统返回，必须有。附件面板开时先收面板）
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_backward'))
          .fontSize(fs(18))
          .fontColor([this.c.textPrimary])
      }
      .width(36)
      .height(36)
      .backgroundColor(this.glassBg())
      .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
      .border({ width: 1, color: this.glassBorderInactive() })
      .shadow({ radius: 10, color: this.glassShadow(), offsetX: 0, offsetY: 2 })
      .onClick(() => {
        if (this.attachmentPanelOpen) { this.closeAttachmentPanel(); return; }
        if (this.navPathStack !== null) { this.navPathStack.pop(); }
      })

      // 标题列（flavor 徽章 + 标题 + 副标题；layoutWeight 占满，标题 ellipsis）
      Row({ space: 6 }) {
        Text(flavorLabel(this.flavor))
          .fontSize(fs(9)).fontWeight(FontWeight.Medium).fontColor('#ffffff')
          .backgroundColor(flavorColorHex(this.flavor))
          .borderRadius(2)
          .width(fs(18)).height(fs(18))
          .textAlign(TextAlign.Center)
          .maxLines(1)
        Column() {
          Text(this.sessionTitle !== '' ? this.sessionTitle : t('chat.defaultTitle'))
            .fontSize(fs(16)).fontWeight(FontWeight.Medium).fontColor(this.c.textPrimary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.chatSubtitle !== '') {
            Text(this.chatSubtitle)
              .fontSize(fs(11)).fontColor(this.c.textSecondary)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 1 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)

      // 搜索（液态 chip；searchMode 时 primary 描边高亮 + xmark）
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        SymbolGlyph(this.searchMode ? $r('sys.symbol.xmark') : $r('sys.symbol.magnifyingglass'))
          .fontSize(fs(18))
          .fontColor([this.searchMode ? this.c.primary : this.c.textSecondary])
      }
      .width(36)
      .height(36)
      .backgroundColor(this.glassBg())
      .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
      .border({ width: 1, color: this.searchMode ? this.c.primary : this.glassBorderInactive() })
      .shadow({ radius: 10, color: this.glassShadow(), offsetX: 0, offsetY: 2 })
      .animation({ duration: 200, curve: Curve.EaseOut })
      .onClick(() => { this.toggleSearch(); })

      // ⋯ 下拉（液态 chip + bindMenu frosted 气泡；替换原 SessionActionMenu 底部 sheet）
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.ellipsis_message'))
          .fontSize(fs(18))
          .fontColor([this.c.textSecondary])
      }
      .width(36)
      .height(36)
      .backgroundColor(this.glassBg())
      .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
      .border({ width: 1, color: this.glassBorderInactive() })
      .shadow({ radius: 10, color: this.glassShadow(), offsetX: 0, offsetY: 2 })
      .bindMenu(this.ChatTopMenu(), {
        placement: Placement.BottomRight,
        offset: { x: 0, y: 8 },
        backgroundColor: this.c.surface,
        backgroundBlurStyle: BlurStyle.Regular
      })
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .backgroundColor(this.glassBg())
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK, { scale: 0.5 })
    .border({ width: { bottom: 0.5 }, color: this.glassBorderInactive() })
  }

  // ⋯ 下拉菜单（替换 SessionActionMenu sheet）。Menu/MenuItem 形态镜像 ComposerToolbar ThinkingMenu；
  //   active 门控（终端/语音/切换远程仅活跃；归档↔删除二选一）。
  @Builder
  private ChatTopMenu() {
    Menu() {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.gearshape')).fontSize(16), content: t('chat.config') })
        .contentFont({ size: fs(14) })
        .onClick(() => { this.configSheetOpen = true; })
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.folder')).fontSize(16), content: t('sessionMenu.files') })
        .contentFont({ size: fs(14) })
        .onClick(() => { this.openFiles(); })
      if (this.isActive) {
        MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.keyboard')).fontSize(16), content: t('sessionMenu.terminal') })
          .contentFont({ size: fs(14) })
          .onClick(() => { this.openTerminal(); })
        MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.mic')).fontSize(16), content: t('sessionMenu.voice') })
          .contentFont({ size: fs(14) })
          .onClick(() => { this.openVoice(); })
      }
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.share')).fontSize(16), content: t('chat.exportTitle') })
        .contentFont({ size: fs(14) })
        .onClick(() => { this.exportConversation(); })
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.list_bullet')).fontSize(16), content: t('outline.title') })
        .contentFont({ size: fs(14) })
        .onClick(() => { this.outlineOpen = true; })
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')).fontSize(16), content: t('sessionMenu.rename') })
        .contentFont({ size: fs(14) })
        .onClick(() => { this.startRename(); })
      if (this.isActive) {
        MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.swap')).fontSize(16), content: t('sessionMenu.switchRemote') })
          .contentFont({ size: fs(14) })
          .onClick(() => { this.startSwitchRemote(); })
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier(this.isActive ? $r('sys.symbol.archivebox') : $r('sys.symbol.trash')).fontSize(16),
        content: this.isActive ? t('sessionMenu.archive') : t('sessionMenu.delete')
      })
        .contentFont({ size: fs(14) })
        .contentFontColor(this.c.error)
        .onClick(() => { this.onDestructiveTap(); })
    }
  }

  // 对话内搜索栏（对照 Index 顶栏 Search 组件：内置 ✕ 仅清文本；标题栏 🔍/✕ 切整栏显隐）
  //   过滤中显示「N 个匹配」（0 命中即「0 个匹配」=空反馈，无需另设空态分支）。
  @Builder
  private SearchBar() {
    Column({ space: 4 }) {
      Search({ value: this.searchQuery, placeholder: t('chat.searchPlaceholder') })
        .height(40)
        .backgroundColor(this.c.surface)
        .placeholderColor(this.c.textTertiary)
        .onChange((value: string) => { this.searchQuery = value; })
      if (this.isFiltering()) {
        Text(t('chat.searchMatches', kv('n', this.filteredBlocks.length)))
          .fontSize(fs(12))
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
        Text(t('common.copy')).fontSize(fs(16)).fontColor(this.c.textPrimary).layoutWeight(1)
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
          Text(t('chat.resend')).fontSize(fs(16)).fontColor(this.c.textPrimary).layoutWeight(1)
        }
        .width('100%')
        .height(52)
        .padding({ left: 20, right: 20 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => { this.retryMessageMenu(); })

        Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 20, right: 20 })
      }

      Row() {
        Text(t('chat.share')).fontSize(fs(16)).fontColor(this.c.textPrimary).layoutWeight(1)
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
        // 液态顶栏（hideTitleBar 后自建，顶栏首位）
        this.ChatTopBar()
        // 连接状态横幅（SSE 重连/断开时显形；常态 Visibility.None 不占位）
        ConnectionBanner()
        // 前台重同步横幅（切后台 >30s 回前台 beginSync；resyncSeq++ 触发 loadMessages，完成后 endSync）
        SyncingBanner()
        if (this.isLoading && this.messages.length === 0) {
          Column() {
            LoadingProgress().width(36).height(36).color(this.c.primary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.loadError !== '' && this.messages.length === 0) {
          Column({ space: 10 }) {
            Text(t('chat.loadFailed')).fontSize(fs(15)).fontColor(this.c.error)
            Text(this.loadError).fontSize(fs(12)).fontColor(this.c.textTertiary).textAlign(TextAlign.Center)
            Button(t('common.retry'))
              .fontSize(fs(13))
              .backgroundColor(this.c.primary)
              .fontColor(this.c.bubbleUserText)
              .onClick(() => this.loadMessages())
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.isLoading && this.blocks.length === 0) {
          this.MessageSkeleton()
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
            // Stack 包 List 以悬浮「新消息」浮标（alignContent 底部居中；浮标在 newMessagesCount>0 时显形）
            Stack({ alignContent: Alignment.Bottom }) {
            List({ scroller: this.scroller, space: 8 }) {
              // LazyForEach + IDataSource（对照 chatcube ChatMessageListSection：流式根治）。
              //   曾试 Repeat(filteredBlocks)+@Trace+内联 @Builder：think 渲染时触发 ArkUI「UINode added during
              //   re-render」冲突（Repeat 同 key 项管理与 @Trace 精确刷新争抢 item 所有权）→ JS 线程冻结、SSE 不进。
              //   LazyForEach 由 dataSource 的 onDataChange(index) 显式通知单项重生成——不依赖 @Trace、无所有权冲突。
              //   生成器重跑时 ArkUI 按 key 复用 ListItem、对同位同型子组件（MarkdownText 等 @ComponentV2）按 @Param
              //   增量更新而非重建 → CJMarkdown 保活（其内 ForEach 签名不含 content）→ 仅 content 更新 → 流式逐字实时增长、无冻结。
              //   key 恒用稳定 b.id（同 key 复用 ListItem、不重建）。
              LazyForEach(this.dataSource, (b: ChatBlock) => {
                  ListItem() {
                    Column() {
                      // 跨日（或首条）日期分隔（dividerBefore 由 recomputeBlocks 盖戳）；
                      //   过滤视图是非连续子集，分隔会误导 → 实际过滤时（非空查询）不显示。
                      if (b.dividerBefore && !this.isFiltering()) {
                        DateDivider({ timestamp: b.createdAt })
                      }
                      // 未读分隔（首条 createdAt>entryLastSeenAt 的块前；上游无对照，客户端自创）
                      if (b.unreadDividerBefore && !this.isFiltering()) {
                        this.UnreadDivider()
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
                      } else if (b.kind === 'generated-image') {
                        GeneratedImageCard({
                          block: b,
                          sessionId: this.sessionId
                        })
                      } else if (b.kind === 'cli-output') {
                        CliOutputCard({
                          block: b
                        })
                      } else if (b.kind === 'codex-review' && b.review !== null) {
                        CodexReviewCard({
                          review: b.review
                        })
                      } else if (b.kind === 'agent-event' && b.event !== null) {
                        this.EventMessageBar(b)
                      } else if (b.kind === 'tool-group') {
                        // 连发同质工具折叠卡（对照 web ToolGroupBlock）：头部 + 展开行 + 行详情 sheet。
                        //   纯展示（分组内工具恒非待批），无需 sessionId/flavor/nowTick/onDecided。
                        ToolGroupCard({ block: b })
                      } else {
                        ToolCard({
                          block: b,
                          sessionId: this.sessionId,
                          flavor: this.flavor,
                          nowTick: this.isRunningBlock(b) ? this.nowTick : 0,
                          actionState: this.toolActionStateOf(b.id),
                          detailOpenInit: this.detailOpenSigs[b.id] !== undefined,
                          onAction: (kind: string): void => { this.handleToolAction(b, kind); },
                          onDetailOpenChange: (open: boolean): void => { this.toggleToolDetail(b.id, open); }
                        })
                      }
                    }
                  }
                }, (b: ChatBlock): string => b.id)

              if (this.isThinking) {
                ListItem() {
                  this.TypingIndicator()
                }
              }
            }
            .width('100%')
            .height('100%')
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
              // 用户手动滚到底 → 清新消息浮标计数
              if (this.isPinnedToBottom) {
                this.newMessagesCount = 0;
              } else if (!this.settlingCancelled) {
                // 用户上滑读历史 → 放弃初始滚动定锚重试（对照上游 shouldCancelInitialScrollSettling）
                this.cancelSettling();
              }
            })

            if (this.newMessagesCount > 0) {
              this.NewMessagesButton()
            }
            }
            .width('100%')
            .layoutWeight(1)
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
          onDisappear: (): void => { this.scheduleSheetOpen = false; this.scheduleCustomMode = false; }
        })

        // 用户气泡图片全屏预览（自带 bindSheet + 双指缩放，复用 markdown/生成图片同款；open=false 不渲染）
        ImagePreviewSheet({
          src: this.attachmentPreviewSrc,
          open: this.attachmentPreviewOpen,
          onClose: (): void => { this.attachmentPreviewOpen = false; }
        })
      // 三 sheet 各占独立 0×0 锚点节点（延续 SessionActionMenu/Index 双节点模式：
      //   同一节点叠多个 bindSheet 仅其中一个生效，致配置/消息菜单不开；锚点尺寸无关渲染）。
      Column() {}
        .width(0)
        .height(0)
        .bindSheet(this.messageMenuOpen, this.MessageMenuSheet(), {
          detents: [SheetSize.FIT_CONTENT],
          dragBar: true,
          showClose: false,
          onDisappear: (): void => { this.closeMessageMenu(); }
        })
      Column() {}
        .width(0)
        .height(0)
        .bindSheet(this.configSheetOpen, this.ConfigSheet(), {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          dragBar: true,
          showClose: true,
          // sheet 容器（含顶部 dragBar/header 区）统一 c.bg：消除顶部异色条（对照 chatcube themeBackground）。
          //   SheetOptions 无 backgroundBlurStyle 字段；纯色背板照 ImagePreviewSheet 只设 backgroundColor。
          backgroundColor: this.c.bg,
          onDisappear: (): void => { this.configSheetOpen = false; }
        })
      Column() {}
        .width(0)
        .height(0)
        .bindSheet(this.outlineOpen, this.OutlineSheet(), {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          dragBar: true,
          showClose: true,
          onDisappear: (): void => { this.outlineOpen = false; }
        })
      // 重命名 sheet（⋯ 下拉「重命名」开；独立 0×0 锚点，不与他 sheet 冲突）
      Column() {}
        .width(0)
        .height(0)
        .bindSheet(this.showRename, this.RenameSheet(), {
          detents: [SheetSize.FIT_CONTENT],
          dragBar: true,
          showClose: true,
          title: { title: t('sessionMenu.renameSheetTitle') },
          onDisappear: (): void => { this.closeRename(); }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.c.bg)
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack;
      const param = context.pathInfo.param as ChatPageRouteParams;
      if (param !== null && param !== undefined) {
        if (this.sessionId === '') {
          this.sessionId = param.sessionId;
        }
      }
    })
    .onBackPressed((): boolean => {
      // 附件面板开时 back 先收面板（对照 chatcube ChatPage:2893 onBackPressed）；
      //   各 bindSheet(config/schedule/messageMenu/outline/rename/imagePreview)原生消费 back，不重复处理。
      if (this.attachmentPanelOpen) {
        this.closeAttachmentPanel();
        return true;
      }
      if (this.searchMode) {       // 搜索栏开 → back 先退搜索
        this.toggleSearch();
        return true;
      }
      return false;
    })
  }
}

// 系统路由表 buildFunction（router_map.json 引用）
@Builder
export function ChatPageBuilder(name: string, param: Object) {
  ChatPage({ routeParamsSeed: param as ChatPageRouteParams })
}
