// Markdown 排版尺寸推导（移植自 chatcube utils/MarkdownTypographyUtils.ets，MIT）。
//   纯函数：从一个正文 textSize 派生标题分级字号 / 行高 / 块间距，供 markdown_hybrid 的 theme setter 使用。
//   chatcube 同款语义；ArkTS 元组 [number×6] 直接用（标题 6 级）。
//   compact=true 走紧凑档（reasoning 气泡等次级文本；本期默认 false）。

// 标题 6 级的（字号 / 行高）元组
export type MarkdownTitleScale = [number, number, number, number, number, number];

function clamp(value: number, minValue: number, maxValue: number): number {
  return Math.max(minValue, Math.min(maxValue, value));
}

// 正文行高：compact ×1.35 / 正常 ×1.4（相对 max(textSize,10)）
export function getMarkdownTextLineHeight(textSize: number, compact: boolean = false): number {
  const normalizedTextSize: number = Math.max(textSize, 10);
  const multiplier: number = compact ? 1.35 : 1.4;
  return Math.round(normalizedTextSize * multiplier);
}

// 标题分级字号：H1=+4 / H2=+3 / H3=+2 / H4=+1 / H5=H6=正文（compact 各档再 −1）
export function getMarkdownTitleSizes(textSize: number, compact: boolean = false): MarkdownTitleScale {
  const nt: number = Math.max(textSize, 10);
  if (compact) {
    return [nt + 3, nt + 2, nt + 1, nt + 1, nt, nt];
  }
  return [nt + 4, nt + 3, nt + 2, nt + 1, nt, nt];
}

// 标题分级行高：各档字号 ×(compact 1.28 / 正常 1.3)
export function getMarkdownTitleLineHeights(titleSizes: MarkdownTitleScale, compact: boolean = false): MarkdownTitleScale {
  const multiplier: number = compact ? 1.28 : 1.3;
  return [
    Math.round(titleSizes[0] * multiplier),
    Math.round(titleSizes[1] * multiplier),
    Math.round(titleSizes[2] * multiplier),
    Math.round(titleSizes[3] * multiplier),
    Math.round(titleSizes[4] * multiplier),
    Math.round(titleSizes[5] * multiplier)
  ];
}

// 块间垂直间距：clamp(round(textSize×0.55), 7, 12)（compact clamp 6~10）
export function getMarkdownBlockSpacing(textSize: number, compact: boolean = false): number {
  const normalizedTextSize: number = Math.max(textSize, 10);
  if (compact) {
    return clamp(Math.round(normalizedTextSize * 0.5), 6, 10);
  }
  return clamp(Math.round(normalizedTextSize * 0.55), 7, 12);
}
