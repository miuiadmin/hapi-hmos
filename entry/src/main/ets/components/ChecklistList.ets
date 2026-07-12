// ChecklistList —— 对照 web/src/components/ToolCard/checklist.tsx 的 ChecklistList
// TodoWrite / update_plan 清单渲染：每项 glyph（☑/◉/☐）+ 正文，按状态着色/删除线。

import { ChecklistItem } from '../chat/Checklist';
import { paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';

@ComponentV2
struct ChecklistList {
  @Param items: ChecklistItem[] = [];
  @Param emptyLabel: string = '';

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  private glyph(status: string): string {
    if (status === 'completed') {
      return '☑';
    }
    if (status === 'in_progress') {
      return '◉';
    }
    return '☐';
  }

  private tone(status: string): string {
    if (status === 'completed') {
      return this.c.success;
    }
    if (status === 'in_progress') {
      return this.c.primary;
    }
    return this.c.textSecondary;
  }

  build() {
    Column() {
      if (this.items.length === 0) {
        if (this.emptyLabel !== '') {
          Text(this.emptyLabel)
            .fontSize(12)
            .fontColor(this.c.textSecondary)
        }
      } else {
        ForEach(this.items, (item: ChecklistItem, idx: number) => {
          Row() {
            Text(this.glyph(item.status))
              .fontSize(13)
              .fontColor(this.tone(item.status))
              .margin({ right: 6 })
            Text(item.text.trim().length > 0 ? item.text.trim() : '(空)')
              .fontSize(13)
              .fontColor(item.status === 'completed' ? this.tone('completed') : this.c.textPrimary)
              .layoutWeight(1)
              .decoration({ type: item.status === 'completed' ? TextDecorationType.LineThrough : TextDecorationType.None })
          }
          .width('100%')
        }, (item: ChecklistItem, idx: number) => item.id !== '' ? item.id : `item-${idx}`)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

export { ChecklistList };
