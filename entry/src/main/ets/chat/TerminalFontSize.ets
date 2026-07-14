// 终端字号纯逻辑层（无 @kit，LocalUnit 可测）。
//   对照上游 web 终端设置：离散档位 [9,11,13,15,17]，默认 13，可实时改不需重启。
//   本层仅常量 + 归一化函数；响应式状态 + 持久化在 services/TerminalFontSizeService.ets（镜像范式）。

// 合法离散档位（对照上游；ArkTS 用 number[] 而非 as const）
export const VALID_TERMINAL_FONT_SIZES: number[] = [9, 11, 13, 15, 17];

// 默认字号（档位中位）
export const DEFAULT_TERMINAL_FONT_SIZE: number = 13;

// 归一化：合法档位透传，非法（含 NaN/越界/非档位整数）→ DEFAULT。
//   对照上游 normalizeTerminalFontSize 语义（离散集合，非连续 clamp）。
export function normalizeTerminalFontSize(raw: number): number {
  for (let i = 0; i < VALID_TERMINAL_FONT_SIZES.length; i++) {
    if (VALID_TERMINAL_FONT_SIZES[i] === raw) { return raw; }
  }
  return DEFAULT_TERMINAL_FONT_SIZE;
}
