// SheetDialog —— berry3 半窗统一标题栏（bindSheet 共用标题栏），颜色改走 JS 调色板。
//
// 【半窗标准】标题正文级 fs(20) 左对齐 Bold + 右上角灰圆关闭按钮（surfaceSelected 底）。
//   固定标题的半窗弹窗复用本标题栏即获统一外观。
//
// 【只渲染标题栏，无 content 插槽】调用方在 bindSheet builder 里用 Column 把 SheetDialog 与自身
//   内容 @Builder 纵向并列。⚠️ 不用 @BuilderParam content：V2 下方法引用传入的 @BuilderParam 在
//   update func 丢绑定 → "undefined is not callable" 闪退（berry3 Bug2 实测抓到崩溃栈）。
//
// 【白头 ↔ 灰身】标题栏独立 bg 白底（⚠️不加分割线，靠白头 ↔ 灰身(c.surface)纯色对比），白底铺满
//   sheet 宽（被 sheet 顶部圆角自然裁剪）。调用方根 Column 不加 left/right/top padding（白头要铺满），
//   内容用内层 Column 自管边距。
//
// 颜色映射（berry3 sys token → PaletteColors）：
//   font_primary→textPrimary / icon_secondary→textSecondary / comp_background_tertiary→surfaceSelected /
//   comp_background_primary→bg。
import { fs, paletteOf, PaletteColors, getThemeState } from '../../theme/ThemeService';

@ComponentV2
export struct SheetDialog {
  /** 标题文本 */
  @Param title: string = '';
  /** 是否显示右上角关闭按钮 */
  @Param showCloseButton: boolean = false;
  /** 标题栏关闭按钮点击回调 */
  @Event onClose: () => void = () => {};
  /** 是否显示左上角返回按钮（视图内导航，非关闭 sheet） */
  @Param showBackButton: boolean = false;
  /** 标题栏返回按钮点击回调 */
  @Event onBack: () => void = () => {};

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  build() {
    // Row 为唯一根（永远有根，合规）。标题 layoutWeight(1) 把关闭钮推到右侧。
    Row() {
      if (this.showBackButton) {
        // 返回钮：裸 chevron 无背景（视图内导航，弱化视觉）
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_backward'))
            .fontSize(18)
            .fontColor([this.c.textPrimary])
        }
        .width(32)
        .height(32)
        .backgroundColor(Color.Transparent)
        .margin({ right: 4 })
        .onClick(() => this.onBack())
      }
      Text(this.title)
        .fontSize(fs(20))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.c.textPrimary)
        .layoutWeight(1)
      if (this.showCloseButton) {
        // ⚠️ 灰圆用 surfaceSelected（透明圆只剩裸✕无轮廓）
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([this.c.textSecondary])
        }
        .width(32)
        .height(32)
        .backgroundColor(this.c.surfaceSelected)
        .onClick(() => this.onClose())
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 20, bottom: 12 })
    .backgroundColor(this.c.bg)
  }
}
