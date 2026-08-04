// 输入框上方工具条（对照 chatcube components/ChatToolbar.ets，MIT；UI/交互照搬，资源机制走本项目 Palette）。
//   旧顶部 StatusBar 的全部状态下沉到此：左色点+文案(连接/思考/权限/在线) + 思考强度 chip(菜单切档) +
//   权限 chip(点击=开模型按钮同一个 sheet) + codex fast/goal/collaboration 状态 chip。
//   胶囊 chip 规格（ChatToolbar.ets:134-143）：Capsule / h32 / padding{12,12} / r16 / blur COMPONENT_REGULAR /
//   边框1vp(选中 primary/未选中 border) / shadow{radius10,offsetY2} / animation 200 EaseOut。外层 Scroll→Row h32。
//   思考档位按 flavor 取真实可选域（协议不变）：claude→EFFORT_OPTIONS 调 onSetEffort；codex/opencode→reasoning 域调 onSetReasoningEffort。
//   自管一条 SSE onStateChange 监听 + DeviceNetworkState（搬自旧 StatusBar.ets:71-86）。
import { getSSEClient, SSEConnectionState } from '../api/SSEClient';
import { SyncEvent } from '../models/SyncEvent';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { AgentState } from '../chat/AgentState';
import { getDeviceNetworkState, DeviceNetworkState } from '../services/DeviceNetworkService';
import { resolveStatusBarState, VIBING_MESSAGES, StatusBarState } from '../chat/StatusBarStatus';
import {
  shouldShowFastChip,
  shouldShowCollaborationChip,
  shouldShowPermissionChip,
  shouldShowGoalChip,
  permissionModeTone,
  toneColor
} from '../chat/StatusBarChips';
import {
  permissionModeDisplayName, collaborationModeDisplayName, ThreadGoal,
  EFFORT_OPTIONS, effortDisplayName, reasoningEffortsForFlavor, reasoningEffortDisplayName
} from '../models/Types';
import { t } from '../i18n/I18nService';
import { SymbolGlyphModifier } from '@kit.ArkUI';

@ComponentV2
export struct ComposerToolbar {
  @Param isThinking: boolean = false;
  @Param agentState: AgentState | null = null;
  @Param permissionMode: string = '';
  @Param collaborationMode: string = '';
  @Param modelReasoningEffort: string = '';   // codex/opencode 推理努力（思考 chip 档位 + fast 判定）
  @Param model: string = '';                   // fast 判定（含 mini/fast）
  @Param flavor: string = '';                  // 门控各 chip + 思考档位域
  @Param effort: string = '';                  // claude 努力度（思考 chip 档位 + 选中高亮）
  @Param threadGoal: ThreadGoal | null = null; // codex goal chip
  @Event onSetEffort: (e: string) => void = (e: string): void => {};            // claude 思考菜单
  @Event onSetReasoningEffort: (e: string) => void = (e: string): void => {};   // codex/opencode 思考菜单
  @Event onOpenConfig: () => void = (): void => {};                             // 权限 chip → 开模型+权限同一 sheet
  @Local sseState: SSEConnectionState = 'idle';
  @Local net: DeviceNetworkState = getDeviceNetworkState();
  @Local vibingIndex: number = 0;
  private listenerId: number = -1;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }
  private get isDark(): boolean { return getThemeState().isDark; }

  // 半透明色（对照 chatcube ChatToolbar.withAlpha：#RRGGBB → #AA{{RRGGBB}}，HarmonyOS 八位色 alpha 在前）。
  private withAlpha(color: string, alphaHex: string): string {
    if (color.startsWith('#') && color.length === 7) {
      return `#${alphaHex}${color.substring(1)}`;
    }
    return color;
  }
  // chip 半透明底（chatcube getChipBackgroundColor：surface + 暗 '14'/亮 '1A'）。
  private chipBg(): string { return this.withAlpha(this.c.surface, this.isDark ? '14' : '1A'); }
  // chip 未选中描边（chatcube getInactiveChipBorderColor：divider + 暗 'A6'/亮 '73'）。
  private chipBorderInactive(): string { return this.withAlpha(this.c.border, this.isDark ? 'A6' : '73'); }
  // chip 阴影色（chatcube getChipShadowColor：暗 0.18 / 亮 rgba(15,23,42,0.06)）。
  private chipShadow(): string { return this.isDark ? 'rgba(0, 0, 0, 0.18)' : 'rgba(15, 23, 42, 0.06)'; }

  // 仅有 pending 权限请求（对照旧 StatusBar.hasPermissions）
  private get hasPermissions(): boolean {
    return this.agentState !== null && Object.keys(this.agentState.requests).length > 0;
  }

  // build 内禁局部 const（arkts 10905210）：状态合成下沉 getter。
  private get statusBarState(): StatusBarState {
    return resolveStatusBarState(this.net.online, this.sseState === 'open', this.hasPermissions, this.isThinking, this.vibingIndex);
  }

  // 思考 chip 仅 claude(努力度)/codex/opencode(推理努力) 显；其余 flavor 无思考控制。
  private showThinkingChip(): boolean {
    return this.flavor === 'claude' || this.flavor === 'codex' || this.flavor === 'opencode';
  }

  // 思考 chip 是否「启用」（对照 chatcube isReasoningEnabled：level≠OFF；本项目 ''=默认/未启→不高亮，非空=已选档→primary 高亮）。
  private thinkingActive(): boolean {
    if (this.flavor === 'claude') { return this.effort !== ''; }
    return this.modelReasoningEffort !== '';
  }

  // 思考 chip 文案：claude→effortDisplayName(effort)；codex/opencode→reasoningEffortDisplayName；默认→「默认」。
  private thinkingLabel(): string {
    if (this.flavor === 'claude') {
      return this.effort !== '' ? effortDisplayName(this.effort) : t('types.default');
    }
    return this.modelReasoningEffort !== '' ? reasoningEffortDisplayName(this.modelReasoningEffort) : t('types.default');
  }

  // 思考菜单项点击分发（避免 @Builder 传函数参数——按 field 字符串分发，同 SessionConfigOverlay.optionRow 模式）。
  private dispatchThinking(value: string, kind: string): void {
    if (kind === 'effort') { this.onSetEffort(value); } else { this.onSetReasoningEffort(value); }
  }

  // goal chip 文案（对照旧 StatusBar.goalLabel）
  private goalLabel(): string {
    const g = this.threadGoal;
    if (g === null) { return ''; }
    if (g.status === 'active') { return t('statusBar.goal'); }
    if (g.status === 'budgetLimited') { return t('statusBar.goalLimited'); }
    if (g.status === 'paused') { return t('statusBar.goalPaused'); }
    if (g.status === 'complete') { return t('statusBar.goalComplete'); }
    return t('statusBar.goal');
  }

  // 权限 chip 是否高亮（bypass 系=警告色调，对照旧 StatusBar 用 toneColor(permissionModeTone)）
  private permissionActive(): boolean {
    return this.permissionMode === 'bypassPermissions' || this.permissionMode === 'yolo' || this.permissionMode === 'safe-yolo';
  }

  aboutToAppear(): void {
    const sse = getSSEClient();
    this.sseState = sse.getState();
    this.listenerId = sse.addListener({
      onEvent: (_event: SyncEvent) => {},
      onStateChange: (state: SSEConnectionState) => { this.sseState = state; }
    });
    this.vibingIndex = Math.floor(Math.random() * VIBING_MESSAGES.length);
  }

  aboutToDisappear(): void {
    if (this.listenerId !== -1) {
      getSSEClient().removeListener(this.listenerId);
      this.listenerId = -1;
    }
  }

  build() {
    Scroll() {
      Row() {
        // 状态 chip（旧 StatusBar 左侧下移：色点 + 文案；非交互纯展示；同款 chip 规格）
        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Row({ space: 6 }) {
            Circle({ width: 8, height: 8 }).fill(this.statusBarState.color)
            Text(this.statusBarState.label)
              .fontSize(fs(14))
              .fontColor(this.statusBarState.color)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .height(32)
        .padding({ left: 12, right: 12 })
        .borderRadius(16)
        .backgroundColor(this.chipBg())
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .border({ width: 1, color: this.chipBorderInactive() })
        .shadow({ radius: 10, color: this.chipShadow(), offsetX: 0, offsetY: 2 })
        .animation({ duration: 200, curve: Curve.EaseOut })

        // 思考强度 chip（chatcube 同款：AI_deep_thinking + 档位 + chevron_up；启用→primary 高亮 + Medium + primary 描边）
        if (this.showThinkingChip()) {
          Button({ type: ButtonType.Capsule, stateEffect: false }) {
            Row() {
              SymbolGlyph($r('sys.symbol.AI_deep_thinking'))
                .fontSize(fs(16))
                .fontColor([this.thinkingActive() ? this.c.primary : this.c.textSecondary])
              Text(this.thinkingLabel())
                .fontSize(fs(14))
                .fontColor(this.thinkingActive() ? this.c.primary : this.c.textSecondary)
                .fontWeight(this.thinkingActive() ? FontWeight.Medium : FontWeight.Regular)
                .margin({ left: 4 })
                .maxLines(1)
              SymbolGlyph($r('sys.symbol.chevron_up'))
                .fontSize(fs(12))
                .fontColor([this.thinkingActive() ? this.c.primary : this.c.textSecondary])
                .margin({ left: 2 })
            }
          }
          .height(32)
          .padding({ left: 12, right: 12 })
          .borderRadius(16)
          .backgroundColor(this.chipBg())
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .border({ width: 1, color: this.thinkingActive() ? this.c.primary : this.chipBorderInactive() })
          .shadow({ radius: 10, color: this.chipShadow(), offsetX: 0, offsetY: 2 })
          .margin({ left: 8 })
          .animation({ duration: 200, curve: Curve.EaseOut })
          .bindMenu(this.ThinkingMenu(), {
            placement: Placement.BottomLeft,
            offset: { x: 0, y: 8 },
            backgroundColor: this.c.surface,
            backgroundBlurStyle: BlurStyle.Regular
          })
        }

        // 权限 chip（非 default 且 flavor 域允许才显；点击=开模型按钮同一个 sheet）
        if (shouldShowPermissionChip(this.permissionMode, this.flavor)) {
          Button({ type: ButtonType.Capsule, stateEffect: false }) {
            Row() {
              SymbolGlyph($r('sys.symbol.lock_open'))
                .fontSize(fs(14))
                .fontColor([toneColor(permissionModeTone(this.permissionMode), this.c)])
              Text(permissionModeDisplayName(this.permissionMode))
                .fontSize(fs(14))
                .fontColor(toneColor(permissionModeTone(this.permissionMode), this.c))
                .margin({ left: 4 })
                .maxLines(1)
            }
          }
          .height(32)
          .padding({ left: 12, right: 12 })
          .borderRadius(16)
          .backgroundColor(this.chipBg())
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .border({ width: 1, color: this.permissionActive() ? this.c.warning : this.chipBorderInactive() })
          .shadow({ radius: 10, color: this.chipShadow(), offsetX: 0, offsetY: 2 })
          .margin({ left: 8 })
          .animation({ duration: 200, curve: Curve.EaseOut })
          .onClick(() => { this.onOpenConfig(); })
        }

        // codex fast 模式 chip（纯展示）
        if (shouldShowFastChip(this.flavor, this.model, this.modelReasoningEffort)) {
          this.PlainChip(t('statusBar.fast'), this.c.success)
        }
        // codex goal chip（纯展示）
        if (shouldShowGoalChip(this.flavor, this.threadGoal !== null)) {
          this.PlainChip(this.goalLabel(), this.c.primary)
        }
        // codex collaboration chip（纯展示）
        if (shouldShowCollaborationChip(this.flavor, this.collaborationMode)) {
          this.PlainChip(collaborationModeDisplayName(this.collaborationMode), this.c.primary)
        }
      }
      .height(32)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height(32)
    .align(Alignment.Start)
    .padding({ left: 4, right: 4 })
    .margin({ bottom: 8 })
  }

  // 纯展示胶囊 chip（fast/goal/collaboration：无图标，色调文字 + 同款胶囊底/边框/阴影）
  @Builder
  PlainChip(text: string, color: string) {
    Text(text)
      .fontSize(fs(14))
      .fontColor(color)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .height(32)
      .padding({ left: 12, right: 12 })
      .borderRadius(16)
      .backgroundColor(this.chipBg())
      .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
      .border({ width: 1, color: this.chipBorderInactive() })
      .shadow({ radius: 10, color: this.chipShadow(), offsetX: 0, offsetY: 2 })
      .margin({ left: 8 })
      .animation({ duration: 200, curve: Curve.EaseOut })
  }

  // 思考强度菜单：claude→EFFORT_OPTIONS(onSetEffort)；codex/opencode→reasoning 域(onSetReasoningEffort)。
  //   选中项带 checkmark；协议不变——不照搬 chatcube 的 OFF/AUTO/LOW/... 全集，只列本 flavor 真实可选档位。
  @Builder
  ThinkingMenu() {
    Menu() {
      if (this.flavor === 'claude') {
        ForEach(EFFORT_OPTIONS, (e: string) => {
          this.ThinkingItem(effortDisplayName(e), e, this.effort, 'effort')
        }, (e: string) => e)
      } else {
        ForEach(reasoningEffortsForFlavor(this.flavor), (e: string) => {
          this.ThinkingItem(reasoningEffortDisplayName(e), e, this.modelReasoningEffort, 'reasoning')
        }, (e: string) => e)
      }
    }
  }

  // 选中判定在 @Builder 内部做（value === currentValue），传参仅纯字符串——同 SessionConfigOverlay.optionRow 模式。
  @Builder
  ThinkingItem(label: string, value: string, currentValue: string, kind: string) {
    if (value === currentValue) {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark')).fontSize(16), content: label })
        .contentFont({ size: fs(14) })
        .onClick(() => { this.dispatchThinking(value, kind); })
    } else {
      MenuItem({ content: label })
        .contentFont({ size: fs(14) })
        .onClick(() => { this.dispatchThinking(value, kind); })
    }
  }
}
