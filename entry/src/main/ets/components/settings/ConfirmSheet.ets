// ConfirmSheet —— 通用确认/说明半屏弹窗（bindSheet 内容），替代系统 AlertDialog。
//
// 标题栏（SheetDialog）+ 可滚动 message + 胶囊按钮行。遮罩/圆角/滑入/下滑关闭由 bindSheet 接管。
//
// 按钮点击契约：先 onClose（父组件置 show=false）再 action。
//   - action 空 / 不弹新内容 → sheet 关闭；
//   - action 内再置 show=true（同步流）→ V2 批处理最终 true，sheet 不关仅热替换内容。
//
// 按钮（Capsule h48 stateEffect，对照 berry3 ConfirmSheet.buttonView）：
//   primary → primary 填充 + 白字(bubbleUserText)；
//   danger  → 灰底(surfaceSelected) + 红字(error)；
//   省略    → 灰底(surfaceSelected) + 主字(textPrimary)。
//
// detents 用 MEDIUM+LARGE（非 FIT_CONTENT）：message 长度差异大，FIT_CONTENT 首档超长 Text 不滚动会被裁；
//   MEDIUM 固定档 + message 包 Scroll 可滚动最稳（由调用点经 buildSheetOptions 透传）。
//
// 颜色映射：brand→primary / font_on_primary→bubbleUserText(唯一白 token) / warning(#E53935)→error /
//   comp_background_tertiary→surfaceSelected / font_secondary→textSecondary。
import { SheetDialog } from './SheetDialog';
import { fs, paletteOf, PaletteColors, getThemeState } from '../../theme/ThemeService';

/** 半屏确认弹窗按钮角色：primary=品牌填充 / danger=红字警示 / 省略=普通灰底 */
export type SheetButtonRole = 'primary' | 'danger';

/** 半屏确认弹窗按钮 */
export interface SheetButton {
  /** 按钮文本 */
  text: string;
  /** 按钮角色：primary 品牌填充 / danger 红字 / 省略普通灰底 */
  role?: SheetButtonRole;
  /** 点击回调（onClose 后执行） */
  action: () => void;
}

@ComponentV2
export struct ConfirmSheet {
  /** 标题 */
  @Param title: string = '';
  /** 说明正文（超长可滚动） */
  @Param message: string = '';
  /** 操作按钮（通常 1-2 个：取消 + 主动作） */
  @Param buttons: SheetButton[] = [];
  /** 关闭回调：✕ 或按钮点击时触发，父组件置 show=false */
  @Event onClose: () => void = () => {};

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  /** 按钮背景色：primary 品牌，其余灰底 */
  private btnBgColor(role: SheetButtonRole | undefined): ResourceColor {
    if (role === 'primary') { return this.c.primary; }
    return this.c.surfaceSelected;
  }

  /** 按钮文字色：primary 白字，danger 红字，其余主字色 */
  private btnFontColor(role: SheetButtonRole | undefined): ResourceColor {
    if (role === 'primary') { return this.c.bubbleUserText; }
    if (role === 'danger') { return this.c.error; }
    return this.c.textPrimary;
  }

  /** 单个按钮（胶囊型，HDS 高度 48，stateEffect 原生按压反馈） */
  @Builder buttonView(btn: SheetButton) {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Text(btn.text)
        .fontSize(fs(14))
        .fontColor(this.btnFontColor(btn.role))
    }
    .layoutWeight(1)
    .height(48)
    .backgroundColor(this.btnBgColor(btn.role))
    .onClick(() => {
      // 先关再执行：action 内若同步置 show=true，V2 最终 true → sheet 不关仅换内容
      this.onClose();
      btn.action();
    })
  }

  /** 说明正文（可滚动）+ 按钮行 */
  @Builder body() {
    Scroll() {
      Text(this.message)
        .fontSize(fs(14))
        .fontColor(this.c.textSecondary)
        .textAlign(TextAlign.Start)
        .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.TopStart)
    .scrollBar(BarState.Auto)
    .margin({ bottom: 16 })

    // 按钮行：1 个占满，2 个均分（layoutWeight(1) + space 12）
    Row({ space: 12 }) {
      ForEach(this.buttons, (btn: SheetButton, idx: number) => {
        this.buttonView(btn)
      }, (btn: SheetButton, idx: number) => `${idx}`)
    }
    .width('100%')
  }

  build() {
    // 标题栏 + 正文纵向并列（SheetDialog 不提供 content 插槽，详见 SheetDialog 注释）
    Column() {
      SheetDialog({
        title: this.title,
        showCloseButton: true,
        onClose: () => this.onClose()
      })
      Column() {
        this.body()
      }
      .padding({ left: 16, right: 16, top: 12, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
