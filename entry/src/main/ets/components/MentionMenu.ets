import { FileSearchItem } from '../models/Types';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';

// @ 文件提及联想浮层（输入 @ 触发；对照 SlashMenu 形态，数据源为 GET /sessions/:id/files?query=）：
//   渲染在 InputBar 正上方，列按 fileName 匹配的文件；tap 选中即把 @filePath 插入输入框（ChatPage selectMention）。
//   纯展示 + 回调：联想结果/选中态由 ChatPage 传入；移动端无 ↑↓，导航靠 tap。
//   语义对照上游 Files 页：fileName=显示名（主）、filePath=相对路径（副，agent 读它定位）、fullPath=绝对路径。

@ComponentV2
export struct MentionMenu {
  @Param items: FileSearchItem[] = [];
  @Param selectedIndex: number = 0;                  // 高亮项（tap 即选，预留键盘扩展）
  @Event onSelect: (item: FileSearchItem) => void = (item: FileSearchItem): void => {};

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  build() {
    Column() {
      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.items, (item: FileSearchItem, index: number) => {
            Row({ space: 8 }) {
              Text(item.fileType === 'folder' ? '📁' : '📄')
                .fontSize(fs(14))
              Column() {
                Text(item.fileName)
                  .fontSize(fs(14))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.c.textPrimary)
                  .maxLines(1)
                  .textOverflow(TextOverflow.Ellipsis)
                if (item.filePath !== '' && item.filePath !== item.fileName) {
                  Text(item.filePath)
                    .fontSize(fs(11))
                    .fontColor(this.c.textTertiary)
                    .maxLines(1)
                    .textOverflow(TextOverflow.Ellipsis)
                    .margin({ top: 1 })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(8)
            .backgroundColor(index === this.selectedIndex ? this.c.surface : this.c.bg)
            .alignItems(VerticalAlign.Center)
            .onClick(() => { this.onSelect(item); })
          }, (item: FileSearchItem, index: number) => `${item.fullPath}-${index}`)
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 264 })
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .borderRadius(12)
    .backgroundColor(this.c.bg)
    .border({ width: 1, color: this.c.border })
  }
}
