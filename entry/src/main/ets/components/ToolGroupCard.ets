// ToolGroupCard —— 对照 web/src/components/ToolCard/ToolGroupCard.tsx
// 连发同质工具调用折叠卡：可点头部（chevron + 主标题 + 副标题 + 徽标簇）+ 展开后各行（状态符 + getToolPresentation
//   icon/title/subtitle + 行状态徽标）+ 行点开详情 sheet（复用 ToolInputView/ToolResultView，不重写）。
//   纯展示——分组内工具恒非待批（isEligibleForToolGrouping 排除 pending/ask/request/CodexPermission），无审批动作。
// V2：@Param block；@Local open（展开态）/isDetailOpen（bindSheet 双向绑定用 !!）/detailTool（当前选中行）。
//   头部 onClick 翻 open；行 onClick 设 detailTool + 开 sheet。展开态靠稳定 group id 跨 recomputeBlocks 保活
//   （makeToolGroupBlock 锚 firstToolId → ForEach key 不变 → 组件实例复用 → @Local open 不丢）。

import { ChatBlock, ChatToolCall } from '../chat/ChatBlock';
import { ToolPresentation, getToolPresentation } from '../chat/Presentation';
import { formatGroupedHeaderTitle, formatGroupedHeaderSubtitle } from '../chat/GroupedPresentation';
import { ToolInputView, ToolResultView } from './ToolCardViews';
import { getChatSurfaceColorsState } from '../services/ChatSurfaceColorsService';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';

@ComponentV2
struct ToolGroupCard {
  @Param block: ChatBlock = new ChatBlock();
  @Local open: boolean = false;
  @Local isDetailOpen: boolean = false;
  @Local detailTool: ChatToolCall = new ChatToolCall();

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  private get summary() {
    return this.block.groupSummary;
  }

  private get headerTitle(): string {
    return formatGroupedHeaderTitle(this.block.groupTools);
  }

  private get headerSubtitle(): string {
    return formatGroupedHeaderSubtitle(this.summary);
  }

  // 行 tool（child.tool 恒非空——分组仅收 tool-call 块）；空时退空 tool 占位
  private presentationOf(child: ChatBlock): ToolPresentation {
    const tool: ChatToolCall | null = child.tool;
    return tool === null ? new ToolPresentation() : getToolPresentation(tool);
  }

  // 状态符号（镜像 ToolCard.statusGlyph）：🔒 pending / ✓ completed / ✕ error / ● running
  private stateGlyph(child: ChatBlock): string {
    const tool: ChatToolCall | null = child.tool;
    if (tool === null) {
      return '';
    }
    if (tool.permission !== null && tool.permission.status === 'pending') {
      return '🔒';
    }
    if (tool.state === 'completed') {
      return '✓';
    }
    if (tool.state === 'error') {
      return '✕';
    }
    return '●';
  }

  private stateColor(child: ChatBlock): string {
    const tool: ChatToolCall | null = child.tool;
    if (tool === null) {
      return this.c.textTertiary;
    }
    if (tool.permission !== null && tool.permission.status === 'pending') {
      return this.c.warning;
    }
    if (tool.state === 'error') {
      return this.c.error;
    }
    if (tool.state === 'running') {
      return this.c.primary;
    }
    return this.c.success;
  }

  // 行状态徽标（对照上游 RowStatusBadge）：仅 error/running/pending 显；completed 不显
  private rowBadgeLabel(child: ChatBlock): string {
    const tool: ChatToolCall | null = child.tool;
    if (tool === null) {
      return '';
    }
    if (tool.state === 'error') {
      return t('toolGroup.rowStatus.error');
    }
    if (tool.state === 'running') {
      return t('toolGroup.rowStatus.running');
    }
    if (tool.permission !== null && tool.permission.status === 'pending') {
      return t('toolGroup.rowStatus.pending');
    }
    return '';
  }

  private openDetail(child: ChatBlock): void {
    const tool: ChatToolCall | null = child.tool;
    if (tool !== null) {
      this.detailTool = tool;
      this.isDetailOpen = true;
    }
  }

  @Builder
  Badge(text: string, fg: string, bg: string) {
    Text(text)
      .fontSize(fs(11))
      .fontColor(fg)
      .backgroundColor(bg)
      .borderRadius(8)
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
  }

  @Builder
  Header() {
    Row({ space: 8 }) {
      // chevron + 标题 + 副标题
      Column() {
        Row({ space: 6 }) {
          Text(this.open ? '▾' : '▸')
            .fontSize(fs(11))
            .fontColor(this.c.textTertiary)
          if (this.headerTitle !== '') {
            Text(this.headerTitle)
              .fontSize(fs(13))
              .fontColor(this.c.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
        }
        .width('100%')
        if (this.headerSubtitle !== '') {
          Text(this.headerSubtitle)
            .fontSize(fs(11))
            .fontColor(this.c.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 徽标簇（对照上游：toolCount 恒显；running/pending/error 按计数；fileTargets 文件数）
      Row({ space: 4 }) {
        this.Badge(
          t('toolGroup.toolCount', { n: this.summary.totalTools }),
          this.c.textTertiary,
          this.c.surfaceSelected
        )
        if (this.summary.runningCount > 0) {
          this.Badge(
            t('toolGroup.badge.running', { n: this.summary.runningCount }),
            this.c.primary,
            this.c.surfaceSelected
          )
        }
        if (this.summary.pendingCount > 0) {
          this.Badge(
            t('toolGroup.badge.pending', { n: this.summary.pendingCount }),
            this.c.warning,
            this.c.surfaceSelected
          )
        }
        if (this.summary.errorCount > 0) {
          this.Badge(
            t('toolGroup.badge.error', { n: this.summary.errorCount }),
            this.c.error,
            this.c.errorBg
          )
        }
        if (this.summary.fileTargets.length > 0) {
          this.Badge(
            t('toolGroup.badge.fileTargets', { n: this.summary.fileTargets.length }),
            this.c.textTertiary,
            this.c.surfaceSelected
          )
        }
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  GroupRow(child: ChatBlock) {
    Row({ space: 8 }) {
      Text(this.stateGlyph(child))
        .fontSize(fs(13))
        .fontColor(this.stateColor(child))
      Text(this.presentationOf(child).icon)
        .fontSize(fs(13))
      Column() {
        Text(this.presentationOf(child).title)
          .fontSize(fs(13))
          .fontColor(this.c.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.presentationOf(child).subtitle !== '') {
          Text(this.presentationOf(child).subtitle)
            .fontSize(fs(11))
            .fontColor(this.c.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 1 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.rowBadgeLabel(child) !== '') {
        Text(this.rowBadgeLabel(child))
          .fontSize(fs(10))
          .fontColor(this.stateColor(child))
          .backgroundColor(this.c.surfaceSelected)
          .borderRadius(8)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      }
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(12)
    .backgroundColor(this.c.bg)
    .border({ width: 0.5, color: this.c.border })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.openDetail(child); })
  }

  @Builder
  DetailSheet() {
    Scroll() {
      Column() {
        Text(t('tool.input'))
          .fontSize(fs(11))
          .fontColor(this.c.textTertiary)
          .width('100%')
          .margin({ bottom: 6 })
        ToolInputView({ tool: this.detailTool, surface: 'dialog' })

        Text(t('tool.result'))
          .fontSize(fs(11))
          .fontColor(this.c.textTertiary)
          .width('100%')
          .margin({ top: 16, bottom: 6 })
        ToolResultView({ tool: this.detailTool, surface: 'dialog' })
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Auto)
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST,
    })
  }

  build() {
    Column() {
      // 头部（可点切换 open）
      Row() {
        this.Header()
      }
      .width('100%')
      .padding({ left: 12, right: 8, top: 10, bottom: 10 })
      .onClick(() => { this.open = !this.open; })

      if (this.open) {
        Column({ space: 8 }) {
          ForEach(this.block.groupTools, (child: ChatBlock) => {
            this.GroupRow(child)
          }, (child: ChatBlock) => child.id)
        }
        .width('100%')
        .padding({ left: 8, right: 8, bottom: 10 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .backgroundColor(getChatSurfaceColorsState().toolGroupBg || this.c.surface)
    .borderRadius(20)
    .bindSheet(this.isDetailOpen!!, this.DetailSheet(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      blurStyle: BlurStyle.Thick,
      title: { title: getToolPresentation(this.detailTool).title },
    })
  }
}

export { ToolGroupCard };
