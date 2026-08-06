import { ChatMessage, formatScheduledIn } from '../models/Message';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t, kv } from '../i18n/I18nService';

// 排队消息条（对照 web AssistantChat/QueuedMessagesBar.tsx）：渲染在 composer/InputBar 正上方，
//   列出所有「已发但未被 CLI 消费」的用户消息（即时排队 + 定时共用 invokedAt=0 状态）。
//   每行：clamped 文本 + 编辑✎ + 取消✕；定时行（scheduledAt>0 且未到时间）额外显「X 后发送」。
//   纯展示 + 回调：排序/数据由 ChatPage 传入（sortQueuedMessages），编辑/取消委托回 ChatPage。
//   挂载与 thread 互斥：ChatPage.recomputeBlocks 已把 isQueued 行滤出 thread，故仅在此处可见。
//
//   样式（chatcube 对齐 + 对照本项目 ComposerToolbar chip / chatcube ScreenshotBanner 浮卡范式）：
//     单块悬浮面板——surface 底 + 0.5vp border + 轻 shadow + r14；头「⏲ 排队中 N」+ 每行消息预览
//     + squircle(r9) 编辑/取消按钮带按压态（surfaceSelected 底 + scale 0.9，对照 composer ModelButton）。
//   ★ msg 文本 Column 仍 layoutWeight(1)（Row 横轴主方向占宽，正确）；勿给 Text 加 layoutWeight
//     （曾致满屏灰板，见 commit 1de91a3 / memory chat-queued-grayboard-layoutweight）。

@ComponentV2
export struct QueuedMessagesBar {
  @Param queued: ChatMessage[] = [];           // 已排序的排队消息（isQueued）
  @Event onEdit: (m: ChatMessage) => void = (m: ChatMessage): void => {};
  @Event onCancel: (m: ChatMessage) => void = (m: ChatMessage): void => {};
  @Local pressedKey: string = '';              // 按压态：`${id}#edit` / `${id}#cancel`（仅含点中按钮）

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }
  private get isDark(): boolean { return getThemeState().isDark; }

  // 面板阴影色（对照 ComposerToolbar.chipShadow：暗 0.20 / 亮 rgba(15,23,42,0.06)）。
  private panelShadow(): string {
    return this.isDark ? 'rgba(0, 0, 0, 0.20)' : 'rgba(15, 23, 42, 0.06)';
  }
  private isPressed(m: ChatMessage, kind: string): boolean {
    return this.pressedKey === `${m.id}#${kind}`;
  }

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
      // 头：排队计数（对照 web「Queued」label + 计数）
      Row({ space: 5 }) {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(fs(12))
          .fontColor([this.c.textTertiary])
        Text(t('queued.count', kv('count', this.queued.length)))
          .fontSize(fs(12))
          .fontColor(this.c.textTertiary)
      }

      // 消息行
      ForEach(this.queued, (m: ChatMessage) => {
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text(m.text)
              .fontSize(fs(13))
              .fontColor(this.c.textPrimary)
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .lineHeight(fs(18))
              .width('100%')
            if (this.scheduleLabel(m) !== '') {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.clock'))
                  .fontSize(fs(11))
                  .fontColor([this.c.warning])
                Text(this.scheduleLabel(m))
                  .fontSize(fs(11))
                  .fontColor(this.c.warning)
              }
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          // 编辑（回填 composer + 恢复定时 + 移除本行）—— 系统符号 square_and_pencil（HMOS 已验证字形）
          this.QueueActionButton(m, 'edit', false)

          // 取消（DELETE 排队消息；乐观行未落地时禁用）
          this.QueueActionButton(m, 'cancel', !this.canCancel(m))
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }, (m: ChatMessage) => m.id)
    }
    .width('100%')
    .margin({ top: 2, bottom: 6 })
    .padding({ left: 12, right: 6, top: 10, bottom: 10 })
    .borderRadius(14)
    .backgroundColor(this.c.card)
    .border({ width: 0.5, color: this.c.border })
    .shadow({ radius: 12, color: this.panelShadow(), offsetX: 0, offsetY: 3 })
  }

  // 行内方块按钮（编辑 / 取消）：squircle r9 + 按压态（surfaceSelected 底 + scale 0.9），
  //   对照 composer ModelButton 按压范式；glyph/颜色按 kind 内联（$r 不作 @Builder 入参，避冻结坑）。
  @Builder
  QueueActionButton(m: ChatMessage, kind: string, disabled: boolean): void {
    Row() {
      if (kind === 'edit') {
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(fs(15))
          .fontColor([this.c.textSecondary])
      } else {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(fs(14))
          .fontColor([disabled ? this.c.textTertiary : this.c.error])
      }
    }
    .width(30)
    .height(30)
    .justifyContent(FlexAlign.Center)
    .borderRadius(9)
    .backgroundColor(this.isPressed(m, kind) ? this.c.surfaceSelected : Color.Transparent)
    .scale({ x: this.isPressed(m, kind) ? 0.9 : 1, y: this.isPressed(m, kind) ? 0.9 : 1 })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .opacity(disabled ? 0.4 : 1)
    .onTouch((event: TouchEvent) => {
      if (disabled) { return; }
      if (event.type === TouchType.Down) {
        this.pressedKey = `${m.id}#${kind}`;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedKey = '';
      }
    })
    .onClick(() => {
      if (disabled) { return; }
      if (kind === 'edit') { this.onEdit(m); } else { this.onCancel(m); }
    })
  }
}
