// CodeBlock —— 对照 web/src/components/CodeBlock.tsx（上游 Shiki 高亮；本项目自包含轻量扫描器）
// 等宽文本 + 行号 + 长内容折叠（>18 行或 >1800 字符 → 折叠到 260 + 「已截断」角标）。
// 宽行按 maxLines(1) 截断（窄屏取舍：完整内容在详情 sheet 可纵向滚动查看）。
// 语法高亮：逐行 tokenizeLine → 按 token 类型染色的 Span 序列（chat/CodeHighlight 纯层；
//   keyword=primary/string=success/number=warning/comment=codeMuted/plain=codeText）。
//   text 语言全 plain（零回归）；大文件（>20k 字符）降级 text 免扫描 jank。
// V2：@Param code/language/title/collapseLongContent/scrollY/maxHeight；@Computed allLines/isCollapsed/visibleLines/label。

import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';
import { tokenizeLine, HighlightToken, HighlightTokenType } from '../chat/CodeHighlight';

const COLLAPSE_LINE_THRESHOLD: number = 18;
const COLLAPSE_CHAR_THRESHOLD: number = 1800;
const COLLAPSED_HEIGHT: number = 260;
const SCROLL_HEIGHT: number = 420;
const HIGHLIGHT_CHAR_CAP: number = 20000;   // 超此长度降级 text（免逐行扫描 jank）

// 按行切分（对照上游 countCodeLines/splitDiffLines）：空串 → ['']；末尾 '\n' 产生的空串丢弃
function splitCodeLines(code: string): string[] {
  if (code.length === 0) {
    return [''];
  }
  const lines: string[] = code.split('\n');
  if (lines.length > 1 && lines[lines.length - 1] === '') {
    lines.splice(lines.length - 1, 1);
  }
  return lines;
}

@ComponentV2
struct CodeBlock {
  @Param code: string = '';
  @Param language: string = 'text';      // 语法高亮 + label 兜底（CodeHighlight 归一）
  @Param title: string = '';             // 非空时作 label
  @Param collapseLongContent: boolean = false;
  @Param scrollY: boolean = false;
  @Param maxHeight: number = 0;          // 0 = 默认（折叠 260 / 滚动 420）

  // 主题（读 @Trace isDark 建立刷新依赖）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  // 每个 @Computed 只直接读 @Param 基本类型（this.code），不依赖其它 @Computed，规避链式追踪不确定性。

  @Computed get isCollapsed(): boolean {
    if (!this.collapseLongContent) {
      return false;
    }
    if (this.code.length > COLLAPSE_CHAR_THRESHOLD) {
      return true;
    }
    return splitCodeLines(this.code).length > COLLAPSE_LINE_THRESHOLD;
  }

  @Computed get label(): string {
    if (this.title.trim().length > 0) {
      return this.title;
    }
    if (this.language === '' || this.language === 'unknown') {
      return t('code.code');
    }
    return this.language;
  }

  @Computed get lineNumberWidth(): number {
    const digits: number = String(splitCodeLines(this.code).length).length;
    return Math.max(digits, 2);
  }

  // 折叠时只渲染前 N 行
  @Computed get visibleLines(): string[] {
    const all: string[] = splitCodeLines(this.code);
    if (this.code.length > COLLAPSE_CHAR_THRESHOLD || all.length > COLLAPSE_LINE_THRESHOLD) {
      if (this.collapseLongContent) {
        return all.slice(0, Math.min(all.length, COLLAPSE_LINE_THRESHOLD));
      }
    }
    return all;
  }

  private numColWidth(): number {
    return this.lineNumberWidth * 7 + 6;
  }

  private bodyMaxHeight(): number {
    return this.maxHeight > 0 ? this.maxHeight : SCROLL_HEIGHT;
  }

  // 大文件降级：超 HIGHLIGHT_CHAR_CAP 字符走 text（免逐行扫描 jank）。
  //   collapseLongContent 的工具卡走折叠分支不命中；FileViewerPage scrollY 大文件才需此守卫。
  private get effectiveLanguage(): string {
    return this.code.length > HIGHLIGHT_CHAR_CAP ? 'text' : this.language;
  }

  // 逐行 tokenize（chat/CodeHighlight 纯层）。空行透传 ' '（tokenizeLine 自带占位）。
  private highlight(line: string): HighlightToken[] {
    return tokenizeLine(line, this.effectiveLanguage);
  }

  // token 类型 → 既有 palette（不新增调色板项）。
  //   keyword=primary / string=success / number=warning / comment=codeMuted / plain=codeText。
  private colorForToken(type: HighlightTokenType): string {
    if (type === 'keyword') { return this.c.primary; }
    if (type === 'string') { return this.c.success; }
    if (type === 'number') { return this.c.warning; }
    if (type === 'comment') { return this.c.codeMuted; }
    return this.c.codeText;
  }

  build() {
    Column() {
      // header（label）
      Row() {
        Text(this.label)
          .fontSize(fs(10))
          .fontColor(this.c.codeMuted)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(this.c.surfaceSelected)

      // body
      if (this.scrollY && !this.isCollapsed) {
        Scroll() {
          this.CodeBody()
        }
        .width('100%')
        .constraintSize({ maxHeight: this.bodyMaxHeight() })
        .scrollBar(BarState.Auto)
        .align(Alignment.Top)
      } else if (this.isCollapsed) {
        Stack({ alignContent: Alignment.Bottom }) {
          this.CodeBody()
          // 底部「已截断」角标
          Row() {
            Text(t('code.truncated'))
              .fontSize(fs(10))
              .fontColor(this.c.codeMuted)
              .backgroundColor(this.c.codeBg)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(8)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ bottom: 6 })
        }
        .width('100%')
        .clip(true)
        .constraintSize({ maxHeight: COLLAPSED_HEIGHT })
      } else {
        this.CodeBody()
      }
    }
    .width('100%')
    .backgroundColor(this.c.codeBg)
    .borderRadius(10)
    .clip(true)
  }

  @Builder
  CodeBody() {
    Column() {
      ForEach(this.visibleLines, (line: string, idx: number) => {
        Row() {
          Text(String(idx + 1))
            .fontSize(fs(11))
            .fontColor(this.c.codeMuted)
            .width(this.numColWidth())
            .textAlign(TextAlign.End)
          // 行内容：逐 token 染色 Span 序列（CodeHighlight）；text 语言全 plain 等价旧行为。
          //   父 Text 持 fontSize/maxLines/textOverflow/margin；Span 仅 fontColor + fontFamily。
          Text() {
            ForEach(this.highlight(line.length > 0 ? line : ' '), (tk: HighlightToken, idx: number) => {
              Span(tk.text)
                .fontColor(this.colorForToken(tk.type))
                .fontFamily('monospace')
            }, (tk: HighlightToken, idx: number) => `${idx}`)
          }
          .fontSize(fs(11))
          .fontColor(this.c.codeText)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 8 })
        }
        .width('100%')
      }, (line: string, idx: number) => `${idx}`)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }
}

export { CodeBlock };
