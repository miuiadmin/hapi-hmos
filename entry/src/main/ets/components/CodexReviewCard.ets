import { CodexReview, CodexReviewFinding, formatReviewPercent, formatReviewLocation, reviewPriorityColor } from '../chat/CodexReview';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';

// CodexReviewCard —— 对照 web/src/components/AssistantChat/messages/CodexReviewCard.tsx
// Codex agent 偶把 review JSON 当文本发出；parse 嗅探命中 → codex-review 块 → 本卡渲染结构化结果：
//   header（标题 + overallCorrectness 徽章 + overall 置信度 % 徽章）+ overallExplanation 段 +
//   findings 计数 + findings 列表（P{n} 优先级徽章[0/1 红·2 琥珀·余中性] + 粗体标题 + 正文 + 位置 mono + 置信度 %）。
//   位置非可点链接（faithful：上游仅 mono span，无跳转）。
// V2：@Param review（解析后的 CodexReview）；主题读 @Trace isDark 即时刷新。

@ComponentV2
export struct CodexReviewCard {
  @Param review: CodexReview = new CodexReview();

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  // 优先级 → 徽章文字色（0/1 error、2 warning、余 textTertiary）
  private badgeTextColor(priority: number | null): string {
    const kind = reviewPriorityColor(priority);
    if (kind === 'error') {
      return this.c.error;
    }
    if (kind === 'warning') {
      return this.c.warning;
    }
    return this.c.textTertiary;
  }

  // 优先级 → 徽章背景色（error → errorBg；warning/neutral → surfaceSelected）
  private badgeBgColor(priority: number | null): string {
    const kind = reviewPriorityColor(priority);
    if (kind === 'error') {
      return this.c.errorBg;
    }
    return this.c.surfaceSelected;
  }

  @Builder
  NeutralBadge(text: string, textColor: string, bgColor: string) {
    Text(text)
      .fontSize(fs(11))
      .fontWeight(FontWeight.Medium)
      .fontColor(textColor)
      .backgroundColor(bgColor)
      .borderRadius(6)
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .maxLines(1)
      .textOverflow(TextOverflow.Ellipsis)
  }

  @Builder
  FindingItem(finding: CodexReviewFinding) {
    Column() {
      // 标题行：优先级徽章（priority 非 null）+ 粗体标题
      Row() {
        if (finding.priority !== null) {
          Text(`P${finding.priority}`)
            .fontSize(fs(11))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.badgeTextColor(finding.priority))
            .backgroundColor(this.badgeBgColor(finding.priority))
            .borderRadius(6)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .margin({ right: 8 })
        }
        Text(finding.title)
          .fontSize(fs(13))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.c.textPrimary)
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 正文
      Text(finding.body)
        .fontSize(fs(13))
        .fontColor(this.c.textPrimary)
        .width('100%')
        .margin({ top: 8 })

      // 位置 + 置信度（hint 色，换行横排）
      Row() {
        if (this.findingLocation(finding) !== null) {
          Text(this.findingLocation(finding))
            .fontSize(fs(11))
            .fontColor(this.c.codeMuted)
            .fontFamily('monospace')
            .maxLines(1)
            .textOverflow(TextOverflow.Ellipsis)
            .layoutWeight(1)
        } else {
          Text(t('codexReview.location.missing'))
            .fontSize(fs(11))
            .fontColor(this.c.textTertiary)
            .layoutWeight(1)
        }
        if (this.findingConfidence(finding) !== null) {
          Text(t('codexReview.confidence', { value: this.findingConfidence(finding) }))
            .fontSize(fs(11))
            .fontColor(this.c.textTertiary)
            .margin({ left: 12 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(12)
    .borderRadius(10)
    .backgroundColor(this.c.bg)
    .border({ width: 0.5, color: this.c.border })
  }

  // 位置串（null = 无 filePath，调用方显「无位置」）
  private findingLocation(finding: CodexReviewFinding): string | null {
    return formatReviewLocation(finding);
  }

  // 单条置信度 %（null = 无/非有限，隐藏）
  private findingConfidence(finding: CodexReviewFinding): string | null {
    return formatReviewPercent(finding.confidenceScore);
  }

  build() {
    Column() {
      // header：标题 + overallCorrectness 徽章 + overall 置信度 % 徽章
      Row() {
        Text(t('codexReview.title'))
          .fontSize(fs(13))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.textPrimary)
          .layoutWeight(1)
        if (this.review.overallCorrectness !== null && this.review.overallCorrectness !== '') {
          this.NeutralBadge(this.review.overallCorrectness, this.c.textPrimary, this.c.bg)
        }
        if (formatReviewPercent(this.review.overallConfidenceScore) !== null) {
          this.NeutralBadge(formatReviewPercent(this.review.overallConfidenceScore) as string, this.c.textTertiary, this.c.bg)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .border({ width: 0.5, color: this.c.border })

      // body
      Column() {
        if (this.review.overallExplanation !== null && this.review.overallExplanation !== '') {
          Text(this.review.overallExplanation)
            .fontSize(fs(13))
            .fontColor(this.c.textPrimary)
            .width('100%')
            .margin({ bottom: 12 })
        }
        Text(t('codexReview.findings', { count: this.review.findings.length }))
          .fontSize(fs(11))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.textTertiary)
          .width('100%')
        if (this.review.findings.length > 0) {
          Column({ space: 8 }) {
            ForEach(this.review.findings, (finding: CodexReviewFinding) => {
              this.FindingItem(finding)
            }, (finding: CodexReviewFinding, index: number): string => `${finding.title}:${index}`)
          }
          .width('100%')
          .margin({ top: 8 })
        }
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor(this.c.surface)
    .border({ width: 0.5, color: this.c.border })
    .clip(true)
  }
}
