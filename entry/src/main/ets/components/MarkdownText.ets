import {
  CJMarkdown,
  MarkdownConfiguration,
  MarkdownPlugin,
  MarkdownTheme
} from '@cangjie-tpc/markdown_hybrid'
import { Want, common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { fs, paletteOf, PaletteColors, toArgb, getThemeState } from '../theme/ThemeService'
import { showToast } from '../utils/Toast';
import { NON_HTTPS_LINKIFY_SCHEMES } from '../chat/LinkSchemes';
import { t } from '../i18n/I18nService';
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

// 极简 Markdown 渲染组件：封装 @cangjie-tpc/markdown_hybrid（Apache-2.0）的 CJMarkdown
// 参考 chatcube ChatMarkdownHybridRenderer（MIT），裁掉其 AppUiState 主题系统 / 排版工具 / 媒体图标依赖：
//   - 颜色走统一主题（theme/ThemeService）：buildConfig 读 paletteOf(isDark) + toArgb 转 ARGB；
//     getConfig 在 isDark 变化时丢弃缓存重建（markdown_hybrid 缓存数字配色，无观察钩子 → 手动失效）
//   - 复制按钮已启用（图标 app.media.markdown_code_copy + setCodeCopyCallback 写系统剪贴板）；
//     全屏按钮已启用（setIsCodeFullScreen(true) + setCodeFullScreenCallback → bindSheet 大尺寸代码预览，复用 markdown_code_fullscreen 图标）
//   - 不开 LaTeX 插件（agent 文本罕含公式，且其需额外字号/颜色格式设置），后续需要再补
//   - 仓颉引擎：useCangjieComponent=true（库本体即 Cangjie 实现，依赖其内置 .so）
// hapi 简化：每条 message-received 是完整消息（非 token 增量）→ isInputEnded 恒 true，无需增量分析
// 所有 setter 名逐字对照 chatcube 同版本（1.3.6）源码，禁止臆造

@ComponentV2
export struct MarkdownText {
  @Param content: string = '';
  // hapi 消息均为完整消息，默认已完成（无需流式增量分析）
  @Param isInputEnded: boolean = true;

  // 裸文件路径 → hapi-file: 链接（喂 CJMarkdown 前预处理；对照上游 remarkFilePathLinks MDAST 插件）。
  //   opt-in：仅当上层接了 onOpenFilePath 并显式 linkFilePaths=true 才扫描——避免工具卡 / reasoning 等无 nav
  //   上下文的叶子场景出现「点得动却没反应」的死链接（上游能处处链是因 markdown-text 恒有 session 上下文）。
  //   scanFilePaths 是纯函数、幂等（无命中返回原引用）→ @Computed 仅依赖 @Param 基本类型，无链式追踪。
  @Param linkFilePaths: boolean = false;
  @Computed get renderedContent(): string {
    return this.linkFilePaths ? scanFilePaths(this.content) : this.content;
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
  private cachedForIsDark: boolean = false;     // config 缓存对应的明暗；变化则重建（驱动 markdown 暗色刷新）

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

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

    const textSize: number = 15;
    const codeTextSize: number = Math.max(textSize - 1, 12);

    // 解析器 / 行为
    theme.setIsMarkdownParserSync(false);
    theme.setIsCodeBlockParserSync(false);
    theme.setIsCodeFullScreen(true);             // 开启代码块全屏按钮（点 → 全屏 sheet）
    theme.setIconWidthAndHeight(22);             // 代码块图标尺寸（复制 / 全屏，对照 chatcube）
    theme.setCodeCopyIcon($r('app.media.markdown_code_copy'));
    theme.setCodeFullScreenIcon($r('app.media.markdown_code_fullscreen'));
    theme.setBlockFirstTopMargin(0);
    theme.setBlockLastBottomMargin(0);
    theme.setBlockTopAndBottomMargins(6);
    theme.setOpenGestureSwipe(false);

    // 正文段落
    theme.setParagraphTextSize(textSize);
    theme.setParagraphTextLineHeight(textSize + 6);
    theme.setParagraphTextColor(toArgb(c.textPrimary));
    theme.setParagraphTopMargins(0);
    theme.setParagraphBottomMargins(0);

    // 标题（仅配色，分级字号用库默认）
    theme.setHeadingTextColor(toArgb(c.textPrimary));
    theme.setHeadingBreakColor(toArgb(c.border));

    // 链接
    theme.setLinkColor(toArgb(c.primary));
    theme.setLinkSize(textSize);
    theme.setLinkLineHeight(textSize + 6);
    theme.setLinkBackGroupColor(0x00000000);
    theme.setIsLinkUnderlined(false);

    // 引用块
    theme.setBlockQuoteColor(toArgb(c.primary));
    theme.setBlockQuoteBackGroupColor(toArgb(c.codeBg));
    theme.setBlockQuoteWidth(3);
    theme.setBlockQuoteLeftMargin(10);
    theme.setBlockQuoteRightMargin(0);
    theme.setBlockQuoteTopAndBottomMargins(6);

    // 行内修饰（删除线 / 下划线 / 上下标字色，字号用库默认）
    theme.setStrikethroughColor(toArgb(c.textPrimary));
    theme.setUnderlineColor(toArgb(c.textPrimary));
    theme.setSubTextColor(toArgb(c.textPrimary));
    theme.setSupTextColor(toArgb(c.textPrimary));

    // 行内代码
    theme.setCodeTextColor(toArgb(c.codeText));
    theme.setCodeBackgroundColor(toArgb(c.codeBg));
    theme.setCodeTextSize(codeTextSize);
    theme.setCodeTypeface('monospace');

    // 代码块
    theme.setCodeBlockTextColor(toArgb(c.codeText));
    theme.setCodeBlockBackgroundColor(toArgb(c.codeBg));
    theme.setCodeBlockTextSize(codeTextSize);
    theme.setCodeBlockTypeface('monospace');
    theme.setCodeBlockLineHeight(codeTextSize + 4);
    theme.setCodeBlockRadius(8);
    theme.setCodeBlockLineNumberHide(false);
    theme.setCodeBlockIconTextHide(false);
    theme.setIsSeparateCodeBlock(false);

    // 表格
    theme.setTableCellPadding(6);
    theme.setTableBorderColor(toArgb(c.border));
    theme.setTableBorderWidth(1);
    theme.setTableOddRowBackgroundColor(0x00000000);
    theme.setTableEvenRowBackgroundColor(toArgb(c.codeBg));
    theme.setTableHeaderRowBackgroundColor(toArgb(c.codeBg));
    theme.setTableContentTextColor(toArgb(c.textPrimary));
    theme.setTableContentTextSize(textSize);
    theme.setTableTitleTextColor(toArgb(c.textPrimary));
    theme.setTableTitleTextSize(textSize);
    theme.setTableRadius(6);
    theme.setTableScrollBarShow(false);

    // 分割线 / 暗色模式
    theme.setThematicBreakColor(toArgb(c.border));
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
      message: t('markdown.openExternalMessage', { scheme: scheme, url: url }),
      autoCancel: true,
      buttons: [
        { text: t('common.cancel'), color: this.c.textSecondary },
        { text: t('markdown.open'), color: this.c.primary, action: (): void => { this.openSafeLink(url); } },
        { text: t('markdown.alwaysAllow'), color: this.c.primary, action: (): void => {
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

  // 全屏代码预览 sheet：可滚动等宽代码 + 长按可选中复制（dragBar/showClose/title 由 bindSheet 配置提供）
  @Builder
  private CodePreviewSheet() {
    Column() {
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.c.codeBg)
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
    return plugin;
  }

  // 读 isDark（@Trace）建立刷新依赖；isDark 变化 → 丢弃缓存重建 config（markdown 暗色刷新的关键）
  private getConfig(): MarkdownConfiguration {
    const isDark: boolean = getThemeState().isDark;
    if (this.cachedConfig === null || this.cachedForIsDark !== isDark) {
      this.cachedConfig = this.buildConfig();
      this.cachedForIsDark = isDark;
    }
    return this.cachedConfig;
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
        CJMarkdown({
          content: this.renderedContent,
          isInputEnded: this.isInputEnded,
          incrementalAnalysis: false,
          useCangjieComponent: true,
          config: this.getConfig(),
          plugin: this.getPlugin()
        })
      }
      .width('100%')
      .backgroundColor(Color.Transparent)
      .bindSheet(this.showCodePreview!!, this.CodePreviewSheet(), {
        height: SheetSize.LARGE,
        detents: [SheetSize.LARGE],
        dragBar: true,
        showClose: true,
        title: { title: this.previewTitle },
        onDisappear: (): void => { this.closeCodePreview(); }
      })

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
