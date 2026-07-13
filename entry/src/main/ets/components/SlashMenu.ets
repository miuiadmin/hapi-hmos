import { SlashCommand } from '../chat/SlashCommands';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';

// 斜杠补全浮层（对照 web AssistantChat 建议列表）：渲染在 InputBar 正上方，列出按评分排序的命令；
//   tap 选中即应用（ChatPage 调 applySuggestion 替换活动词）。纯展示 + 回调：建议数据/选中态由 ChatPage 传入。
//   移动端无 ↑↓ 键盘导航，故用 tap；上游 web useActiveSuggestions 的键盘选中态不移植（selectedIndex 仅作高亮预留）。

@ComponentV2
export struct SlashMenu {
  @Param suggestions: SlashCommand[] = [];
  @Param selectedIndex: number = 0;                 // 高亮项（tap 即选，预留键盘扩展）
  @Event onSelect: (cmd: SlashCommand) => void = (cmd: SlashCommand): void => {};

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  build() {
    Column() {
      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.suggestions, (cmd: SlashCommand, index: number) => {
            Row({ space: 8 }) {
              Text(`/${cmd.name}`)
                .fontSize(fs(14))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.c.primary)
                .maxLines(1)
              Text(cmd.description)
                .fontSize(fs(12))
                .fontColor(this.c.textTertiary)
                .maxLines(1)
                .textOverflow(TextOverflow.Ellipsis)
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .borderRadius(8)
            .backgroundColor(index === this.selectedIndex ? this.c.surface : this.c.bg)
            .alignItems(VerticalAlign.Center)
            .onClick(() => { this.onSelect(cmd); })
          }, (cmd: SlashCommand, index: number) => `${cmd.name}-${index}`)
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
