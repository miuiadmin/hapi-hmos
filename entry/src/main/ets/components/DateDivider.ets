// 日期分隔符组件（消息流跨日插入居中 pill）——语义/样式对照 chatcube components/DateDivider.ets（MIT，保留版权）。
// 配色改用本项目统一主题（textTertiary 文字 + border 描边 + 透明底贴合列表底色），不依赖 $r 资源。
// 文本由 formatDateDivider(timestamp) 产出（今天 / 昨天 / M月D日 / YYYY年M月D日）。
import { formatDateDivider } from '../utils/DateFormatUtils';
import { paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';

@ComponentV2
export struct DateDivider {
  // 分隔日期的时间戳（取该组首条消息的 createdAt）
  @Param timestamp: number = 0;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  build() {
    Row() {
      Text(formatDateDivider(this.timestamp))
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.textTertiary)
        .padding({ left: 10, right: 10, top: 3, bottom: 3 })
        .backgroundColor(Color.Transparent)
        .borderRadius(8)
        .border({ width: 0.5, color: this.c.border })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 10, bottom: 6 })
  }
}
