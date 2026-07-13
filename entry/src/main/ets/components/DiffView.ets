// DiffView —— 对照 web/src/components/DiffView.tsx（DiffInlineView 部分）
// 行 diff 渲染：旧/新双行号 + +/- 前缀 + 红绿背景 + +N -M 统计角标。diff 算法见 chat/Diff（LCS）。
// Edit / MultiEdit / Write(新增) 共用。宽行 maxLines(1) 截断（完整行在 sheet 纵向滚动查看）。
// V2：@Param oldString/newString/filePath/size/scrollY/maxHeight；@Computed diffLines/stats/lineNumberWidth。

import { DiffLine, computeDiff, computeDiffStats, DiffStats, splitDiffLines } from '../chat/Diff';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';

const DEFAULT_SCROLL_HEIGHT: number = 420;

@ComponentV2
struct DiffView {
  @Param oldString: string = '';
  @Param newString: string = '';
  @Param filePath: string = '';
  @Param size: string = 'compact';        // 'compact' | 'comfortable'（comfortable 用于 sheet）
  @Param scrollY: boolean = false;
  @Param maxHeight: number = 0;

  // 主题（读 @Trace isDark 建立刷新依赖）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  // 每个 @Computed 只直接读 @Param 基本类型（this.oldString/newString），不依赖其它 @Computed。
  @Computed get diffLines(): DiffLine[] {
    return computeDiff(this.oldString, this.newString);
  }

  @Computed get stats(): DiffStats {
    return computeDiffStats(computeDiff(this.oldString, this.newString));
  }

  @Computed get lineNumberWidth(): number {
    const oldLines: number = splitDiffLines(this.oldString).length;
    const newLines: number = splitDiffLines(this.newString).length;
    const a: number = String(oldLines).length;
    const b: number = String(newLines).length;
    return Math.max(a, b, 2);
  }

  private numColWidth(): number {
    return this.lineNumberWidth * 7 + 4;
  }

  private bodyMaxHeight(): number {
    return this.maxHeight > 0 ? this.maxHeight : DEFAULT_SCROLL_HEIGHT;
  }

  private lineBg(dl: DiffLine): ResourceColor {
    if (dl.type === 'added') {
      return this.c.successBg;
    }
    if (dl.type === 'removed') {
      return this.c.errorBg;
    }
    return Color.Transparent;
  }

  private lineFg(dl: DiffLine): string {
    if (dl.type === 'added') {
      return this.c.diffAdd;
    }
    if (dl.type === 'removed') {
      return this.c.diffDelete;
    }
    return this.c.codeText;
  }

  build() {
    Column() {
      // header：filePath / "DIFF" + +N -M 角标
      Row() {
        Text(this.filePath !== '' ? this.filePath : 'DIFF')
          .fontSize(fs(10))
          .fontColor(this.c.codeMuted)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        this.StatBadge(true, this.stats.additions)
        this.StatBadge(false, this.stats.deletions)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(this.c.surfaceSelected)

      // body
      if (this.scrollY) {
        Scroll() {
          this.DiffBody()
        }
        .width('100%')
        .constraintSize({ maxHeight: this.bodyMaxHeight() })
        .scrollBar(BarState.Auto)
        .align(Alignment.Top)
      } else {
        this.DiffBody()
      }
    }
    .width('100%')
    .backgroundColor(this.c.codeBg)
    .borderRadius(10)
    .clip(true)
  }

  @Builder
  StatBadge(added: boolean, value: number) {
    Text((added ? '+' : '-') + value)
      .fontSize(fs(10))
      .fontColor(added ? this.c.diffAdd : this.c.diffDelete)
      .backgroundColor(added ? this.c.successBg : this.c.errorBg)
      .borderRadius(8)
      .padding({ left: 6, right: 6, top: 1, bottom: 1 })
      .margin({ left: 4 })
  }

  @Builder
  DiffBody() {
    Column() {
      ForEach(this.diffLines, (dl: DiffLine) => {
        Row() {
          Text(dl.oldLine > 0 ? String(dl.oldLine) : '')
            .fontSize(fs(10))
            .fontColor(this.c.codeMuted)
            .width(this.numColWidth())
            .textAlign(TextAlign.End)
          Text(dl.newLine > 0 ? String(dl.newLine) : '')
            .fontSize(fs(10))
            .fontColor(this.c.codeMuted)
            .width(this.numColWidth())
            .textAlign(TextAlign.End)
            .margin({ left: 6 })
          Text((dl.type === 'added' ? '+' : dl.type === 'removed' ? '-' : ' ') + (dl.text.length > 0 ? dl.text : ' '))
            .fontSize(fs(11))
            .fontColor(this.lineFg(dl))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: 6 })
        }
        .width('100%')
        .backgroundColor(this.lineBg(dl))
        .padding({ left: 8, right: 8, top: 1, bottom: 1 })
      }, (dl: DiffLine) => `${dl.oldLine}:${dl.newLine}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

export { DiffView };
