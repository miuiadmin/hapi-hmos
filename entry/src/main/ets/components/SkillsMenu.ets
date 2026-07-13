import { SkillItem } from '../models/Types';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';

// $ 技能补全浮层（对照 web AssistantChat 建议列表；结构镜像 SlashMenu）：
//   渲染在 InputBar 正上方，列出按评分排序的技能；tap 选中即应用（ChatPage 调 applySuggestion 替换活动词）。
//   纯展示 + 回调：建议数据/选中态由 ChatPage 传入（skillSuggestions(skills, query, recentMap)）。
//   移动端无 ↑↓ 键盘导航，用 tap；上游键盘选中态不移植（selectedIndex 仅作高亮预留）。

@ComponentV2
export struct SkillsMenu {
  @Param items: SkillItem[] = [];
  @Param selectedIndex: number = 0;                    // 高亮项（tap 即选，预留键盘扩展）
  @Event onSelect: (skill: SkillItem) => void = (skill: SkillItem): void => {};

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  build() {
    Column() {
      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.items, (skill: SkillItem, index: number) => {
            Row({ space: 8 }) {
              Text(`$${skill.name}`)
                .fontSize(fs(14))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.c.primary)
                .maxLines(1)
              Text(skill.description)
                .fontSize(fs(12))
                .fontColor(this.c.textTertiary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .borderRadius(8)
            .backgroundColor(index === this.selectedIndex ? this.c.surface : this.c.bg)
            .alignItems(VerticalAlign.Center)
            .onClick(() => { this.onSelect(skill); })
          }, (skill: SkillItem, index: number) => `${skill.name}-${index}`)
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
