import { MarkdownText } from './MarkdownText';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';
import { getReasoningCollapseState } from '../services/ReasoningCollapseService';

// ReasoningBubble —— agent 思考过程块
// 对照上游 web/src/components/assistant-ui/reasoning.tsx（ReasoningGroup 折叠容器 + Reasoning markdown 体）
// + chatcube MessageBubble reasoning（流式自动预览 + 指示）双参考。
//
// 语义：
//   - 默认收起（历史 reasoning 仅显「思考过程」头）；流式中（isStreaming）自动展开 + LoadingProgress 指示；
//   - 点 header 手动展开/折叠（expanded）；
//   - 体走 MarkdownText，容器 surface 浅底 + rounded-16（同 agent 气泡/工具卡观感）。
//
// 简化取舍（已记）：auto-open 用 `expanded || isStreaming`——流式展开、结束后收起，
//   未做上游的「结束后保持展开」（避 @Monitor 监听 @Param 的复杂度；移动端收起更聚焦正文）。需要可后续加。
//   另：MarkdownText 正文按默认字号/配色渲染（未做上游 13.5px+muted），靠容器浅底+标签区分；muted 可后续加。
@ComponentV2
export struct ReasoningBubble {
  @Param text: string = '';
  @Param isStreaming: boolean = false;   // 末块 reasoning 且会话 thinking 中（ChatPage.isReasoningStreaming 计算）
  @Local expanded: boolean = false;

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  // 是否展开体：手动展开，或流式中自动展开——但「推理默认折叠」开关开启时流式也不自动展开
  //   （对照上游 #1385 useReasoningCollapse：reasoningCollapsed=true 时 nextOpen=!false 恒收起，含流式）。
  //   读 @Trace collapsedByDefault 建立刷新依赖：设置页切换即时生效。
  @Computed get shouldExpand(): boolean {
    return this.expanded || (this.isStreaming && !getReasoningCollapseState().collapsedByDefault);
  }

  build() {
    Column() {
      // header：箭头 + 标签 + 流式指示
      Row() {
        SymbolGlyph(this.shouldExpand ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(fs(11))
          .fontColor([this.c.textTertiary])
          .margin({ right: 6 })
        Text(t('reasoning.label'))
          .fontSize(fs(12))
          .fontColor(this.c.textSecondary)
          .layoutWeight(1)
        if (this.isStreaming) {
          LoadingProgress()
            .width(12)
            .height(12)
            .color(this.c.textTertiary)
            .margin({ left: 6 })
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 9, bottom: 9 })
      .onClick(() => {
        this.expanded = !this.expanded;
      })

      // 展开体（含流式中，除非「推理默认折叠」开启）：markdown 正文，顶部分隔线
      if (this.shouldExpand) {
        Column() {
          // 流式增量：isStreaming 时 isInputEnded=false + incrementalAnalysis=true → CJMarkdown 增量重渲（防冻结根因）
          MarkdownText({
            content: this.text,
            isInputEnded: !this.isStreaming,
            incrementalAnalysis: this.isStreaming
          })
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 10 })
        .border({ width: { top: 1 }, color: this.c.border })
      }
    }
    .width('100%')
    .backgroundColor(this.c.card)
    .border({ width: 0.5, color: this.c.border })
    .borderRadius(16)
  }
}
