// 设置页分组标题（对照 berry3 components/SettingSectionTitle.ets）。
// 纯展示，无按压态。作为独立 ListItem 浮在 ListItemGroup 之上（坐在页面 surface 底上），保证白卡纯净。
// 放置：List 内 ListItem { SettingSectionTitle({text}) } 紧跟其后 ListItemGroup。
import { fs, paletteOf, PaletteColors, getThemeState } from '../../theme/ThemeService';

@ComponentV2
export struct SettingSectionTitle {
  /** 标题文本 */
  @Param text: string = '';
  /** 相对 List 内容区左缘的内缩（vp） */
  @Param insetLeft: number = 6;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  build() {
    Text(this.text)
      .fontSize(fs(13))
      .fontColor(this.c.textSecondary)
      // margin top6/bottom0：标题贴近下方卡片（标题→卡 = List space12）
      .margin({ left: this.insetLeft, top: 6, bottom: 0 })
  }
}
