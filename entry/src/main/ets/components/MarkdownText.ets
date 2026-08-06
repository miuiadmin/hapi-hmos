import {
  CJMarkdown,
  MarkdownConfiguration,
  MarkdownPlugin,
  MarkdownTheme,
  LatexMathColorFormat,
  ImageFitType
} from '@cangjie-tpc/markdown_hybrid'
import { Want, common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { fs, paletteOf, PaletteColors, toArgb, getThemeState } from '../theme/ThemeService'
import {
  getMarkdownTitleSizes,
  getMarkdownTitleLineHeights,
  getMarkdownTextLineHeight,
  getMarkdownBlockSpacing,
  MarkdownTitleScale
} from '../utils/MarkdownTypographyUtil';
import { CodeBlock } from './CodeBlock';
import { splitMarkdown, MarkdownSegment } from '../utils/MarkdownCodeSplitter';
import { showToast } from '../utils/Toast';
import { NON_HTTPS_LINKIFY_SCHEMES } from '../chat/LinkSchemes';
import { t, kv2 } from '../i18n/I18nService';
import {
  classifyScheme,
  hasScheme,
  extractScheme,
  isAllowedScheme,
  loadAllowedSchemes,
  saveAllowedScheme
} from '../utils/ExternalLink';
import { getPreferencesService } from '../services/PreferencesService';
import { ImagePreviewSheet } from './ImagePreviewSheet';
import { scanFilePaths, decodeFilePathHref } from '../utils/FilePathScanner';
import { SheetDialog } from './settings/SheetDialog';
import { buildSheetOptions, SheetOverrides } from './settings/SheetOptionsFactory';

// 极简 Markdown 渲染组件：封装 @cangjie-tpc/markdown_hybrid（Apache-2.0）的 CJMarkdown
// 参考 chatcube ChatMarkdownHybridRenderer（MIT），裁掉其 AppUiState 主题系统 / 排版工具 / 媒体图标依赖：
//   - 颜色走统一主题（theme/ThemeService）：buildConfig 读 paletteOf(isDark) + toArgb 转 ARGB；
//     getConfig 在 isDark 变化时丢弃缓存重建（markdown_hybrid 缓存数字配色，无观察钩子 → 手动失效）
//   - 复制按钮已启用（图标 app.media.markdown_code_copy + setCodeCopyCallback 写系统剪贴板）；
//     全屏按钮已启用（setIsCodeFullScreen(true) + setCodeFullScreenCallback → bindSheet 大尺寸代码预览，复用 markdown_code_fullscreen 图标）
//   - 开 LaTeX 插件（对齐 chatcube setIsLatexMathPlugin(true) + setLatex* 主题；库自带数学字体，无需回调）
//   - 仓颉引擎：useCangjieComponent=true（库本体即 Cangjie 实现，依赖其内置 .so）
// hapi 简化：每条 message-received 是完整消息（非 token 增量）→ isInputEnded 恒 true，无需增量分析
// 所有 setter 名逐字对照 chatcube 同版本（1.3.6）源码，禁止臆造

@ComponentV2
export struct MarkdownText {
  @Param content: string = '';
  // 流式态：末块 agent-text/reasoning 在 thinking 中时由上层传 false（CJMarkdown 流式增量渲染）；
  //   历史/已完成块恒 true（默认，向后兼容）。isInputEnded 入 config 签名 → 翻转时 CJMarkdown 一次性重建做最终解析。
  @Param isInputEnded: boolean = true;
  // 流式增量分析：流式块传 true（配合 content @Param 原地更新做增量解析）；历史块 false（默认）。
  //   修「incrementalAnalysis:false + content 变化 → CJMarkdown 不重渲流式增量」根因。
  @Param incrementalAnalysis: boolean = false;
  // 紧凑档（reasoning 气泡等次级文本；默认 false）：小一号字号 + 更紧间距/级差。对照 chatcube compact。
  @Param compact: boolean = false;

  // 裸文件路径 → hapi-file: 链接（喂 CJMarkdown 前预处理；对照上游 remarkFilePathLinks MDAST 插件）。
  //   opt-in：仅当上层接了 onOpenFilePath 并显式 linkFilePaths=true 才扫描——避免工具卡 / reasoning 等无 nav
  //   上下文的叶子场景出现「点得动却没反应」的死链接（上游能处处链是因 markdown-text 恒有 session 上下文）。
  //   scanFilePaths 是纯函数、幂等（无命中返回原引用）→ @Computed 仅依赖 @Param 基本类型，无链式追踪。
  @Param linkFilePaths: boolean = false;

  // 拆段：fenced 代码块脱离 CJMarkdown 自渲（CodeBlock 语法高亮；CJMarkdown 无 token 着色 API），
  //   正文段仍走 CJMarkdown（标题/列表/表格/行内码 排版强）。@Computed 仅依赖 @Param content →
  //   content 流式变化时重算；splitter 前缀稳定（append-only）→ ForEach index 键复用前缀段，不整列重建。
  @Computed get segments(): MarkdownSegment[] {
    return splitMarkdown(this.content);
  }

  // 正文段文件路径链接预处理（opt-in；代码段不处理——代码非散文，路径不该成链接）
  private mdContent(text: string): string {
    return this.linkFilePaths ? scanFilePaths(text) : text;
  }

  // 路径链接点击 → 委托上层（ChatPage.openFilePath → FileViewer）。叶子组件不持 navStack，范式同 chatcube @Event onOpenLink。
  @Event onOpenFilePath: (path: string) => void = (path: string): void => {};

  // 代码全屏预览（点代码块全屏图标 → bindSheet 大尺寸 sheet 展示完整代码，对照 chatcube CodePreviewSheet）
  @Local showCodePreview: boolean = false;
  @Local previewCode: string = '';
  @Local previewTitle: string = '';

  // 图片全屏预览（点 markdown 图片 → bindSheet 全屏 Image 预览，对照 chatcube onImageClick → handleImagePreview，
  //   裁掉其媒体库/存相册/分享；MVP 仅单图 Contain 预览 + 点按关闭）
  @Local showImagePreview: boolean = false;
  @Local previewImageSrc: string = '';

  private cachedConfig: MarkdownConfiguration | null = null;
  private cachedPlugin: MarkdownPlugin | null = null;
  private cachedConfigSignature: string = '';   // config 缓存对应的签名（isDark/fontScale/isInputEnded/compact）；任一变化则重建

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  // 代码块上下外边距（对齐 CJMarkdown 块间距 blockSpacing，保持正文↔代码段垂直节奏一致；
  //   CJMarkdown 各实例首末块 margin=0，故代码段与正文段之间的间距由此外边距提供）
  private get codeBlockMargin(): number {
    const textSize: number = Math.max(fs(15) - (this.compact ? 2 : 1), 10);
    return getMarkdownBlockSpacing(textSize, this.compact);
  }

  // 构建配置（主题 + 回调）；isDark 变化时由 getConfig 失效重建，否则缓存复用避免每帧重建
  private buildConfig(): MarkdownConfiguration {
    const config: MarkdownConfiguration = new MarkdownConfiguration();
    const theme: MarkdownTheme = new MarkdownTheme();

    const isDark: boolean = getThemeState().isDark;
    const c: PaletteColors = paletteOf(isDark);

    // setContext 需 UI 上下文（资源 / 字号解析），对照 chatcube buildMarkdownConfig
    const ctx = this.getUIContext().getHostContext();
    if (ctx !== undefined && ctx !== null) {
      theme.setContext(ctx);
    }

    // —— 尺寸派生（对照 chatcube MarkdownTypographyUtils；base 走全局字号缩放 fs()，响应设置页 small/default/large）——
    const textSize: number = Math.max(fs(15) - (this.compact ? 2 : 1), 10);
    const textLineHeight: number = getMarkdownTextLineHeight(textSize, this.compact);
    const codeTextSize: number = Math.max(textSize - 1, 10);
    const codeLineHeight: number = getMarkdownTextLineHeight(codeTextSize);
    const blockSpacing: number = getMarkdownBlockSpacing(textSize, this.compact);
    const titleSizes: MarkdownTitleScale = getMarkdownTitleSizes(textSize, this.compact);
    const titleLineHeights: MarkdownTitleScale = getMarkdownTitleLineHeights(titleSizes, this.compact);

    // —— 颜色（palette → ARGB）——
    const textColor: number = toArgb(c.textPrimary);
    const titleColor: number = toArgb(c.textPrimary);
    const linkColor: number = toArgb(c.primary);
    const codeTextColor: number = toArgb(c.codeText);
    const codeBgColor: number = toArgb(c.codeBg);
    const tableBorderColor: number = toArgb(c.border);
    const tableBgColor: number = toArgb(c.bg);

    // —— 派生边距（列表 / 引用 / 上下标 / 代码多行；对照 chatcube applyListTheme/applyInlineDecorationTheme）——
    const listItemSpacing: number = Math.max(Math.round(textSize * (this.compact ? 0.12 : 0.18)), this.compact ? 1 : 2);
    const listLeftMargin: number = Math.max(Math.round(textSize * 0.65), this.compact ? 7 : 8);
    const bulletSize: number = Math.max(Math.round(textSize * 0.35), 4);
    const subSupTextSize: number = Math.max(Math.round(textSize * 0.72), 8);
    const codeMultilineMargin: number = Math.max(Math.round(codeTextSize * (this.compact ? 0.65 : 0.75)), this.compact ? 8 : 10);
    const quoteHorizontalMargin: number = Math.max(Math.round(textSize * (this.compact ? 0.72 : 0.8)), this.compact ? 9 : 10);
    const quoteVerticalSpacing: number = Math.max(Math.round(textSize * (this.compact ? 0.4 : 0.45)), this.compact ? 5 : 6);

    // 解析器 / 行为
    theme.setIsMarkdownParserSync(false);
    theme.setIsCodeBlockParserSync(false);
    theme.setIsOnCopy(this.isInputEnded);          // 流式中关复制（对照 chatcube）
    theme.setIsCodeFullScreen(true);               // 开启代码块全屏按钮（点 → 全屏 sheet）
    theme.setIconWidthAndHeight(22);               // 代码块图标尺寸（复制 / 全屏，对照 chatcube）
    theme.setCodeCopyIcon($r('app.media.markdown_code_copy'));
    theme.setCodeFullScreenIcon($r('app.media.markdown_code_fullscreen'));
    theme.setBlockFirstTopMargin(0);
    theme.setBlockLastBottomMargin(0);
    theme.setBlockTopAndBottomMargins(blockSpacing);
    theme.setOpenGestureSwipe(false);

    // 正文段落
    theme.setParagraphTextSize(textSize);
    theme.setParagraphTextLineHeight(textLineHeight);
    theme.setParagraphTextColor(textColor);
    theme.setParagraphTopMargins(0);
    theme.setParagraphBottomMargins(0);

    // 标题（分级字号 / 行高 / 颜色 / 边距，对照 chatcube applyHeadingTheme；旧版只设了颜色 → H1≈H4 扁平）
    theme.setHeadingTextColor(titleColor);
    theme.setHeadingBreakColor(tableBorderColor);
    theme.setHeadingTextSize1(titleSizes[0]);
    theme.setHeadingTextSize2(titleSizes[1]);
    theme.setHeadingTextSize3(titleSizes[2]);
    theme.setHeadingTextSize4(titleSizes[3]);
    theme.setHeadingTextSize5(titleSizes[4]);
    theme.setHeadingTextSize6(titleSizes[5]);
    theme.setHeadingTextLineHeight1(titleLineHeights[0]);
    theme.setHeadingTextLineHeight2(titleLineHeights[1]);
    theme.setHeadingTextLineHeight3(titleLineHeights[2]);
    theme.setHeadingTextLineHeight4(titleLineHeights[3]);
    theme.setHeadingTextLineHeight5(titleLineHeights[4]);
    theme.setHeadingTextLineHeight6(titleLineHeights[5]);
    theme.setHeadingTextColor1(titleColor);
    theme.setHeadingTextColor2(titleColor);
    theme.setHeadingTextColor3(titleColor);
    theme.setHeadingTextColor4(titleColor);
    theme.setHeadingTextColor5(titleColor);
    theme.setHeadingTextColor6(titleColor);
    theme.setHeadingTypeface('sans-serif');
    theme.setHeadingTopMargins(blockSpacing);
    theme.setHeadingBottomMargins(Math.max(Math.round(textSize * 0.35), 4));

    // 链接
    theme.setLinkColor(linkColor);
    theme.setLinkSize(textSize);
    theme.setLinkLineHeight(textLineHeight);
    theme.setLinkBackGroupColor(0x00000000);
    theme.setIsLinkUnderlined(false);

    // 引用块
    theme.setBlockQuoteColor(linkColor);
    theme.setBlockQuoteBackGroupColor(codeBgColor);
    theme.setBlockQuoteWidth(3);
    theme.setBlockQuoteLeftMargin(quoteHorizontalMargin);
    theme.setBlockQuoteRightMargin(0);
    theme.setBlockQuoteTopAndBottomMargins(quoteVerticalSpacing);

    // 列表（bullet / ordered 项色 / 字号 / 行高 + 缩进 + 项间距，对照 chatcube applyListTheme；旧版全缺 → 无缩进挤一团）
    theme.setBlockOrderedAndBulletTopAndBottomMargins(listItemSpacing);
    theme.setBlockLeftMargin(listLeftMargin);
    theme.setBlockRightMargin(0);
    theme.setOrderedListItemPrefixBold(false);
    theme.setOrderedListItemColor(textColor);
    theme.setOrderedListItemSize(textSize);
    theme.setOrderedListItemLineHeight(textLineHeight);
    theme.setBulletListItemColor(textColor);
    theme.setBulletListItemSize(bulletSize);
    theme.setBulletListItemLineHeight(textLineHeight);

    // 行内修饰（删除线 / 下划线 / 上下标字色 + 字号）
    theme.setStrikethroughColor(textColor);
    theme.setUnderlineColor(textColor);
    theme.setSubTextColor(textColor);
    theme.setSubTextSize(subSupTextSize);
    theme.setSupTextColor(textColor);
    theme.setSupTextSize(subSupTextSize);

    // 行内代码
    theme.setCodeTextColor(codeTextColor);
    theme.setCodeBackgroundColor(codeBgColor);
    theme.setCodeTextSize(codeTextSize);
    theme.setCodeTypeface('monospace');

    // 代码块（字 / 底 / 字号 / 行距 / 多行间距 / 圆角 / 行号 + 语言标签 CodeList 全家，对照 chatcube）
    theme.setCodeBlockTextColor(codeTextColor);
    theme.setCodeBlockBackgroundColor(codeBgColor);
    theme.setCodeBlockTextSize(codeTextSize);
    theme.setCodeBlockTypeface('monospace');
    theme.setCodeBlockLineHeight(codeLineHeight);
    theme.setCodeMultilineMargin(codeMultilineMargin);
    theme.setCodeBlockRadius(8);
    theme.setCodeBlockLineNumberHide(false);
    theme.setCodeBlockIconTextHide(false);
    theme.setCodeBlockTypeTextColor(codeTextColor);
    theme.setCodeBlockTypeTextPadding(4);
    theme.setCodeListTitleTextSize(codeTextSize);
    theme.setCodeListTitleSelectTextSize(codeTextSize);
    theme.setCodeListTitleSelectTextColor(codeTextColor);
    theme.setCodeListTitleUnSelectTextColor(textColor);
    theme.setCodeListTitleSelectBackGroupColor(codeBgColor);
    theme.setCodeListTitleUnSelectBackGroupColor(0x00000000);
    theme.setIsSeparateCodeBlock(false);

    // 表格（奇行 bg / 偶行+表头 codeBg / 边框 / 行高，对照 chatcube）
    theme.setTableCellPadding(8);
    theme.setTableBorderColor(tableBorderColor);
    theme.setTableBorderWidth(1);
    theme.setTableOddRowBackgroundColor(tableBgColor);
    theme.setTableEvenRowBackgroundColor(codeBgColor);
    theme.setTableHeaderRowBackgroundColor(codeBgColor);
    theme.setTableContentTextColor(textColor);
    theme.setTableContentTextSize(textSize);
    theme.setTableContentTextLineHeight(textLineHeight);
    theme.setTableTitleTextColor(titleColor);
    theme.setTableTitleTextSize(textSize);
    theme.setTableTitleLineHeight(textLineHeight);
    theme.setTableTextLineHeight(textLineHeight);
    theme.setTableRadius(6);
    theme.setTableScrollBarShow(false);
    theme.setTableScrollBarColor(tableBorderColor);

    // 分割线 / 暗色模式
    theme.setThematicBreakColor(tableBorderColor);

    // 数学公式 LaTeX（对齐 chatcube setLatex*；库内置渲染生成图片，无需回调）
    theme.setLatexDefaultText(true);
    theme.setLatexMathTextSize(Math.max(textSize, 13));
    theme.setLatexMathTextColor(textColor);
    theme.setLatexMathBackGroupColor(0x00000000);
    theme.setLatexMathColorFormat(LatexMathColorFormat.COLOR_FORMAT_BGRA_8888);
    theme.setLatexMathBlockCenter(false);

    // 图片（圆角 + 上下与块同节奏；不设 maxWidth/fit —— chatcube 亦不设，库默认按容器宽自适应，设硬值反易回归）
    theme.setImageBorderRadius(8);
    theme.setImageMarginTop(blockSpacing);
    theme.setImageMarginBottom(blockSpacing);

    theme.setIsDark(isDark);

    config.setMarkdownTheme(theme);
    // 链接点击 → hapi-file: 拦截（裸路径链接）→ scheme 分类策略（IANA 安全直接开 / deny 阻止 / custom 确认）
    config.setLinkCallback((url: string): void => {
      // 裸文件路径链接（scanFilePaths 预处理注入）→ 委托上层打开 FileViewer，不落 openExternal（非 IANA/deny，会走 custom 确认→startAbility 失败）
      if (url.indexOf('hapi-file:') === 0) {
        const fp: string | null = decodeFilePathHref(url);
        if (fp !== null) { this.onOpenFilePath(fp); return; }
      }
      this.openExternal(url);
    });
    // 图片点击 → 应用内全屏预览（http(s)/data:，对照 chatcube setImageCallback → onImageClick → handleImagePreview）
    config.setImageCallback((src: string, _sources: Array<string>): void => { this.openImagePreview(src); });
    // 复制回调：正文选中文本 / 代码块复制按钮 → 写系统剪贴板（对照 chatcube setTextCopyCallback/setCodeCopyCallback）
    config.setTextCopyCallback((text: string): void => { this.copyToClipboard(text); });
    config.setCodeCopyCallback((code: string): void => { this.copyToClipboard(code); });
    // 代码块全屏：回调取 (code, codeType?) → 打开全屏预览 sheet（对照 chatcube setCodeFullScreenCallback → openCodePreviewFromHybrid）
    config.setCodeFullScreenCallback((code: string, codeType: string | undefined): void => {
      this.openCodePreview(code, codeType ?? '');
    });
    return config;
  }

  // 外链点击策略（对照 web markdown-text.tsx URI scheme policy；行为对齐上游）：
  //   相对/锚点链接（无 scheme）→ 忽略；
  //   deny scheme（javascript:/data:/vbscript:/file:）→ 永久阻止；
  //   IANA 安全 scheme（http/https/irc/ircs/mailto/xmpp）→ 直接系统打开；
  //   其余 custom scheme → 查 allowlist，已确认过直接开；首次弹确认（仅本次 / 始终允许）。
  //   归一化 + 控制符剥离在 utils/ExternalLink，防 j%2561vascript / java\nscript 绕过。
  private openExternal(rawUrl: string): void {
    const url: string = rawUrl.trim();
    if (url === '' || !hasScheme(url)) { return; }     // 相对/锚点忽略
    const klass = classifyScheme(url);
    if (klass === 'deny') { return; }                  // javascript:/data: 等永久阻止
    if (klass === 'iana') {
      this.openSafeLink(url);
      return;
    }
    // custom scheme：查 allowlist
    const scheme: string = extractScheme(url);
    loadAllowedSchemes(getPreferencesService())
      .then((allowed: string[]): void => {
        if (isAllowedScheme(scheme, allowed)) {
          this.openSafeLink(url);
        } else {
          this.confirmCustomScheme(url, scheme);
        }
      })
      .catch((): void => { this.confirmCustomScheme(url, scheme); });
  }

  // 系统级打开：http/https 走 viewData + browsable（唤浏览器，原已验证）；其余 scheme 走纯隐式 Want 让系统按 uri 匹配。
  //   startAbility 返回 Promise 必须 catch（否则系统弹默认「无可用打开方式」且丢日志）。
  private openSafeLink(url: string): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined || hostContext === null) {
      showToast(t('common.cannotOpenLink'));
      return;
    }
    const lower: string = url.toLowerCase();
    const isWeb: boolean = lower.startsWith('http://') || lower.startsWith('https://');
    const want: Want = isWeb
      ? { action: 'ohos.want.action.viewData', entities: ['entity.system.browsable'], uri: url }
      : { uri: url };
    (hostContext as common.UIAbilityContext).startAbility(want)
      .catch((): void => { showToast(t('common.noAppToOpen')); });
  }

  // custom scheme 首次确认弹窗（对齐上游「仅 custom scheme 才确认」）：
  //   取消（autoCancel）= 不打开；打开 = 仅本次；始终允许 = 持久化该 scheme 后再开（后续免确认）。
  private confirmCustomScheme(url: string, scheme: string): void {
    this.getUIContext().showAlertDialog({
      title: t('markdown.openExternalTitle'),
      message: t('markdown.openExternalMessage', kv2('scheme', scheme, 'url', url)),
      autoCancel: true,
      buttons: [
        { value: t('common.cancel'), fontColor: this.c.textSecondary, action: (): void => {} },
        { value: t('markdown.open'), fontColor: this.c.primary, action: (): void => { this.openSafeLink(url); } },
        { value: t('markdown.alwaysAllow'), fontColor: this.c.primary, action: (): void => {
          saveAllowedScheme(scheme, getPreferencesService()).then((): void => { this.openSafeLink(url); });
        } }
      ]
    });
  }

  // 写系统剪贴板（@ohos.pasteboard；API 形态对照 berry3 ClipboardUtils，实现自写）。复制成功/失败 toast 反馈。
  private copyToClipboard(text: string): void {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data)
      .then((): void => { showToast(t('common.copySuccess')); })
      .catch((): void => { showToast(t('markdown.copyFailed')); });
  }

  // 打开代码全屏预览（对照 chatcube openCodePreviewFromHybrid）
  private openCodePreview(code: string, codeType: string): void {
    if (code.trim().length === 0) {
      showToast(t('markdown.codeGenerating'));
      return;
    }
    this.previewCode = code;
    this.previewTitle = this.normalizeCodeTitle(codeType);
    this.showCodePreview = true;
  }

  // 语言标题归一：空 →「代码」；否则取小写语言名（typescript/python/…）作 sheet title
  private normalizeCodeTitle(codeType: string): string {
    const trimmed: string = codeType.trim().toLowerCase();
    return trimmed.length > 0 ? trimmed : t('markdown.code');
  }

  private closeCodePreview(): void {
    this.showCodePreview = false;
    this.previewCode = '';
    this.previewTitle = '';
  }

  // 打开图片全屏预览（仅 http(s)/data: 可应用内预览；相对/本地路径静默忽略）。
  //   ArkUI Image 直接加载 http(s) 网络图（已声明 INTERNET 权限）与 data: 内联图；其余 scheme 忽略。
  private openImagePreview(src: string): void {
    const s: string = src.trim();
    if (s === ''
      || (!s.startsWith('http://') && !s.startsWith('https://') && !s.startsWith('data:'))) {
      return;
    }
    this.previewImageSrc = s;
    this.showImagePreview = true;
  }

  private closeImagePreview(): void {
    this.showImagePreview = false;
    this.previewImageSrc = '';
  }

  // 全屏代码预览 sheet：固定标题栏（SheetDialog 白头 + ✕）+ 灰身滚动等宽代码（长按可选中复制）。
  @Builder
  private CodePreviewSheet() {
    Column() {
      SheetDialog({
        title: this.previewTitle,
        showCloseButton: true,
        onClose: () => { this.closeCodePreview(); }
      })
      Scroll() {
        Text(this.previewCode)
          .fontSize(fs(13))
          .fontColor(this.c.codeText)
          .fontFamily('monospace')
          .copyOption(CopyOptions.LocalDevice)
          .textAlign(TextAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)
      .padding({ left: 16, right: 16, top: 8, bottom: 16 })
      .backgroundColor(this.c.bg)
    }
    .width('100%')
    .height('100%')
  }

  // 代码预览 sheet 视觉配置：LARGE + 灰身(c.surface) + 毛玻璃 + 无把手/无系统关闭（对照 SessionConfigOverlay）。
  private get codePreviewSheetOpts(): SheetOptions {
    const ov: SheetOverrides = {
      detents: [SheetSize.LARGE],
      onDisappear: (): void => { this.closeCodePreview(); }
    };
    return buildSheetOptions(this.c.bg, ov);
  }

  private buildPlugin(): MarkdownPlugin {
    const plugin: MarkdownPlugin = new MarkdownPlugin();
    plugin.setIsTablePlugin(true);
    plugin.setIsStrikethroughPlugin(true);
    plugin.setIsTaskListPlugin(true);
    plugin.setIsLinkifyPlugin(true, NON_HTTPS_LINKIFY_SCHEMES);
    plugin.setIsHtmlPlugin(true);
    plugin.setIsSubPlugin(true);
    plugin.setIsSupPlugin(true);
    plugin.setIsTocPlugin(true);
    plugin.setIsFootnotePlugin(true);
    plugin.setIsLatexMathPlugin(true);   // 数学公式（对齐 chatcube；库自带数学字体）
    return plugin;
  }

  // 读 isDark/fontScale（@Trace）建立刷新依赖；签名变化 → 丢弃缓存重建 config（markdown 暗色 / 字号刷新的关键）。
  //   ★ 签名须覆盖 buildConfig 读取的全部外部输入（isDark 配色 / fontScale 字号 / isInputEnded 复制门控 / compact 尺寸档），
  //     否则缓存返回旧 config（如改字号不重建、流式结束后复制仍关）。键同 buildConfigSignature（ForEach 键 + 缓存键统一）。
  private getConfig(): MarkdownConfiguration {
    const sig: string = this.buildConfigSignature();
    if (this.cachedConfig !== null && this.cachedConfigSignature === sig) {
      return this.cachedConfig;
    }
    this.cachedConfig = this.buildConfig();
    this.cachedConfigSignature = sig;
    return this.cachedConfig;
  }

  // CJMarkdown 重建指纹（config 签名 ForEach 的键，对照 chatcube ChatMarkdownHybridRenderer:62-86）：
  //   content【不入】→ content 流式变化时键不变 → CJMarkdown 复用、仅 content @Param 更新 →
  //   incrementalAnalysis:true 增量重渲、原生组件不重建（防每 token 重建冻结根因）。
  //   isDark / isInputEnded 入 → 翻转时 CJMarkdown 一次性重建（主题切换 / 流式→完成最终解析，非 per-token，可接受）。
  private buildConfigSignature(): string {
    const isDark: boolean = getThemeState().isDark;
    const fontScale: number = getThemeState().fontScale;
    return `${isDark ? 'd' : 'l'}|${this.isInputEnded ? 'end' : 'stream'}|${this.compact ? 'c' : 'n'}|${fontScale}`;
  }

  private getPlugin(): MarkdownPlugin {
    if (this.cachedPlugin === null) {
      this.cachedPlugin = this.buildPlugin();
    }
    return this.cachedPlugin;
  }

  build() {
    // 双节点常驻容器：内层 Column 承代码全屏 sheet；图片全屏预览交给 ImagePreviewSheet（自带 bindSheet + 双指缩放）
    // （延续 SessionActionMenu 两节点模式——规避同节点 bindSheet 叠加疑问）
    Column() {
      Column() {
        // 段 ForEach：splitMarkdown 把 content 拆成「正文段 / 代码段」交替渲染。
        //   key = `${configSignature}:${index}`：签名(isDark/fontScale/isInputEnded/compact)入键 → 翻转时
        //   各段一次性重建（主题/字号/流式→完成）；index 入键 + splitter 前缀稳定(append-only) → content
        //   流式变化时前缀段键不变 → CJMarkdown/CodeBlock 复用、仅末段 @Param 增量更新（防每 token 整列重建冻结）。
        ForEach(this.segments, (seg: MarkdownSegment, index: number) => {
          if (seg.kind === 'code') {
            // 代码段 → CodeBlock 语法高亮（脱离 CJMarkdown；本库无 token 着色 API）：
            //   scrollY 长代码限高滚动（对齐 CJMarkdown 代码块）；不折叠（collapseLongContent=false，markdown 里要看全）；
            //   showCopy/showFullScreen 对齐 CJMarkdown 既有复制/全屏；onFullScreen → 复用本组件 CodePreviewSheet。
            CodeBlock({
              code: seg.text,
              language: seg.language,   // 空串 → CodeBlock label 走 t('code.code')（「代码」），高亮降级 text（全 plain）
              scrollY: true,
              collapseLongContent: false,
              showCopy: true,
              showFullScreen: true,
              onFullScreen: (): void => { this.openCodePreview(seg.text, seg.language); }
            })
              .margin({ top: this.codeBlockMargin, bottom: this.codeBlockMargin })
          } else if (seg.text.trim().length > 0) {
            // 正文段 → CJMarkdown（标题/列表/表格/行内码…）；逐段文件路径链接预处理（opt-in）
            CJMarkdown({
              content: this.mdContent(seg.text),
              isInputEnded: this.isInputEnded,
              incrementalAnalysis: this.incrementalAnalysis,
              useCangjieComponent: true,
              config: this.getConfig(),
              plugin: this.getPlugin()
            })
          } else {
            // 空 markdown 段（两代码块之间 / 代码块后尾随换行）→ 零高占位，保 ForEach index 键前缀稳定
            Column() {}
              .height(0)
          }
        }, (seg: MarkdownSegment, index: number): string => `${this.buildConfigSignature()}:${index}`)
      }
      .width('100%')
      .backgroundColor(Color.Transparent)
      .bindSheet(this.showCodePreview!!, this.CodePreviewSheet(), this.codePreviewSheetOpts)

      ImagePreviewSheet({
        src: this.previewImageSrc,
        open: this.showImagePreview,
        onClose: (): void => { this.closeImagePreview(); }
      })
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
  }
}
