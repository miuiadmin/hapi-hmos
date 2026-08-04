// 设置页分组下方说明文案（对照 berry3 components/SettingFooter.ets）。
// 纯展示，空串不渲染。放分组卡片之下、与 List padding 对齐（独立 ListItem）。
import { fs, paletteOf, PaletteColors, getThemeState } from '../../theme/ThemeService';

@ComponentV2
export struct SettingFooter {
  /** 说明文案（空串不渲染） */
  @Param text: string = '';
  /** 相对 List 内容区左缘的内缩（vp），默认对齐 SettingSectionTitle */
  @Param insetLeft: number = 6;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  build() {
    if (this.text.length > 0) {
      Text(this.text)
        .fontSize(fs(13))
        .fontColor(this.c.textTertiary)
        .lineHeight(18)
        .width('100%')
        .margin({ left: this.insetLeft, right: this.insetLeft, top: 0, bottom: 6 })
    }
  }
}
