import { ChatBlock } from '../chat/ChatBlock';
import { getHubClient } from '../api/HubClient';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { ImagePreviewSheet } from './ImagePreviewSheet';
import { t } from '../i18n/I18nService';

// GeneratedImageCard —— 对照 web ToolMessage.tsx:52-104 GeneratedImageCard
// agent 调 display_image 工具登记的图：aboutToAppear 按 imageId GET 二进制 → base64 data URI → Image()。
//   三态：dataUri（图，点击全屏预览）/ loading（骨架占位）/ error（无法加载文案）。
//   caption「生成图片 · fileName」。全屏预览复用 ImagePreviewSheet（含双指缩放，与 markdown 图片同源）。
// V2 状态：@Param block（imageId/fileName/mimeType 取自 block）+ sessionId；@Local dataUri/loading/error/previewOpen。

@ComponentV2
export struct GeneratedImageCard {
  @Param block: ChatBlock = new ChatBlock();
  @Param sessionId: string = '';
  @Local dataUri: string = '';
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
    this.dataUri = '';
    const r = await getHubClient().fetchGeneratedImage(this.sessionId, this.block.imageId, this.block.mimeType);
    if (r.success) {
      this.dataUri = r.dataUri;
    } else {
      this.error = r.error !== '' ? r.error : t('genImage.loadFailed');
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
      if (this.dataUri !== '') {
        Image(this.dataUri)
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
        src: this.dataUri,
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
