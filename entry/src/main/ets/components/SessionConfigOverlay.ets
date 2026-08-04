import { getHubClient } from '../api/HubClient';
import {
  ModelOption,
  modelOptionsForAgent, modelDisplayName,
  EFFORT_OPTIONS, effortDisplayName,
  permissionModesForFlavor, permissionModeDisplayName,
  CODEX_COLLABORATION_MODES, collaborationModeDisplayName,
  reasoningEffortsForFlavor, reasoningEffortDisplayName
} from '../models/Types';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';
import { SheetDialog } from './settings/SheetDialog';

// 会话内即时配置 overlay（对照 web FloatingOverlay + SessionChat 配置区）：
//   分区按 flavor 门控：模型(全)/权限模式(全)/协作模式(仅codex)/努力度(仅claude)/推理努力(codex·opencode)。
//   纯展示 + 回调：当前值由 ChatPage 传入，每项 tap 即回调（ChatPage 调对应 REST 端点并回写本地态 → @Param 刷新高亮）。
//   model/effort/reasoning 的「默认」= ''（ChatPage 据此发 null 复位）；permission/collaboration mode 无复位（'default' 即字面模式）。
//   model 分区除静态预设外，codex/cursor/opencode 另从 Hub 拉 session 作用域 live 列表（aboutToAppear → getSessionXxxModels）。

@ComponentV2
export struct SessionConfigOverlay {
  @Param sessionId: string = '';                    // session 作用域拉模型列表用
  @Param flavor: string = '';
  @Param model: string = '';
  @Param effort: string = '';                       // claude 努力度（'auto'→''？保留原值，'auto'=默认）
  @Param modelReasoningEffort: string = '';          // codex/opencode 推理努力
  @Param permissionMode: string = '';
  @Param collaborationMode: string = '';
  @Local dynamicModels: ModelOption[] = [];          // codex/cursor/opencode 拉 session 作用域 live 模型；其余 flavor 留空
  @Event onSetModel: (m: string) => void = (m: string): void => {};
  @Event onSetEffort: (e: string) => void = (e: string): void => {};
  @Event onSetReasoningEffort: (e: string) => void = (e: string): void => {};
  @Event onSetPermissionMode: (m: string) => void = (m: string): void => {};
  @Event onSetCollaborationMode: (m: string) => void = (m: string): void => {};
  /** 标题栏 ✕ 关闭（ChatPage 收 configSheetOpen） */
  @Event onClose: () => void = (): void => {};

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }
  private get isDark(): boolean { return getThemeState().isDark; }

  // 半透明色（对照 ComposerToolbar.withAlpha / chatcube withColorAlpha：#RRGGBB → #AA{{RRGGBB}}，八位色 alpha 在前）。
  private withAlpha(color: string, alphaHex: string): string {
    if (color.startsWith('#') && color.length === 7) {
      return `#${alphaHex}${color.substring(1)}`;
    }
    return color;
  }
  // 选中行底（chatcube themePrimarySubtleBackground：primary + 暗 '28'/亮 '14'）。
  private selectedBg(): string { return this.withAlpha(this.c.primary, this.isDark ? '28' : '14'); }

  // 按 flavor 拉 session 作用域 live 模型列表 → 写 @Local dynamicModels。
  //   claude/gemini/kimi：纯静态预设，无需拉取 → 清空。
  //   codex/cursor/opencode：getSessionXxxModels(sessionId)（session 自带 cwd，无需另传）。
  //   失败静默 → 清空（回落静态预设 + 「默认」，不阻塞配置）。防竞态：await 后 sessionId/flavor 已变则丢弃。
  aboutToAppear(): void {
    this.refreshModels();   // fire-and-forget：先空列表渲染，拉到后 @Local 触发重渲染
  }
  private async refreshModels(): Promise<void> {
    const sid: string = this.sessionId;
    const flavor: string = this.flavor;
    if (sid === '' || (flavor !== 'codex' && flavor !== 'cursor' && flavor !== 'opencode')) {
      this.dynamicModels = [];
      return;
    }
    try {
      let models: ModelOption[] = [];
      if (flavor === 'codex') {
        models = await getHubClient().getSessionCodexModels(sid);
      } else if (flavor === 'cursor') {
        models = await getHubClient().getSessionCursorModels(sid);
      } else {   // opencode
        models = await getHubClient().getSessionOpencodeModels(sid);
      }
      if (this.sessionId !== sid || this.flavor !== flavor) { return; }   // 过期结果丢弃
      this.dynamicModels = models;
    } catch (e) {
      this.dynamicModels = [];   // 静默回落
    }
  }

  // 模型当前值归一：'auto'/'default'/'' → ''（默认）；trim。对照 normalizeClaudeComposerModel。
  private modelKey(m: string): string {
    const trimmed: string = m.trim();
    if (trimmed === '' || trimmed === 'auto' || trimmed === 'default') { return ''; }
    return trimmed;
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
      .fontSize(fs(13))
      .fontWeight(FontWeight.Medium)
      .fontColor(this.c.textSecondary)
      .width('100%')
      .padding({ left: 4, top: 16, bottom: 8 })
  }

  // 选项胶囊（对照 chatcube ChatToolPickerSheetContent / ModelPickerSheet / NewSession PickerSheet：
  //   选中→primary 半透明底 + primary 字 + Medium + 实心圆；未选→灰底(surface) 浮白身 + 次要字 + 空心圆。
  //   行间 margin 8vp；sectionTitle 顶 16 底 8 → 组内紧(8)/组间松(24) 的近聚分组。
  @Builder
  private optionRow(label: string, value: string, current: string, field: string) {
    Row({ space: 10 }) {
      SymbolGlyph(value === current ? $r('sys.symbol.circle_fill') : $r('sys.symbol.circle'))
        .fontSize(fs(15))
        .fontColor([value === current ? this.c.primary : this.c.textTertiary])
        .width(20)
      Text(label)
        .fontSize(fs(15))
        .fontWeight(value === current ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(value === current ? this.c.primary : this.c.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height(48)
    .padding({ left: 14, right: 14 })
    .borderRadius(12)
    .backgroundColor(value === current ? this.selectedBg() : this.c.surface)
    .margin({ bottom: 8 })
    .onClick(() => { this.dispatch(field, value); })
  }

  build() {
    // 固定标题栏（SheetDialog 白头 + ✕）+ 白身滚动区：标题不再随滚动消失（对照 NewSession PickerSheet /
    //   设置页半窗）。原 title Text 在 Scroll 内随滚动消失 → 顶部只剩原生细把手；现 SheetDialog 常驻。
    //   ⚠️ 配套：sheet 白身 c.bg，故未选胶囊翻灰底 c.surface（灰胶囊浮白身，与 PickerSheet 一致）。
    Column() {
      SheetDialog({
        title: t('sessionConfig.title'),
        showCloseButton: true,
        onClose: () => { this.onClose(); }
      })
      Scroll() {
        Column() {
          // —— 模型（全 flavor：默认 + modelOptionsForAgent 静态预设 + codex/cursor/opencode 动态拉取）——
          this.sectionTitle(t('sessionConfig.model'))
          this.optionRow(modelDisplayName(this.flavor, ''), '', this.modelKey(this.model), 'model')
          ForEach(modelOptionsForAgent(this.flavor), (m: string) => {
            this.optionRow(modelDisplayName(this.flavor, m), m, this.modelKey(this.model), 'model')
          }, (m: string) => m)
          ForEach(this.dynamicModels, (mo: ModelOption) => {
            this.optionRow(mo.label, mo.id, this.modelKey(this.model), 'model')
          }, (mo: ModelOption) => mo.id)

          // —— 权限模式（全 flavor 子集）——
          this.sectionTitle(t('sessionConfig.permissionMode'))
          ForEach(permissionModesForFlavor(this.flavor), (mode: string) => {
            this.optionRow(permissionModeDisplayName(mode), mode, this.permissionMode, 'permission')
          }, (mode: string) => mode)

          // —— 协作模式（仅 codex）——
          if (this.showCollaboration()) {
            this.sectionTitle(t('sessionConfig.collaborationMode'))
            ForEach(CODEX_COLLABORATION_MODES, (mode: string) => {
              this.optionRow(collaborationModeDisplayName(mode), mode, this.collaborationMode, 'collaboration')
            }, (mode: string) => mode)
          }

          // —— 努力度（仅 claude）——
          if (this.showEffort()) {
            this.sectionTitle(t('sessionConfig.effort'))
            ForEach(EFFORT_OPTIONS, (e: string) => {
              this.optionRow(effortDisplayName(e), e, this.effort, 'effort')
            }, (e: string) => e)
          }

          // —— 推理努力（codex / opencode）——
          if (this.showReasoningEffort()) {
            this.sectionTitle(t('sessionConfig.reasoningEffort'))
            ForEach(reasoningEffortsForFlavor(this.flavor), (e: string) => {
              this.optionRow(reasoningEffortDisplayName(e), e, this.modelReasoningEffort, 'reasoning')
            }, (e: string) => e)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .backgroundColor(this.c.bg)
    }
    .width('100%')
    .height('100%')
  }
}
