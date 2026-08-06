// CodeBlock —— 对照 web/src/components/CodeBlock.tsx（上游 Shiki 高亮；本项目自包含轻量扫描器）
// 等宽文本 + 行号 + 长内容折叠（>18 行或 >1800 字符 → 折叠到 260 + 「已截断」角标）。
// 宽行 word-wrap（对齐 chatcube/paseo，从不截断代码；行号顶对齐首行，续行无号）。
// 语法高亮：整块 tokenizeCode（跨块注释/三引号态）→ 按 token 类型染色的 Span 序列（chat/CodeHighlight 纯层；
//   keyword=primary / string=success / number=warning / literal=warning / comment=codeMuted /
//   function=codeFunction / type=codeType / punctuation=codePunctuation / plain=codeText）。
//   text 语言全 plain（零回归）；大文件（>20k 字符）降级 text 免扫描 jank。
// V2：@Param code/language/title/collapseLongContent/scrollY/maxHeight/showCopy/showFullScreen + @Event onFullScreen；
//   @Computed isCollapsed/label/lineNumberWidth/highlightedLines。
//   流式：highlightedLines 按 @Param(code/language) memoize，每 tick O(n) 重算不 remount（父 ForEach key 稳）。

import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';
import { tokenizeCode, HighlightToken, HighlightTokenType } from '../chat/CodeHighlight';
import { pasteboard } from '@kit.BasicServicesKit';
import { showToast } from '../utils/Toast';

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
  // —— markdown 代码块 opt-in 动作（默认关：工具卡 / FileViewer / CliOutput 等调用点零回归）——
  //   showCopy：header 右侧显复制图标 → 写系统剪贴板（对照 CJMarkdown setCodeCopyCallback）。
  //   showFullScreen：header 右侧显全屏图标 → 触发 @Event onFullScreen（交上层开全屏 sheet）。
  @Param showCopy: boolean = false;
  @Param showFullScreen: boolean = false;
  @Event onFullScreen: () => void = (): void => {};

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

  // 整块高亮（跨行块注释/三引号态）；@Computed 按 code/language memoize，流式每 tick O(n) 重算不 remount。
  @Computed get highlightedLines(): HighlightToken[][] {
    return tokenizeCode(this.code, this.effectiveLanguage);
  }

  private numColWidth(): number {
    return this.lineNumberWidth * 7 + 6;
  }

  private bodyMaxHeight(): number {
    return this.maxHeight > 0 ? this.maxHeight : SCROLL_HEIGHT;
  }

  // 大文件降级：超 HIGHLIGHT_CHAR_CAP 字符走 text（免逐行扫描 jank）。
  private get effectiveLanguage(): string {
    return this.code.length > HIGHLIGHT_CHAR_CAP ? 'text' : this.language;
  }

  // 折叠时只渲染前 N 行的 token（与 isCollapsed 同判定；plain 方法从 build 调，读 @Computed 不成链）。
  private visibleTokenLines(): HighlightToken[][] {
    const all: HighlightToken[][] = this.highlightedLines;
    if (this.code.length > COLLAPSE_CHAR_THRESHOLD || all.length > COLLAPSE_LINE_THRESHOLD) {
      if (this.collapseLongContent) {
        return all.slice(0, Math.min(all.length, COLLAPSE_LINE_THRESHOLD));
      }
    }
    return all;
  }

  // token 类型 → palette。
  private colorForToken(type: HighlightTokenType): string {
    if (type === 'keyword') { return this.c.primary; }
    if (type === 'string') { return this.c.success; }
    if (type === 'number') { return this.c.warning; }
    if (type === 'literal') { return this.c.warning; }
    if (type === 'comment') { return this.c.codeMuted; }
    if (type === 'function') { return this.c.codeFunction; }
    if (type === 'type') { return this.c.codeType; }
    if (type === 'punctuation') { return this.c.codePunctuation; }
    return this.c.codeText;   // plain
  }

  // 复制整段代码到系统剪贴板（showCopy=true 时 header 复制图标触发；对照 MarkdownText.copyToClipboard）
  private copyCode(): void {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.code);
    pasteboard.getSystemPasteboard().setData(data)
      .then((): void => { showToast(t('common.copySuccess')); })
      .catch((): void => { showToast(t('markdown.copyFailed')); });
  }

  build() {
    Column() {
      // header（label + opt-in 复制 / 全屏动作图标）
      Row() {
        Text(this.label)
          .fontSize(fs(10))
          .fontColor(this.c.codeMuted)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.showCopy) {
          Image($r('app.media.markdown_code_copy'))
            .width(16)
            .height(16)
            .margin({ left: 8 })
            .onClick(() => { this.copyCode(); })
        }
        if (this.showFullScreen) {
          Image($r('app.media.markdown_code_fullscreen'))
            .width(16)
            .height(16)
            .margin({ left: 8 })
            .onClick(() => { this.onFullScreen(); })
        }
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
      ForEach(this.visibleTokenLines(), (toks: HighlightToken[], idx: number) => {
        Row() {
          Text(String(idx + 1))
            .fontSize(fs(11))
            .fontColor(this.c.codeMuted)
            .width(this.numColWidth())
            .textAlign(TextAlign.End)
          // 行内容：逐 token 染色 Span 序列（CodeHighlight 整块预高亮）；text 语言全 plain 等价旧行为。
          //   父 Text 持 fontSize/margin；Span 仅 fontColor + fontFamily。宽行 word-wrap（无 maxLines）。
          Text() {
            ForEach(toks, (tk: HighlightToken, tIdx: number) => {
              Span(tk.text)
                .fontColor(this.colorForToken(tk.type))
                .fontFamily('monospace')
            }, (tk: HighlightToken, tIdx: number) => `${tIdx}`)
          }
          .fontSize(fs(11))
          .fontColor(this.c.codeText)
          .layoutWeight(1)
          .margin({ left: 8 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)   // 行号顶对齐首行（包裹续行无号，符合 GitHub 习惯）
      }, (toks: HighlightToken[], idx: number) => `${idx}`)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }
}

export { CodeBlock };
