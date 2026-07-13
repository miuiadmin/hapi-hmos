import { ConversationOutlineItem } from '../chat/Outline';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { formatClock } from '../utils/DateFormatUtils';
import { t } from '../i18n/I18nService';

// 对话大纲抽屉（对照 web HappyThread.tsx ConversationOutlinePanel）：
//   列出所有用户提问（buildConversationOutline 产出），tap 即 onJump(blockId) 跳转该消息。
//   纯展示 + 回调；空态「暂无用户消息」。每项：蓝点 + label(2 行省略) + 时间。
@ComponentV2
export struct OutlinePanel {
  @Param items: ConversationOutlineItem[] = [];
  @Event onJump: (blockId: string) => void = (blockId: string): void => {};

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  @Builder
  private empty() {
    Column() {
      Text(t('outline.empty'))
        .fontSize(fs(14))
        .fontColor(this.c.textTertiary)
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Scroll() {
      Column() {
        Text(t('outline.title'))
          .fontSize(fs(17))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.textPrimary)
          .width('100%')
          .padding({ left: 4, top: 4, bottom: 8 })

        if (this.items.length === 0) {
          this.empty()
        } else {
          ForEach(this.items, (item: ConversationOutlineItem) => {
            Row({ space: 10 }) {
              // 蓝点（对照上游蓝点 + USER 标签；项目无 Circle 先例，用圆角方点）
              Column()
                .width(6)
                .height(6)
                .borderRadius(3)
                .backgroundColor(this.c.primary)
                .margin({ top: 7 })
              Column() {
                Text(item.label)
                  .fontSize(fs(14))
                  .fontColor(this.c.textPrimary)
                  .maxLines(2)
                  .textOverflow(TextOverflow.Ellipsis)
                  .width('100%')
                if (item.createdAt > 0) {
                  Text(formatClock(item.createdAt))
                    .fontSize(fs(11))
                    .fontColor(this.c.textTertiary)
                    .margin({ top: 2 })
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .borderRadius(8)
            .alignItems(VerticalAlign.Top)
            .onClick(() => { this.onJump(item.blockId); })
          }, (item: ConversationOutlineItem) => item.id)
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
