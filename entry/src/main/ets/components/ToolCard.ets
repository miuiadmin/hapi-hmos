import { ChatBlock, ChatToolCall, ToolPermission } from '../chat/ChatBlock';
import { ToolPresentation, getToolPresentation, isEditToolName, isAskToolName } from '../chat/Presentation';
import { getInputStrAny } from '../chat/ToolInputUtils';
import { isAskUserQuestionToolName } from '../chat/AskUserQuestion';
import { isRequestUserInputToolName } from '../chat/RequestUserInput';
import { isCodexSessionByFlavor } from '../chat/AgentFlavor';
import { getHubClient, ApproveOptions } from '../api/HubClient';
import { ToolInputView, ToolResultView } from './ToolCardViews';
import { AskUserQuestionFooter } from './AskUserQuestionFooter';
import { RequestUserInputFooter } from './RequestUserInputFooter';
import { AskUserQuestionView } from './AskUserQuestionView';
import { RequestUserInputView } from './RequestUserInputView';
import { shouldShowInlineToolCardBody, shouldUseCompactTerminalToolCard, TerminalToolDisplayMode } from '../chat/TerminalToolDisplay';
import { getTerminalToolDisplayState } from '../services/TerminalToolDisplayService';
import { getChatSurfaceColorsState } from '../services/ChatSurfaceColorsService';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';

// ToolCard —— 对齐 web/src/components/ToolCard/ToolCard.tsx + PermissionFooter.tsx
// 工具调用卡：header（emoji+标题+副标题+elapsed+状态符+详情入口）+ 卡片体（特化/已答回显）+ footer（三选一）+ 详情半模态。
// footer 三选一互斥（仅 permission.status==='pending' 时挂其一）：
//   通用权限 footer（允许/拒绝）/ AskUserQuestionFooter / RequestUserInputFooter。
// 已答 AskUserQuestion（status!=='pending'）→ 内联 AskUserQuestionView 高亮回显。
// V2 状态：@Param block/sessionId；@Local isDetailOpen（bindSheet 双向绑定用 !!）/actionLoading/actionError。

function errMsg(e: Object, fallback: string): string {
  return e instanceof Error ? e.message : fallback;
}

@ComponentV2
struct ToolCard {
  @Param block: ChatBlock = new ChatBlock();
  @Param sessionId: string = '';
  @Param flavor: string = '';             // 会话 flavor（ChatPage 透传；决定 Codex 系权限页变体）
  @Param nowTick: number = 0;               // running 卡 elapsed 实时驱动（ChatPage 仅对 running 卡传非 0）
  @Event onDecided: () => void = () => {};   // 审批/拒绝成功后通知父页刷新 agentState（防 SSE 漏事件导致卡不翻转）
  @Local isDetailOpen: boolean = false;
  @Local actionLoading: string = '';     // ''|'allow'|'session'|'alledits'|'deny'|'abort'
  @Local actionError: string = '';
  @Local decided: boolean = false;       // 任一审批动作成功后置位：防 SSE 翻转前重复点击（对齐答题 footer 的 done）

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  // 稳定的空 tool 占位（tool-call 块恒有 tool；此仅满足 @Param 非空类型，复用同一实例避免每帧新建）
  private emptyTool: ChatToolCall = new ChatToolCall();

  private get tool(): ChatToolCall | null {
    return this.block.tool;
  }

  // 传给子视图的非空 tool（tool 为空时退回 emptyTool 占位）
  private get toolNotNull(): ChatToolCall {
    return this.tool !== null ? this.tool : this.emptyTool;
  }

  private get permission(): ToolPermission | null {
    return this.tool !== null ? this.tool.permission : null;
  }

  private get presentation(): ToolPresentation {
    return this.tool !== null ? getToolPresentation(this.tool) : new ToolPresentation();
  }

  private get toolName(): string {
    return this.tool !== null ? this.tool.name : '';
  }

  // pending 权限（等用户决定）
  private get isPending(): boolean {
    const p = this.permission;
    return p !== null && p.status === 'pending';
  }

  // 终端工具卡片显示模式（读 @Trace mode 建立刷新依赖；设置页切换即时重渲染，同 isDark 机制）
  private get terminalToolMode(): TerminalToolDisplayMode {
    return getTerminalToolDisplayState().mode;
  }

  // compact 终端卡走紧凑样式（副标题单行截断；对照上游 useCompactTerminalCard）
  private get useCompactTerminalCard(): boolean {
    return shouldUseCompactTerminalToolCard(this.toolName, this.terminalToolMode);
  }

  // 是否挂内联卡片体（对照上游 showInline = shouldShowInlineToolCardBody）：
  //   子代理工具→false；终端类(Bash 等)→detailed 时 true（绕过 minimal 内联命令预览）；其他→!minimal。
  private get hasInlineBody(): boolean {
    return shouldShowInlineToolCardBody(this.toolName, this.presentation.minimal, this.terminalToolMode);
  }

  // 是否挂通用权限 footer：pending 且非答题工具；或 denied/canceled（显示状态/原因框）
  private get showsFooter(): boolean {
    const p = this.permission;
    if (p === null) {
      return false;
    }
    if (p.status === 'pending') {
      return !isAskToolName(this.toolName);
    }
    return p.status === 'denied' || p.status === 'canceled';
  }

  private get isAskUserQuestion(): boolean {
    return isAskUserQuestionToolName(this.toolName);
  }

  private get isRequestUserInputTool(): boolean {
    return isRequestUserInputToolName(this.toolName);
  }

  // pending 的答题工具 → 挂专用答题 footer（取代通用权限 footer）
  private get isPendingAskUserQuestion(): boolean {
    return this.isPending && this.isAskUserQuestion;
  }

  private get isPendingRequestUserInput(): boolean {
    return this.isPending && this.isRequestUserInputTool;
  }

  // 非 pending（approved/denied/canceled）的 AskUserQuestion → 内联已答视图高亮回显
  private get isAnsweredAskUserQuestion(): boolean {
    if (!this.isAskUserQuestion) {
      return false;
    }
    const p = this.permission;
    return p !== null && p.status !== 'pending';
  }

  // 非 pending（approved/denied/canceled）的 request_user_input → 内联已答视图回显（●/○ + 备注）
  private get isAnsweredRequestUserInput(): boolean {
    if (!this.isRequestUserInputTool) {
      return false;
    }
    const p = this.permission;
    return p !== null && p.status !== 'pending';
  }

  private get canAllowForSession(): boolean {
    if (!this.isPending) {
      return false;
    }
    if (isEditToolName(this.toolName) || isAskToolName(this.toolName)) {
      return false;
    }
    const n = this.toolName;
    return n !== 'ExitPlanMode' && n !== 'exit_plan_mode';
  }

  private get canAllowAllEdits(): boolean {
    return this.isPending && isEditToolName(this.toolName);
  }

  // Codex 系会话（flavor 命中或工具名 Codex/Gemini/OpenCode 前缀）→ 权限页走 Yes/YesForSession/Abort 变体
  private get isCodexSession(): boolean {
    return isCodexSessionByFlavor(this.flavor, this.toolName);
  }

  // abort 后的决策（permission.decision==='abort'）→ 非待批 banner 显「已中止」（区别于 denied「已拒绝」）
  private get isAborted(): boolean {
    const p = this.permission;
    return p !== null && p.status === 'denied' && p.decision === 'abort';
  }

  // 状态符号：🔒 pending / ✓ completed / ✕ error / ● running
  private statusGlyph(): string {
    const t = this.tool;
    if (t === null) {
      return '';
    }
    if (t.permission !== null && t.permission.status === 'pending') {
      return '🔒';
    }
    if (t.state === 'completed') {
      return '✓';
    }
    if (t.state === 'error') {
      return '✕';
    }
    return '●';
  }

  private statusColor(): string {
    const t = this.tool;
    if (t === null) {
      return this.c.textTertiary;
    }
    if (t.permission !== null && t.permission.status === 'pending') {
      return this.c.warning;
    }
    if (t.state === 'completed') {
      return this.c.success;
    }
    if (t.state === 'error') {
      return this.c.error;
    }
    return this.c.textTertiary;
  }

  // elapsed（仅 running）：读取 this.nowTick 建立 build 刷新依赖 —— ChatPage ticker 每秒对 running 卡 bump → 卡内 build 重跑重算耗时
  private elapsedText(): string {
    const t = this.tool;
    if (t === null || t.state !== 'running') {
      return '';
    }
    const from: number = t.startedAt > 0 ? t.startedAt : t.createdAt;
    if (from <= 0) {
      return '';
    }
    const ticking: boolean = this.nowTick >= 0;   // 恒真；仅为引用 nowTick 触发刷新
    if (!ticking) {
      return '';
    }
    const secs: number = Math.max(0, (Date.now() - from) / 1000);
    return `${secs.toFixed(1)}s`;
  }

  // 副标题：presentation.subtitle，缺省回退工具 description（截断 160）
  private subtitleText(): string {
    const s: string = this.presentation.subtitle;
    if (s !== '') {
      return truncateSafe(s, 160);
    }
    const t = this.tool;
    return t !== null && t.description !== '' ? truncateSafe(t.description, 160) : '';
  }

  // ===== 审批动作 =====
  private async doAllow(): Promise<void> {
    const p = this.permission;
    if (p === null || this.actionLoading !== '') {
      return;
    }
    this.actionError = '';
    this.actionLoading = 'allow';
    try {
      const ok = await getHubClient().approvePermission(this.sessionId, p.id);
      if (!ok) {
        this.actionError = t('tool.approveFailed');
      } else {
        this.decided = true;
        this.onDecided();
      }
    } catch (e) {
      this.actionError = errMsg(e, t('tool.approveFailed'));
    } finally {
      this.actionLoading = '';
    }
  }

  private async doAllowForSession(): Promise<void> {
    const p = this.permission;
    const t = this.tool;
    if (p === null || t === null || this.actionLoading !== '') {
      return;
    }
    this.actionError = '';
    this.actionLoading = 'session';
    try {
      const opts: ApproveOptions = new ApproveOptions();
      let ident: string = t.name;
      if (t.name === 'Bash') {
        const cmd: string = getInputStrAny(t.input, ['command', 'cmd']);
        ident = cmd !== '' ? `Bash(${cmd})` : 'Bash';
      }
      opts.allowTools = [ident];
      const ok = await getHubClient().approvePermission(this.sessionId, p.id, opts);
      if (!ok) {
        this.actionError = t('tool.approveFailed');
      } else {
        this.decided = true;
        this.onDecided();
      }
    } catch (e) {
      this.actionError = errMsg(e, t('tool.approveFailed'));
    } finally {
      this.actionLoading = '';
    }
  }

  private async doAllowAllEdits(): Promise<void> {
    const p = this.permission;
    if (p === null || this.actionLoading !== '') {
      return;
    }
    this.actionError = '';
    this.actionLoading = 'alledits';
    try {
      const opts: ApproveOptions = new ApproveOptions();
      opts.mode = 'acceptEdits';
      const ok = await getHubClient().approvePermission(this.sessionId, p.id, opts);
      if (!ok) {
        this.actionError = t('tool.approveFailed');
      } else {
        this.decided = true;
        this.onDecided();
      }
    } catch (e) {
      this.actionError = errMsg(e, t('tool.approveFailed'));
    } finally {
      this.actionLoading = '';
    }
  }

  private async doDeny(): Promise<void> {
    const p = this.permission;
    if (p === null || this.actionLoading !== '') {
      return;
    }
    this.actionError = '';
    this.actionLoading = 'deny';
    try {
      const ok = await getHubClient().denyPermission(this.sessionId, p.id);
      if (!ok) {
        this.actionError = t('tool.denyFailed');
      } else {
        this.decided = true;
        this.onDecided();
      }
    } catch (e) {
      this.actionError = errMsg(e, t('tool.denyFailed'));
    } finally {
      this.actionLoading = '';
    }
  }

  // Codex 系：Yes（approved，单次）/ Yes-for-session（approved_for_session）。复用 actionLoading 'allow'/'session' 标志。
  private async doCodexApprove(decision: string): Promise<void> {
    const p = this.permission;
    if (p === null || this.actionLoading !== '') {
      return;
    }
    this.actionError = '';
    this.actionLoading = decision === 'approved' ? 'allow' : 'session';
    try {
      const opts: ApproveOptions = new ApproveOptions();
      opts.decision = decision;
      const ok = await getHubClient().approvePermission(this.sessionId, p.id, opts);
      if (!ok) {
        this.actionError = t('tool.approveFailed');
      } else {
        this.decided = true;
        this.onDecided();
      }
    } catch (e) {
      this.actionError = errMsg(e, t('tool.approveFailed'));
    } finally {
      this.actionLoading = '';
    }
  }

  // Codex 系：Abort（deny，decision='abort'）。走 denyPermission 带决策串。
  private async doCodexAbort(): Promise<void> {
    const p = this.permission;
    if (p === null || this.actionLoading !== '') {
      return;
    }
    this.actionError = '';
    this.actionLoading = 'abort';
    try {
      const ok = await getHubClient().denyPermission(this.sessionId, p.id, 'abort');
      if (!ok) {
        this.actionError = t('tool.denyFailed');
      } else {
        this.decided = true;
        this.onDecided();
      }
    } catch (e) {
      this.actionError = errMsg(e, t('tool.denyFailed'));
    } finally {
      this.actionLoading = '';
    }
  }

  // ===== Builders =====
  @Builder
  private Header() {
    Row() {
      // 左：图标 + 标题 + 副标题
      Column() {
        Row() {
          Text(this.presentation.icon)
            .fontSize(fs(14))
            .margin({ right: 6 })
          Text(this.presentation.title)
            .fontSize(fs(14))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.textPrimary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.subtitleText() !== '') {
          Text(this.subtitleText())
            .fontSize(fs(11))
            .fontColor(this.c.textSecondary)
            .maxLines(this.useCompactTerminalCard ? 1 : 2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 右：elapsed + 状态符 + 详情入口
      Column() {
        Row() {
          if (this.elapsedText() !== '') {
            Text(this.elapsedText())
              .fontSize(fs(11))
              .fontColor(this.c.textTertiary)
              .margin({ right: 6 })
          }
          Text(this.statusGlyph())
            .fontSize(fs(13))
            .fontColor(this.statusColor())
          Text('›')
            .fontSize(fs(18))
            .fontColor(this.c.textTertiary)
            .margin({ left: 4 })
        }
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .onClick(() => {
      this.isDetailOpen = true;
    })
  }

  // 单个权限动作行（@Builder 只收基本类型参数；动作经 actionKey 内部分派，避免向 @Builder 传回调）
  @Builder
  private ActionRow(label: string, color: string, loading: boolean, actionKey: string, disabled: boolean) {
    Row() {
      Text(label)
        .fontSize(fs(14))
        .fontColor(disabled ? this.c.textTertiary : color)
        .layoutWeight(1)
      if (loading) {
        LoadingProgress()
          .width(14)
          .height(14)
          .color(color)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 9, bottom: 9 })
    .borderRadius(12)
    .backgroundColor(this.c.bg)
    .margin({ top: 6 })
    .opacity(disabled ? 0.5 : 1)
    .onClick(() => {
      if (disabled) {
        return;
      }
      this.dispatchAction(actionKey);
    })
  }

  private dispatchAction(key: string): void {
    if (this.decided) {
      return;
    }
    if (key === 'allow') {
      this.doAllow();
    } else if (key === 'session') {
      this.doAllowForSession();
    } else if (key === 'alledits') {
      this.doAllowAllEdits();
    } else if (key === 'deny') {
      this.doDeny();
    } else if (key === 'codexYes') {
      this.doCodexApprove('approved');
    } else if (key === 'codexSession') {
      this.doCodexApprove('approved_for_session');
    } else if (key === 'abort') {
      this.doCodexAbort();
    }
  }

  @Builder
  private PermissionFooter() {
    if (this.isPending) {
      Column() {
        Text(this.decided ? t('tool.decided') : t('tool.waitingForApproval'))
          .fontSize(fs(11))
          .fontColor(this.c.textTertiary)
          .width('100%')

        if (this.actionError !== '') {
          Text(this.actionError)
            .fontSize(fs(11))
            .fontColor(this.c.error)
            .width('100%')
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .backgroundColor(this.c.errorBg)
            .borderRadius(8)
            .margin({ top: 6 })
        }

        // Codex 系权限页变体：Yes / Yes-for-session / Abort（三键恒显，无 canAllow 门控；对照上游 PermissionFooter Codex 分支）
        if (this.isCodexSession) {
          this.ActionRow(t('tool.yes'), this.c.success, this.actionLoading === 'allow', 'codexYes', this.decided)
          this.ActionRow(t('tool.yesForSession'), this.c.textSecondary, this.actionLoading === 'session', 'codexSession', this.decided)
          this.ActionRow(t('tool.abortLabel'), this.c.error, this.actionLoading === 'abort', 'abort', this.decided)
        } else {
          this.ActionRow(t('tool.allow'), this.c.success, this.actionLoading === 'allow', 'allow', this.decided)

          if (this.canAllowForSession) {
            this.ActionRow(t('tool.allowForSession'), this.c.textSecondary, this.actionLoading === 'session', 'session', this.decided)
          }
          if (this.canAllowAllEdits) {
            this.ActionRow(t('tool.allowAll'), this.c.textSecondary, this.actionLoading === 'alledits', 'alledits', this.decided)
          }

          this.ActionRow(t('tool.deny'), this.c.error, this.actionLoading === 'deny', 'deny', this.decided)
        }
      }
      .width('100%')
      .margin({ top: 8 })
      .padding({ top: 8, bottom: 4 })
      .border({ width: { top: 1 }, color: this.c.border })
    } else {
      // denied/canceled/aborted：状态标签（✕ 已拒绝 / ⊘ 已中止 / ⊘ 已取消）+ 原因（若有）
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Text(this.isAborted ? '⊘' : (this.permission !== null && this.permission.status === 'denied' ? '✕' : '⊘'))
            .fontSize(fs(13))
            .fontColor(this.c.error)
          Text(this.isAborted ? t('tool.aborted') : (this.permission !== null && this.permission.status === 'denied' ? t('tool.rejected') : t('tool.canceled')))
            .fontSize(fs(12))
            .fontColor(this.c.error)
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.permission !== null && this.permission.reason !== '') {
          Text(this.permission.reason)
            .fontSize(fs(11))
            .fontColor(this.c.error)
            .width('100%')
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .backgroundColor(this.c.errorBg)
            .borderRadius(8)
        }
      }
      .width('100%')
      .margin({ top: 8 })
      .padding({ top: 8, bottom: 4 })
      .border({ width: { top: 1 }, color: this.c.border })
    }
  }

  // 详情半模态：特化输入视图 + 结果视图（dialog surface，完整未截断）。对照上游 ToolDetailDialogContent。
  @Builder
  private DetailSheet() {
    Scroll() {
      Column() {
        Text(t('tool.input'))
          .fontSize(fs(11))
          .fontColor(this.c.textTertiary)
          .width('100%')
          .margin({ bottom: 6 })
        ToolInputView({ tool: this.toolNotNull, surface: 'dialog' })

        Text(t('tool.result'))
          .fontSize(fs(11))
          .fontColor(this.c.textTertiary)
          .width('100%')
          .margin({ top: 16, bottom: 6 })
        ToolResultView({ tool: this.toolNotNull, surface: 'dialog' })
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Auto)
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST,
    })
  }

  build() {
    Column() {
      this.Header()
      if (this.hasInlineBody) {
        // 内联卡片体（TodoWrite 清单 / update_plan 步骤 / ExitPlanMode 计划）
        Column() {
          ToolInputView({ tool: this.toolNotNull, surface: 'inline' })
        }
        .width('100%')
        .margin({ top: 8 })
      } else if (this.isAnsweredAskUserQuestion) {
        // 已答 AskUserQuestion：只读高亮回显（approved 后 footer 卸载，改此视图）
        Column() {
          AskUserQuestionView({ tool: this.toolNotNull })
        }
        .width('100%')
        .margin({ top: 8 })
      } else if (this.isAnsweredRequestUserInput) {
        // 已答 request_user_input：只读回显（approved 后 footer 卸载，改此视图）
        Column() {
          RequestUserInputView({ tool: this.toolNotNull })
        }
        .width('100%')
        .margin({ top: 8 })
      }
      if (this.showsFooter) {
        this.PermissionFooter()
      } else if (this.isPendingAskUserQuestion) {
        AskUserQuestionFooter({ tool: this.toolNotNull, sessionId: this.sessionId })
      } else if (this.isPendingRequestUserInput) {
        RequestUserInputFooter({ tool: this.toolNotNull, sessionId: this.sessionId })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(getChatSurfaceColorsState().toolGroupBg || this.c.surface)
    .borderRadius(16)
    .bindSheet(this.isDetailOpen!!, this.DetailSheet(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      blurStyle: BlurStyle.Thick,
      title: { title: this.presentation.title },
    })
  }
}

// 截断（本组件内用，避免与 chat 层耦合）
function truncateSafe(s: string, max: number): string {
  if (max <= 0 || s.length <= max) {
    return s;
  }
  return s.substring(0, max) + '…';
}

export { ToolCard };
