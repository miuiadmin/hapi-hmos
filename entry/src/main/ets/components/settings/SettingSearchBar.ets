// 设置页搜索框（对照 berry3 components/SettingSearchBar.ets）。
// 受控模式：父持 @Local query（唯一数据源），传 @Param query（只读）+ @Event onQueryChange 回写。
//   用户输入 / 点清除钮 → onQueryChange 回写父 → @Param 回灌 TextInput 显示。
import { fs, paletteOf, PaletteColors, getThemeState } from '../../theme/ThemeService';

@ComponentV2
export struct SettingSearchBar {
  /** 当前查询文本（父持，只读回灌） */
  @Param query: string = '';
  /** 占位提示 */
  @Param placeholder: string = '';
  /** 文本变化回调（含清空） */
  @Event onQueryChange: (v: string) => void = () => {};

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  build() {
    // Stack 叠层：TextInput 占满底层，放大镜绝对左、清除钮靠右
    Stack({ alignContent: Alignment.End }) {
      TextInput({ text: this.query, placeholder: this.placeholder })
        .width('100%')
        .height(40)
        .borderRadius(12)
        .backgroundColor(this.c.bg)
        // 左留放大镜位(44)，右留清除钮位(有内容时 44，无内容 16 收边)
        .padding({ left: 44, right: this.query.length > 0 ? 44 : 16 })
        .fontSize(fs(14))
        .fontColor(this.c.textPrimary)
        .placeholderColor(this.c.textTertiary)
        .onChange((v: string) => { this.onQueryChange(v); })

      // 放大镜（绝对左，垂直居中：y=(40-18)/2≈11）
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(18)
        .fontColor([this.c.textSecondary])
        .position({ x: 14, y: 11 })

      // 清除钮（仅 query 非空时；stateEffect 强制按压反馈）
      if (this.query.length > 0) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
            .fontSize(18)
            .fontColor([this.c.textTertiary])
        }
        .width(32)
        .height(32)
        .backgroundColor(Color.Transparent)
        .margin({ right: 4 })
        .onClick(() => { this.onQueryChange(''); })
      }
    }
    .width('100%')
    .height(40)
  }
}
