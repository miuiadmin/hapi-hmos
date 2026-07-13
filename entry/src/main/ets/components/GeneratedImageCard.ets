import { ChatBlock } from '../chat/ChatBlock';
import { getHubClient } from '../api/HubClient';
import { getGeneratedImageCache } from '../services/GeneratedImageCache';
import { buildImageCacheKey } from '../services/GeneratedImageCacheUtils';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { ImagePreviewSheet } from './ImagePreviewSheet';
import { t } from '../i18n/I18nService';

// GeneratedImageCard —— 对照 web ToolMessage.tsx:52-104 GeneratedImageCard
// agent 调 display_image 工具登记的图：aboutToAppear 按 imageId GET 二进制 → 磁盘缓存 → Image(裸沙箱路径)。
//   三态：filePath（图，点击全屏预览）/ loading（骨架占位）/ error（无法加载文案）。
//   caption「生成图片 · fileName」。全屏预览复用 ImagePreviewSheet（含双指缩放，与 markdown 图片同源）。
// V2 状态：@Param block（imageId/fileName/mimeType 取自 block）+ sessionId；@Local filePath/loading/error/previewOpen。

@ComponentV2
export struct GeneratedImageCard {
  @Param block: ChatBlock = new ChatBlock();
  @Param sessionId: string = '';
  @Local filePath: string = '';
  @Local loading: boolean = true;
  @Local error: string = '';
  @Local previewOpen: boolean = false;

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  aboutToAppear(): void {
    this.loadImage();
  }

  private async loadImage(): Promise<void> {
    this.loading = true;
    this.error = '';
    // 经磁盘缓存（key=session:image）：命中直显裸路径，未命中拉字节写盘；同图并发去重。
    //   失败 loader 重抛 → 不缓存、可重试；error 文案保留 Hub 原文（空则回落 loadFailed）。
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

  build() {
    Column() {
      Text(t('genImage.caption', { fileName: this.block.fileName }))
        .fontSize(fs(11))
        .fontColor(this.c.textTertiary)
        .maxLines(1)
        .textOverflow(TextOverflow.Ellipsis)
        .margin({ bottom: 6 })
      if (this.filePath !== '') {
        Image(this.filePath)
          .width('100%')
          .objectFit(ImageFit.Contain)
          .borderRadius(10)
          .constraintSize({ maxHeight: 360 })
          .draggable(false)
          .onClick((): void => { this.previewOpen = true; })
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
      } else {
        Text(t('genImage.unavailable', { error: this.error }))
          .fontSize(fs(13))
          .fontColor(this.c.textTertiary)
          .padding({ top: 24, bottom: 24, left: 12, right: 12 })
          .width('100%')
          .textAlign(TextAlign.Center)
          .borderRadius(10)
          .backgroundColor(this.c.surfaceSelected)
      }

      // 全屏预览（自带 bindSheet + 双指缩放，统一 markdown/生成图片两处）
      ImagePreviewSheet({
        src: this.filePath,
        open: this.previewOpen,
        onClose: (): void => { this.previewOpen = false; }
      })
    }
    .padding(10)
    .borderRadius(14)
    .backgroundColor(this.c.surface)
    .border({ width: 0.5, color: this.c.border })
  }
}
