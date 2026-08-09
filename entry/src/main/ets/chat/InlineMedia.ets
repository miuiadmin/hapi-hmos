// 内联媒体 mime 判定纯层（零 @kit，LocalUnit 可测）—— 对照上游
//   web/src/lib/generatedInlineMedia.ts：isInline{Audio,Video,Image}MimeType + generatedInlineMediaLabel。
//
//   isInlineImageMimeType 把空/未设 mime 也当图片（向后兼容：旧生成图无 mime 字段，按图片渲染）。
//   generatedInlineMediaLabel：按 mime 返回展示文案（生成视频 / 生成音频 / 生成图片 / 生成文件）。

export function isInlineVideoMimeType(mimeType: string): boolean {
  return mimeType.startsWith('video/');
}

export function isInlineAudioMimeType(mimeType: string): boolean {
  return mimeType.startsWith('audio/');
}

// 空 mime 视为图片（历史生成图无 mime，兜底图片渲染）。
export function isInlineImageMimeType(mimeType: string): boolean {
  return mimeType === '' || mimeType.startsWith('image/');
}

export function generatedInlineMediaLabel(mimeType: string): string {
  if (isInlineVideoMimeType(mimeType)) { return 'genImage.videoCaption'; }
  if (isInlineAudioMimeType(mimeType)) { return 'genImage.audioCaption'; }
  if (isInlineImageMimeType(mimeType)) { return 'genImage.caption'; }
  return 'genImage.fileCaption';
}

// 内联图 tiny 放大（对照上游 ToolMessage.tsx computeTinyImageScale，#1405）：
//   图最大边 < 64px → 放大到 64px（封顶 16×），避免微小生成图标按原始小尺寸难辨；
//   细长图（一边 ≤0 或最大边 ≥64）恒 1（不放大畸形图）。纯函数，LocalUnit 可测。
const MIN_INLINE_IMAGE_DIMENSION: number = 64;
export function computeTinyImageScale(width: number, height: number): number {
  const maxDim: number = Math.max(width, height);
  if (width <= 0 || height <= 0 || maxDim >= MIN_INLINE_IMAGE_DIMENSION) {
    return 1;
  }
  return Math.min(MIN_INLINE_IMAGE_DIMENSION / maxDim, 16);
}
