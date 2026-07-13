import { ChatMessage, formatScheduledIn } from '../models/Message';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';

// 排队消息条（对照 web AssistantChat/QueuedMessagesBar.tsx）：渲染在 composer/InputBar 正上方，
//   列出所有「已发但未被 CLI 消费」的用户消息（即时排队 + 定时共用 invokedAt=0 状态）。
//   每行：clamped 文本 + 编辑✎ + 取消✕；定时行（scheduledAt>0 且未到时间）额外显「X 后发送」。
//   纯展示 + 回调：排序/数据由 ChatPage 传入（sortQueuedMessages），编辑/取消委托回 ChatPage。
//   挂载与 thread 互斥：ChatPage.recomputeBlocks 已把 isQueued 行滤出 thread，故仅在此处可见。

@ComponentV2
export struct QueuedMessagesBar {
  @Param queued: ChatMessage[] = [];           // 已排序的排队消息（isQueued）
  @Event onEdit: (m: ChatMessage) => void = (m: ChatMessage): void => {};
  @Event onCancel: (m: ChatMessage) => void = (m: ChatMessage): void => {};

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  // 定时剩余标签（scheduledAt>0 且未到时间才显；ArkUI build 内取 now，随 bar 重建刷新）
  private scheduleLabel(m: ChatMessage): string {
    if (m.scheduledAt <= 0) { return ''; }
    return formatScheduledIn(m.scheduledAt, Date.now());
  }

  // 取消按钮可用：需服务端 id（乐观行尚未落地，无法 DELETE）
  private canCancel(m: ChatMessage): boolean {
    return !m.isOptimistic && m.id !== '';
  }

  build() {
    Column({ space: 6 }) {
      // 头：排队计数
      Row({ space: 6 }) {
        Text('🕓').fontSize(fs(12))
        Text(`排队中 ${this.queued.length}`)
          .fontSize(fs(12))
          .fontColor(this.c.textTertiary)
        Blank()
      }
      .width('100%')

      ForEach(this.queued, (m: ChatMessage) => {
        Row({ space: 8 }) {
          Column({ space: 3 }) {
            Text(m.text)
              .fontSize(fs(13))
              .fontColor(this.c.textPrimary)
              .maxLines(3)
              .textOverflow(TextOverflow.Ellipsis)
              .layoutWeight(1)
              .width('100%')
            if (this.scheduleLabel(m) !== '') {
              Text(`⏰ ${this.scheduleLabel(m)}`)
                .fontSize(fs(11))
                .fontColor(this.c.warning)
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          // 编辑（回填 composer + 恢复定时 + 移除本行）
          Text('✎')
            .fontSize(fs(16))
            .fontColor(this.c.textSecondary)
            .width(30)
            .height(30)
            .textAlign(TextAlign.Center)
            .borderRadius(15)
            .onClick(() => { this.onEdit(m); })

          // 取消（DELETE 排队消息；乐观行未落地时禁用）
          Text('✕')
            .fontSize(fs(15))
            .fontColor(this.canCancel(m) ? this.c.error : this.c.textTertiary)
            .width(30)
            .height(30)
            .textAlign(TextAlign.Center)
            .borderRadius(15)
            .opacity(this.canCancel(m) ? 1 : 0.4)
            .onClick(() => {
              if (this.canCancel(m)) { this.onCancel(m); }
            })
        }
        .width('100%')
        .padding({ left: 12, right: 8, top: 8, bottom: 8 })
        .borderRadius(10)
        .backgroundColor(this.c.surface)
        .alignItems(VerticalAlign.Top)
      }, (m: ChatMessage) => m.id)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 2, bottom: 2 })
  }
}
