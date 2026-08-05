import { buffer } from '@kit.ArkTS';
import { pasteboard } from '@kit.BasicServicesKit';
import { getHubClient } from '../api/HubClient';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';
import { CodeBlock } from '../components/CodeBlock';
import { getLayoutState } from '../state/LayoutState';
import { HdsNavDestination, HdsNavDestinationTitleMode, DividerShowType, TitleBarStyleOptions } from '@kit.UIDesignKit';
import { hdsTitleBarStyle } from '../components/HdsTitleBarStyle';

// 文件查看页（NavDestination）—— 对照 hapi web /sessions/$sessionId/file
//   readSessionFile → content(base64)：图片扩展名→Image(data:mime;base64,...)；
//                      文本→buffer base64 解码→CodeBlock；二进制→占位。
//   从 git 改动行进入（showDiff=true）时额外 getGitDiffFile → 统一 diff 逐行染色渲染
//   （DiffView 接 old/new 串对，非统一 diff，故自写 DiffLines，对照 web DiffDisplay）。
// 协议不变；颜色经统一主题。

// 路由参数（FilesPage.openFile 构造）
export class FileViewerRouteParams {
  sessionId: string = '';
  path: string = '';
  showDiff: boolean = false;   // 从 git 改动行进入时为 true（渲染 diff 段）
  staged: boolean = false;     // showDiff 时区分暂存/未暂存版本
}

// 图片扩展名 → MIME（对照 web IMAGE_MIME_BY_EXTENSION，取常见子集）
function resolveImageMime(path: string): string {
  const lower: string = path.toLowerCase();
  const dot: number = lower.lastIndexOf('.');
  if (dot < 0) { return ''; }
  const ext: string = lower.substring(dot + 1);
  if (ext === 'png') { return 'image/png'; }
  if (ext === 'jpg' || ext === 'jpeg') { return 'image/jpeg'; }
  if (ext === 'gif') { return 'image/gif'; }
  if (ext === 'webp') { return 'image/webp'; }
  if (ext === 'bmp') { return 'image/bmp'; }
  if (ext === 'svg') { return 'image/svg+xml'; }
  return '';
}

// 文件名 → 语言 label（CodeBlock language 仅 label 兜底，无语法高亮）
function resolveLanguage(path: string): string {
  const lower: string = path.toLowerCase();
  const dot: number = lower.lastIndexOf('.');
  if (dot < 0) { return 'text'; }
  return lower.substring(dot + 1);
}

// 二进制内容判定（对照 web isBinaryContent：含 \0 或非打印字符占比 >10%）
function isBinaryContent(content: string): boolean {
  if (content === '') { return false; }
  if (content.indexOf('\0') >= 0) { return true; }
  let nonPrintable: number = 0;
  for (let i = 0; i < content.length; i++) {
    const code: number = content.charCodeAt(i);
    if (code < 32 && code !== 9 && code !== 10 && code !== 13) { nonPrintable++; }
  }
  return nonPrintable / content.length > 0.1;
}

@ComponentV2
struct FileViewerPage {
  @Local sessionId: string = '';
  @Local filePath: string = '';
  @Local showDiff: boolean = false;
  @Local staged: boolean = false;

  // 文件内容
  @Local loading: boolean = false;
  @Local contentError: string = '';
  @Local rawBase64: string = '';        // 原始 base64
  @Local decodedText: string = '';      // 解码后文本（仅文本文件有效）
  @Local isBinary: boolean = false;
  @Local imageMime: string = '';        // 非空=图片
  @Local imageUrl: string = '';         // data:mime;base64,...

  // diff（showDiff 时）
  @Local diffLoading: boolean = false;
  @Local diffStdout: string = '';
  @Local diffError: string = '';

  @Local copied: boolean = false;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }
  private get isDark(): boolean { return getThemeState().isDark; }
  private navPathStack: NavPathStack | null = null;
  private scroller: Scroller = new Scroller();
  private get titleBarStyle(): TitleBarStyleOptions { return hdsTitleBarStyle(this.c.bg); }

  private get fileName(): string {
    const idx: number = this.filePath.lastIndexOf('/');
    return idx >= 0 ? this.filePath.substring(idx + 1) : this.filePath;
  }
  // 可复制（文本且 <1MB 解码长度）
  private get canCopy(): boolean {
    return this.decodedText !== '' && !this.isBinary && this.decodedText.length <= 1000000;
  }

  // 读文件内容
  private async loadFile(): Promise<void> {
    if (this.sessionId === '' || this.filePath === '') { return; }
    this.loading = true;
    this.contentError = '';
    try {
      const resp = await getHubClient().readSessionFile(this.sessionId, this.filePath);
      if (!resp.success) {
        this.contentError = resp.error !== '' ? resp.error : t('fileViewer.readFailed');
        return;
      }
      this.rawBase64 = resp.content;
      this.imageMime = resolveImageMime(this.filePath);
      if (this.imageMime !== '') {
        this.imageUrl = `data:${this.imageMime};base64,${resp.content}`;
      } else {
        // 解码 base64 → utf-8 文本
        try {
          this.decodedText = buffer.from(resp.content, 'base64').toString('utf-8');
          this.isBinary = isBinaryContent(this.decodedText);
        } catch (e) {
          this.isBinary = true;   // 解码失败按二进制处理
        }
      }
    } catch (e) {
      this.contentError = e instanceof Error ? e.message : t('fileViewer.readFailed');
    } finally {
      this.loading = false;
    }
  }

  // 读 diff（showDiff 时）
  private async loadDiff(): Promise<void> {
    if (!this.showDiff) { return; }
    this.diffLoading = true;
    try {
      const resp = await getHubClient().getGitDiffFile(this.sessionId, this.filePath, this.staged);
      if (!resp.success) {
        this.diffError = resp.error !== '' ? resp.error : (resp.stderr !== '' ? resp.stderr : t('fileViewer.diffLoadFailed'));
      } else {
        this.diffStdout = resp.stdout;
      }
    } catch (e) {
      this.diffError = e instanceof Error ? e.message : t('fileViewer.diffLoadFailed');
    } finally {
      this.diffLoading = false;
    }
  }

  private copyContent(): void {
    if (!this.canCopy) { return; }
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.decodedText);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.copied = true;
        setTimeout(() => { this.copied = false; }, 1500);
      });
    } catch (e) {
      // 忽略——复制失败不阻断
    }
  }

  @Builder
  private DiffLines() {
    if (this.diffLoading) {
      Text(t('fileViewer.diffLoading')).fontSize(fs(13)).fontColor(this.c.textTertiary).padding(16)
    } else if (this.diffError !== '') {
      Text(this.diffError).fontSize(fs(13)).fontColor(this.c.error).padding(16)
    } else if (this.diffStdout === '') {
      Text(t('fileViewer.noDiff')).fontSize(fs(13)).fontColor(this.c.textTertiary).padding(16)
    } else {
      Column({ space: 0 }) {
        ForEach(this.diffLineList(), (ln: string, i: number) => {
          this.DiffLineRow(ln, i)
        }, (ln: string, i: number) => `${i}`)
      }
      .width('100%')
      .backgroundColor(this.c.codeBg)
      .borderRadius(8)
    }
  }

  @Builder
  private DiffLineRow(ln: string, i: number) {
    Row() {
      Text(ln.length > 0 ? ln : ' ')
        .fontSize(fs(12))
        .fontFamily('monospace')
        .fontColor(this.diffLineColor(ln))
        .width('100%')
    }
    .width('100%')
    .backgroundColor(this.diffLineBg(ln))
    .padding({ left: 8, right: 8, top: 1, bottom: 1 })
  }

  // 统一 diff 逐行切分（去 \r；空 stdout → 空数组）
  private diffLineList(): string[] {
    if (this.diffStdout === '') { return []; }
    const lines: string[] = this.diffStdout.replace(/\r/g, '').split('\n');
    return lines;
  }
  private diffLineColor(ln: string): string {
    if (ln.startsWith('+') && !ln.startsWith('+++')) { return this.c.diffAdd; }
    if (ln.startsWith('-') && !ln.startsWith('---')) { return this.c.diffDelete; }
    if (ln.startsWith('@@')) { return this.c.textTertiary; }
    return this.c.codeText;
  }
  private diffLineBg(ln: string): string {
    if (ln.startsWith('+') && !ln.startsWith('+++')) { return this.c.successBg; }
    if (ln.startsWith('-') && !ln.startsWith('---')) { return this.c.errorBg; }
    return this.c.codeBg;
  }

  @Builder
  private ContentArea() {
    if (this.loading) {
      Column({ space: 8 }) {
        LoadingProgress().width(28).height(28).color(this.c.primary)
        Text(t('fileViewer.loading')).fontSize(fs(13)).fontColor(this.c.textTertiary)
      }
      .width('100%')
      .padding({ top: 48 })
      .alignItems(HorizontalAlign.Center)
    } else if (this.contentError !== '') {
      Text(this.contentError)
        .fontSize(fs(14)).fontColor(this.c.error)
        .width('100%').textAlign(TextAlign.Center)
        .padding({ top: 48, left: 24, right: 24 })
    } else if (this.imageMime !== '' && this.imageUrl !== '') {
      // 图片（data URI；待 DevEco 验证 ArkUI Image 对 base64 data URI 支持）
      Image(this.imageUrl)
        .width('100%')
        .objectFit(ImageFit.Contain)
        .borderRadius(8)
        .backgroundColor(this.c.surface)
    } else if (this.isBinary) {
      Column({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.archivebox')).fontSize(fs(36)).fontColor([this.c.textTertiary])
        Text(t('fileViewer.binary')).fontSize(fs(14)).fontColor(this.c.textTertiary)
      }
      .width('100%')
      .padding({ top: 48 })
      .alignItems(HorizontalAlign.Center)
    } else {
      // 文本：复用 CodeBlock 渲染
      CodeBlock({
        code: this.decodedText,
        language: resolveLanguage(this.filePath),
        title: this.fileName,
        scrollY: true,
        maxHeight: 0
      })
    }
  }

  // 液态顶栏内容（HdsNavDestination titleBar.stackBuilder 调用）。不在此设 padding-top/底色/border——
  //   系统 titleBar avoidLayoutSafeArea 自避让状态栏，磨砂底色由 HDS style 提供（systemMaterialEffect + GRADIENT_BLUR）。
  //   ‹返回 + 文件名 + 复制（液态圆钮 SymbolGlyph；copied?checkmark:doc_filled_on_doc）。
  @Builder
  private TopBar() {
    Row({ space: 8 }) {
      // 返回（液态圆钮；hideBackButton 去掉系统返回，必须有）
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_backward'))
          .fontSize(fs(18))
          .fontColor([this.c.textPrimary])
      }
      .width(36)
      .height(36)
      .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      .onClick(() => { if (this.navPathStack !== null) { this.navPathStack.pop(); } })

      // 文件名（layoutWeight 撑开，ellipsis）
      Text(this.fileName !== '' ? this.fileName : t('fileViewer.fallbackTitle'))
        .fontSize(fs(16))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.textPrimary)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // 复制（液态圆钮；copied?checkmark:doc_filled_on_doc，canCopy 控制字色）
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph(this.copied ? $r('sys.symbol.checkmark') : $r('sys.symbol.doc_filled_on_doc'))
          .fontSize(fs(18))
          .fontColor([this.canCopy ? this.c.textPrimary : this.c.textTertiary])
      }
      .width(36)
      .height(36)
      .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      .onClick(() => { this.copyContent(); })
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    // 液态背景由系统 HDS titleBar 提供；本 Builder 仅渲染顶栏内容，不设根 backgroundColor/border。
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          // 内容
          Column() {
            this.ContentArea()
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8 })

          // diff 段（从 git 改动进入时）
          if (this.showDiff) {
            Column({ space: 6 }) {
              Text(this.staged ? t('fileViewer.diffStaged') : t('fileViewer.diffUnstaged'))
                .fontSize(fs(13)).fontColor(this.c.textTertiary)
                .width('100%')
                .padding({ left: 4 })
              this.DiffLines()
            }
            .width('100%')
            .padding({ left: 12, right: 12, bottom: 24 })
          }
          // 底部安全区占位（手势导航条）
          Row().height(getLayoutState().bottomAvoidHeight)
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .backgroundColor(this.c.bg)
    }
    // HDS 液态 titleBar（stackBuilder 渲染 TopBar）+ bindToScrollable 滚动联动磨砂 +
    //   ignoreLayoutSafeArea 顶延伸状态栏（液态顶栏）/底自管安全区（Scroll 末尾占位补）。
    .titleBar({
      content: {
        title: { mainTitle: ' ' },                          // 占位（真内容走 stackBuilder）
        divider: { showType: DividerShowType.OFF },         // 关分割线（否则又出硬线）
        stackBuilder: (): void => { this.TopBar(); }        // 自建顶栏塞进系统 titleBar
      },
      style: this.titleBarStyle,
      avoidLayoutSafeArea: true,                            // titleBar 自身避让状态栏
      enableComponentSafeArea: false
    })
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .hideTitleBar(false, true)
    .hideBackButton(true)   // 隐藏系统返回箭头：返回走 stackBuilder 内 TopBar 自建液态圆钮
    .systemBarStyle(
      { statusBarContentColor: this.isDark ? '#F5F7FA' : '#1F2329' },
      { statusBarContentColor: this.isDark ? '#F5F7FA' : '#1F2329' }
    )
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack;
      const param = context.pathInfo.param as FileViewerRouteParams;
      if (param !== null && param !== undefined) {
        this.sessionId = param.sessionId;
        this.filePath = param.path;
        this.showDiff = param.showDiff;
        this.staged = param.staged;
        this.loadFile();
        this.loadDiff();
      }
    })
  }
}

// 系统路由表 buildFunction（router_map.json 引用）
@Builder
export function FileViewerPageBuilder(name: string, param: Object) {
  FileViewerPage()
}
