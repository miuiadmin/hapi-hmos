import { TodoItem } from '../models/Types';
import { ChecklistItem } from '../chat/Checklist';
import { ChecklistList } from './ChecklistList';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';

// 会话内待办清单面板（鸿蒙端增值：上游 web 不独立渲染 session.todos，仅列表项显 todoProgress
//   摘要 + 工具卡显 TodoWrite。本面板在对话页内提供「进度+折叠清单」一体化查看）。
//   todos 是 Session 运行时字段（agent TodoWrite 上报），纯只读展示。
//   由 ChatPage 在 session.todos.length > 0 时渲染于消息列表上方（与 TeamPanel 同位）。
// 列表体复用 ChecklistList（☑/◉/☐ + 正文 + 完成删除线），与工具卡内 TodoWrite 清单同款样式。
// 折叠头：📋 待办 {done}/{total} [▾]；与 TeamPanel 范式一致。

@ComponentV2
export struct TodoPanel {
  @Param todos: TodoItem[] = [];
  @Local expanded: boolean = false;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  // 已完成数（status==='completed'）
  private completedCount(): number {
    let n: number = 0;
    for (let i = 0; i < this.todos.length; i++) {
      if (this.todos[i].status === 'completed') { n = n + 1; }
    }
    return n;
  }

  // TodoItem[] → ChecklistItem[]：content→text / id→id（空用 todo-${i} 兜底 key）/ status 同枚举。
  //   复用 ChecklistList 渲染，与工具卡 TodoWrite 清单样式统一。
  private checklistItems(): ChecklistItem[] {
    const out: ChecklistItem[] = [];
    for (let i = 0; i < this.todos.length; i++) {
      const t: TodoItem = this.todos[i];
      const item: ChecklistItem = new ChecklistItem();
      item.text = t.content;
      item.id = t.id !== '' ? t.id : `todo-${i}`;
      if (t.status === 'completed') {
        item.status = 'completed';
      } else if (t.status === 'in_progress') {
        item.status = 'in_progress';
      } else {
        item.status = 'pending';
      }
      out.push(item);
    }
    return out;
  }

  private toggle(): void { this.expanded = !this.expanded; }

  build() {
    Column() {
      // 折叠头（点击展开/收起，对照 TeamPanel header）
      Row({ space: 6 }) {
        Text('📋').fontSize(fs(14))
        Text('待办')
          .fontSize(fs(13))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.textPrimary)
          .layoutWeight(1)
        Text(`${this.completedCount()}/${this.todos.length}`)
          .fontSize(fs(11))
          .fontColor(this.c.textTertiary)
        Text('▾')
          .fontSize(fs(11))
          .fontColor(this.c.textTertiary)
          .rotate({ angle: this.expanded ? 180 : 0 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 9, bottom: 9 })
      .borderRadius(10)
      .backgroundColor(this.c.surface)
      .alignItems(VerticalAlign.Center)
      .onClick(() => { this.toggle(); })

      // 展开体：复用 ChecklistList 渲染清单项
      if (this.expanded) {
        Column() {
          ChecklistList({ items: this.checklistItems(), emptyLabel: '' })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 6, bottom: 8 })
        .margin({ top: 4 })
        .borderRadius(10)
        .backgroundColor(this.c.surface)
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
  }
}
