import { ChatBlock } from '../chat/ChatBlock';
import { getHubClient } from '../api/HubClient';
import { getGeneratedImageCache } from '../services/GeneratedImageCache';
import { buildImageCacheKey } from '../services/GeneratedImageCacheUtils';
import { isInlineVideoMimeType, isInlineAudioMimeType, isInlineImageMimeType, generatedInlineMediaLabel } from '../chat/InlineMedia';
import { AudioPlayerBar } from './AudioPlayerBar';
import { fileIo, picker } from '@kit.CoreFileKit';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { ImagePreviewSheet } from './ImagePreviewSheet';
import { t, kv } from '../i18n/I18nService';

// GeneratedImageCard —— 对照 web ToolMessage.tsx:63-189 GeneratedImageCard
// agent 调 display_image 工具登记的媒体：aboutToAppear 按 imageId GET 二进制 → 磁盘缓存 → 按 mime 分支渲染。
//   mime 分支（对照 generatedInlineMedia）：
//     image/* → Image（点击全屏预览）；audio/* → AudioPlayerBar（AVPlayer）；video/* → Video；其他 → 下载 chip。
//   **非图片媒体延后下载**（上游 shouldFetch = isImage || loadMedia）：图片自动拉；音频/视频/文件先显「Load / Prepare」
//     按钮，用户显式点击后才拉字节（上游注释：非图媒体可能数十 MB）。
//   caption = generatedInlineMediaLabel(mime) · fileName（生成视频/音频/图片/文件）。
//   下载 chip：DocumentViewPicker 系统选择器（免权限）→ 复制盘缓存字节到用户选定的文件。
// V2 状态：@Param block（imageId/fileName/mimeType 取自 block）+ sessionId；@Local filePath/loading/error/previewOpen/loadMedia。
//   ⚠️ Hub 在线机器=[] → 无法实测真音频/视频/下载，分支结构 + 编译先过，待真机验。

@ComponentV2
export struct GeneratedImageCard {
  @Param block: ChatBlock = new ChatBlock();
  @Param sessionId: string = '';
  @Local filePath: string = '';
  @Local loading: boolean = true;
  @Local error: string = '';
  @Local previewOpen: boolean = false;
  @Local loadMedia: boolean = false;   // 非图片媒体的显式拉取 gate（图片恒真）
  @Local saving: boolean = false;      // 下载进行中
  @Local saveError: string = '';       // 下载失败文案

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  // mime 分支（block.mimeType 稳定，getter 重算开销可忽略）
  private get isVideo(): boolean { return isInlineVideoMimeType(this.block.mimeType); }
  private get isAudio(): boolean { return isInlineAudioMimeType(this.block.mimeType); }
  private get isImage(): boolean { return isInlineImageMimeType(this.block.mimeType); }

  aboutToAppear(): void {
    // 图片自动拉；非图片等用户点 Load（shouldFetch = isImage || loadMedia）。
    if (this.isImage) {
      this.startFetch();
    } else {
      this.loading = false;
    }
  }

  // 按 key 拉取：命中缓存直返裸路径；未命中经 loader 拉字节写盘 + 入索引；失败可重试。
  private async startFetch(): Promise<void> {
    this.loading = true;
    this.error = '';
    const key: string = buildImageCacheKey(this.sessionId, this.block.imageId);
    try {
      this.filePath = await getGeneratedImageCache().fetch(key, this.block.mimeType, async (): Promise<ArrayBuffer> => {
        const r = await getHubClient().fetchGeneratedImageBytes(this.sessionId, this.block.imageId);
        if (r.success) {
          return r.buffer;
        }
        throw new Error(r.error);
      });
    } catch (e) {
      this.filePath = '';
      this.error = e instanceof Error && e.message !== '' ? e.message : t('genImage.loadFailed');
    }
    this.loading = false;
  }

  // 非图片媒体：用户点 Load → 置 gate + 拉取。
  private prepareMedia(): void {
    if (this.loadMedia) { return; }
    this.loadMedia = true;
    this.startFetch();
  }

  // 下载（文件分支）：系统选择器选目的地 → 复制盘缓存字节。取消静默，失败显文案。
  private async doDownload(): Promise<void> {
    if (this.filePath === '') { return; }
    this.saving = true;
    this.saveError = '';
    try {
      const opts: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      opts.newFileNames = [this.block.fileName];
      const dp: picker.DocumentViewPicker = new picker.DocumentViewPicker(getContext(this));
      const uris: string[] = await dp.save(opts);
      if (uris.length === 0) {
        // 用户取消
        this.saving = false;
        return;
      }
      // 读盘缓存字节
      const stat: fileIo.Stat = fileIo.statSync(this.filePath);
      const buf: ArrayBuffer = new ArrayBuffer(stat.size);
      const src = fileIo.openSync(this.filePath, fileIo.OpenMode.READ_ONLY);
      try {
        fileIo.readSync(src.fd, buf);
      } finally {
        fileIo.closeSync(src);
      }
      // 写入用户选定文件
      const dest = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE);
      try {
        fileIo.writeSync(dest.fd, buf);
      } finally {
        fileIo.closeSync(dest);
      }
    } catch (e) {
      this.saveError = t('genImage.downloadFailed');
    }
    this.saving = false;
  }

  // Load 按钮 i18n key
  private loadButtonLabel(): string {
    if (this.isVideo) { return 'genImage.loadVideo'; }
    if (this.isAudio) { return 'genImage.loadAudio'; }
    return 'genImage.prepareDownload';
  }

  build() {
    Column() {
      // caption：生成视频/音频/图片/文件 · fileName
      Text(t(generatedInlineMediaLabel(this.block.mimeType), kv('fileName', this.block.fileName)))
        .fontSize(fs(11))
        .fontColor(this.c.textTertiary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: 6 })

      if (this.filePath !== '') {
        // 已就绪：按 mime 分支渲染
        if (this.isImage) {
          Image(this.filePath)
            .width('100%')
            .objectFit(ImageFit.Contain)
            .borderRadius(10)
            .constraintSize({ maxHeight: 360 })
            .draggable(false)
            .onClick((): void => { this.previewOpen = true; })
        } else if (this.isAudio) {
          AudioPlayerBar({ src: this.filePath })
        } else if (this.isVideo) {
          Column() {
            Video({ src: this.filePath })
              .width('100%')
              .controls(true)
              .autoPlay(false)
              .objectFit(ImageFit.Contain)
              .borderRadius(10)
              .constraintSize({ maxHeight: 360 })
          }
        } else {
          // 下载 chip
          Row() {
            SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
              .fontSize(20)
              .fontColor([this.c.textPrimary])
            Text(this.saving ? t('genImage.downloading') : t('genImage.download', kv('fileName', this.block.fileName)))
              .fontSize(fs(13))
              .fontColor(this.c.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .margin({ left: 8 })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 14, bottom: 14 })
          .borderRadius(10)
          .backgroundColor(this.c.surfaceSelected)
          .alignItems(VerticalAlign.Center)
          .onClick((): void => { if (!this.saving) { this.doDownload(); } })
          if (this.saveError !== '') {
            Text(this.saveError)
              .fontSize(fs(11))
              .fontColor(this.c.error)
              .margin({ top: 4 })
          }
        }
      } else if (this.loading) {
        // 骨架占位（对照上游 animate-pulse 骨架；这里用 LoadingProgress 表「拉取中」）
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(this.c.textTertiary)
        }
        .width('100%')
        .height(180)
        .borderRadius(10)
        .backgroundColor(this.c.surfaceSelected)
        .justifyContent(FlexAlign.Center)
      } else if (this.error !== '') {
        Text(t('genImage.unavailable', kv('error', this.error)))
          .fontSize(fs(13))
          .fontColor(this.c.textTertiary)
          .padding({ top: 24, bottom: 24, left: 12, right: 12 })
          .width('100%')
          .textAlign(TextAlign.Center)
          .borderRadius(10)
          .backgroundColor(this.c.surfaceSelected)
      } else {
        // 非图片、未拉取：Load / Prepare 按钮（用户显式触发才下大文件）
        Row() {
          Text(t(this.loadButtonLabel()))
            .fontSize(fs(13))
            .fontColor(this.c.textPrimary)
        }
        .width('100%')
        .height(180)
        .borderRadius(10)
        .backgroundColor(this.c.surfaceSelected)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick((): void => { this.prepareMedia(); })
      }

      // 全屏预览（自带 bindSheet + 双指缩放，统一 markdown/生成图片两处；仅图片用）
      if (this.isImage) {
        ImagePreviewSheet({
          src: this.filePath,
          open: this.previewOpen,
          onClose: (): void => { this.previewOpen = false; }
        })
      }
    }
    .padding(10)
    .borderRadius(14)
    .backgroundColor(this.c.card)
    .border({ width: 0.5, color: this.c.border })
  }
}
