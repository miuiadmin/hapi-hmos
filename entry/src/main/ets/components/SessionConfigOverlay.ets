import {
  modelOptionsForAgent, modelDisplayName,
  EFFORT_OPTIONS, effortDisplayName,
  permissionModesForFlavor, permissionModeDisplayName,
  CODEX_COLLABORATION_MODES, collaborationModeDisplayName,
  reasoningEffortsForFlavor, reasoningEffortDisplayName
} from '../models/Types';
import { paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';

// 会话内即时配置 overlay（对照 web FloatingOverlay + SessionChat 配置区）：
//   分区按 flavor 门控：模型(全)/权限模式(全)/协作模式(仅codex)/努力度(仅claude)/推理努力(codex·opencode)。
//   纯展示 + 回调：当前值由 ChatPage 传入，每项 tap 即回调（ChatPage 调对应 REST 端点并回写本地态 → @Param 刷新高亮）。
//   model/effort/reasoning 的「默认」= ''（ChatPage 据此发 null 复位）；permission/collaboration mode 无复位（'default' 即字面模式）。

@ComponentV2
export struct SessionConfigOverlay {
  @Param flavor: string = '';
  @Param model: string = '';
  @Param effort: string = '';                       // claude 努力度（'auto'→''？保留原值，'auto'=默认）
  @Param modelReasoningEffort: string = '';          // codex/opencode 推理努力
  @Param permissionMode: string = '';
  @Param collaborationMode: string = '';
  @Event onSetModel: (m: string) => void = (m: string): void => {};
  @Event onSetEffort: (e: string) => void = (e: string): void => {};
  @Event onSetReasoningEffort: (e: string) => void = (e: string): void => {};
  @Event onSetPermissionMode: (m: string) => void = (m: string): void => {};
  @Event onSetCollaborationMode: (m: string) => void = (m: string): void => {};

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  // 模型当前值归一：'auto'/'default'/'' → ''（默认）；trim。对照 normalizeClaudeComposerModel。
  private modelKey(m: string): string {
    const t: string = m.trim();
    if (t === '' || t === 'auto' || t === 'default') { return ''; }
    return t;
  }

  private showEffort(): boolean { return this.flavor === 'claude'; }
  private showReasoningEffort(): boolean { return this.flavor === 'codex' || this.flavor === 'opencode'; }
  private showCollaboration(): boolean { return this.flavor === 'codex'; }

  // optionRow 用 field 字符串分发到对应 @Event（避免 @Builder 传函数参数——ArkUI 按值捕获函数型参不稳）。
  private dispatch(field: string, value: string): void {
    if (field === 'model') { this.onSetModel(value); }
    else if (field === 'effort') { this.onSetEffort(value); }
    else if (field === 'reasoning') { this.onSetReasoningEffort(value); }
    else if (field === 'permission') { this.onSetPermissionMode(value); }
    else if (field === 'collaboration') { this.onSetCollaborationMode(value); }
  }

  @Builder
  private sectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor(this.c.textTertiary)
      .width('100%')
      .padding({ left: 4, top: 14, bottom: 4 })
  }

  @Builder
  private optionRow(label: string, value: string, current: string, field: string) {
    Row({ space: 10 }) {
      Text(value === current ? '●' : '○')
        .fontSize(14)
        .fontColor(value === current ? this.c.primary : this.c.textTertiary)
        .width(18)
      Text(label)
        .fontSize(15)
        .fontColor(value === current ? this.c.textPrimary : this.c.textSecondary)
        .layoutWeight(1)
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .borderRadius(8)
    .onClick(() => { this.dispatch(field, value); })
  }

  build() {
    Scroll() {
      Column() {
        Text('会话配置')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.textPrimary)
          .width('100%')
          .padding({ left: 4, top: 4, bottom: 4 })

        // —— 模型（全 flavor：默认 + modelOptionsForAgent 预设）——
        this.sectionTitle('模型')
        this.optionRow(modelDisplayName(this.flavor, ''), '', this.modelKey(this.model), 'model')
        ForEach(modelOptionsForAgent(this.flavor), (m: string) => {
          this.optionRow(modelDisplayName(this.flavor, m), m, this.modelKey(this.model), 'model')
        }, (m: string) => m)

        // —— 权限模式（全 flavor 子集）——
        this.sectionTitle('权限模式')
        ForEach(permissionModesForFlavor(this.flavor), (mode: string) => {
          this.optionRow(permissionModeDisplayName(mode), mode, this.permissionMode, 'permission')
        }, (mode: string) => mode)

        // —— 协作模式（仅 codex）——
        if (this.showCollaboration()) {
          this.sectionTitle('协作模式')
          ForEach(CODEX_COLLABORATION_MODES, (mode: string) => {
            this.optionRow(collaborationModeDisplayName(mode), mode, this.collaborationMode, 'collaboration')
          }, (mode: string) => mode)
        }

        // —— 努力度（仅 claude）——
        if (this.showEffort()) {
          this.sectionTitle('努力度')
          ForEach(EFFORT_OPTIONS, (e: string) => {
            this.optionRow(effortDisplayName(e), e, this.effort, 'effort')
          }, (e: string) => e)
        }

        // —— 推理努力（codex / opencode）——
        if (this.showReasoningEffort()) {
          this.sectionTitle('推理努力')
          ForEach(reasoningEffortsForFlavor(this.flavor), (e: string) => {
            this.optionRow(reasoningEffortDisplayName(e), e, this.modelReasoningEffort, 'reasoning')
          }, (e: string) => e)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 24 })
    }
    .width('100%')
    .constraintSize({ maxHeight: '70%' })
    .scrollBar(BarState.Off)
    .backgroundColor(this.c.bg)
  }
}
