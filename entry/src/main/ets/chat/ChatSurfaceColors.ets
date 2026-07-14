// ChatSurfaceColors —— 聊天气泡自定义配色的纯算法层（无 @kit，LocalUnit 可测）。
// 对照 web/src/hooks/useChatSurfaceColors.ts（mixHex/resolve/getAccent/parse/toPreset/toCustom）。
//
// 上游用 localStorage + CSS 变量 + MutationObserver；鸿蒙改为：
//   - 持久化串（'default'|'preset:soft-x'|'custom:#hex'）由 ChatSurfaceColorsService 经 Preferences 存，
//     @Trace toolGroupBg/userMessageBg 存 resolve 后的 hex（''=用 palette 默认），消费点直读触发重渲染。
//   - 主题（isDark）变化时 service.reapply() 重 resolve（base/ratio 随 isDark 变）。
//
// 关键差异（决策）：上游两 surface 共用中性 base #f2f4f6/#2b2f34；本仓 base 由调用方传入——
//   tool-group base = paletteOf(isDark).surface（与上游中性面 1:1）；
//   user-message base = paletteOf(isDark).primary（染现有蓝气泡，文字保持白）。
//   resolveSurfaceColor 因此把 base 作参数（保持本纯层不依赖 palette，可单测）。

// 偏好串编码（ArkTS 无模板字面量类型 → string）：
//   'default' | 'preset:soft-blue' | 'preset:soft-green' | 'preset:soft-yellow' | 'custom:#rrggbb'
export type ChatSurfaceColorPreference = string;
export type ChatSurfaceColorPreset = 'default' | 'soft-blue' | 'soft-green' | 'soft-yellow';

export const DEFAULT_CHAT_SURFACE_COLOR_PREFERENCE: ChatSurfaceColorPreference = 'default';
export const DEFAULT_PICKER_COLOR: string = '#f2f4f6';

// 预置强调色（对照上游 PRESET_ACCENTS，逐字）
export const PRESET_ACCENTS: Record<string, string> = {
  'soft-blue': '#7db7ff',
  'soft-green': '#8fd19e',
  'soft-yellow': '#f0d77a'
};

const HEX_COLOR_REGEX: RegExp = /^#[0-9a-f]{6}$/i;
const CUSTOM_PREFIX: string = 'custom:';
const PRESET_PREFIX: string = 'preset:';

class Rgb {
  r: number = 0;
  g: number = 0;
  b: number = 0;
}

export function isHexColor(value: string): boolean {
  return HEX_COLOR_REGEX.test(value);
}

// 归一化为 #rrggbb 小写；非法返 null（对照 normalizeHexColor）
export function normalizeHexColor(value: string): string | null {
  const normalized: string = value.trim().toLowerCase();
  return isHexColor(normalized) ? normalized : null;
}

// —— hex ↔ rgb ——（ArkTS 无元组解构 → Rgb 类）
function hexToRgb(hex: string): Rgb {
  const s: string = hex.charAt(0) === '#' ? hex.substring(1) : hex;
  const r: Rgb = new Rgb();
  r.r = parseHexByte(s, 0);
  r.g = parseHexByte(s, 2);
  r.b = parseHexByte(s, 4);
  return r;
}

function parseHexByte(s: string, pos: number): number {
  const hi: number = hexDigit(s.charCodeAt(pos));
  const lo: number = hexDigit(s.charCodeAt(pos + 1));
  return hi * 16 + lo;
}

function hexDigit(c: number): number {
  if (c >= 48 && c <= 57) { return c - 48; }       // 0-9
  if (c >= 65 && c <= 70) { return c - 65 + 10; }  // A-F
  if (c >= 97 && c <= 102) { return c - 97 + 10; } // a-f
  return 0;
}

function clampChannel(value: number): number {
  if (value < 0) { return 0; }
  if (value > 255) { return 255; }
  return value;
}

function pad2(n: number): string {
  const s: string = n.toString(16);
  return s.length < 2 ? '0' + s : s;
}

export function rgbToHex(r: number, g: number, b: number): string {
  return '#' + pad2(clampChannel(r)) + pad2(clampChannel(g)) + pad2(clampChannel(b));
}

// 逐通道线性插值（对照 mixHex）：out = round(base + (accent - base) * ratio)
export function mixHex(base: string, accent: string, ratio: number): string {
  const bt: Rgb = hexToRgb(base);
  const at: Rgb = hexToRgb(accent);
  return rgbToHex(
    Math.round(bt.r + (at.r - bt.r) * ratio),
    Math.round(bt.g + (at.g - bt.g) * ratio),
    Math.round(bt.b + (at.b - bt.b) * ratio)
  );
}

// 偏好 → 强调色（default→null；preset→PRESET_ACCENTS；custom→归一化 hex）（对照 getAccentColor）
export function getAccentColor(pref: ChatSurfaceColorPreference): string | null {
  if (pref === DEFAULT_CHAT_SURFACE_COLOR_PREFERENCE) { return null; }
  if (startsWith(pref, PRESET_PREFIX)) {
    const name: string = pref.substring(PRESET_PREFIX.length);
    const v: string | undefined = PRESET_ACCENTS[name];
    return v !== undefined ? v : null;
  }
  if (startsWith(pref, CUSTOM_PREFIX)) {
    return normalizeHexColor(pref.substring(CUSTOM_PREFIX.length));
  }
  return null;
}

// 偏好 + 主题 + base → 染色 hex（default→null 表用 palette 默认）（对照 resolveSurfaceColor）
//   ratio：custom dark=0.22/light=0.34；preset dark=0.2/light=0.3（逐字上游）
export function resolveSurfaceColor(pref: ChatSurfaceColorPreference, isDark: boolean, base: string): string | null {
  const accent: string | null = getAccentColor(pref);
  if (accent === null) { return null; }
  const ratio: number = startsWith(pref, CUSTOM_PREFIX)
    ? (isDark ? 0.22 : 0.34)
    : (isDark ? 0.2 : 0.3);
  return mixHex(base, accent, ratio);
}

// 偏好 → 取色器显示色（default→DEFAULT_PICKER_COLOR；preset/custom→其强调色）（对照 getChatSurfaceColorPickerValue）
export function getPickerValue(pref: ChatSurfaceColorPreference): string {
  const accent: string | null = getAccentColor(pref);
  return accent !== null ? accent : DEFAULT_PICKER_COLOR;
}

// preset → 偏好串（对照 toPresetChatSurfaceColorPreference）
export function toPresetPreference(preset: ChatSurfaceColorPreset): ChatSurfaceColorPreference {
  return preset === 'default' ? DEFAULT_CHAT_SURFACE_COLOR_PREFERENCE : PRESET_PREFIX + preset;
}

// hex 输入 → 偏好串（非法回落 DEFAULT_PICKER_COLOR）（对照 toCustomChatSurfaceColorPreference）
export function toCustomPreference(value: string): ChatSurfaceColorPreference {
  const normalized: string | null = normalizeHexColor(value);
  return CUSTOM_PREFIX + (normalized !== null ? normalized : DEFAULT_PICKER_COLOR);
}

// 原始存储串 → 偏好（非法/缺省→default）（对照 parseChatSurfaceColorPreference）
export function parseChatSurfaceColorPreference(raw: string): ChatSurfaceColorPreference {
  if (raw === 'default' || raw === 'preset:soft-blue' ||
    raw === 'preset:soft-green' || raw === 'preset:soft-yellow') {
    return raw;
  }
  if (startsWith(raw, CUSTOM_PREFIX)) {
    const normalized: string | null = normalizeHexColor(raw.substring(CUSTOM_PREFIX.length));
    if (normalized !== null) { return CUSTOM_PREFIX + normalized; }
  }
  return DEFAULT_CHAT_SURFACE_COLOR_PREFERENCE;
}

// —— 字符串前缀判定（手写，零依赖）——
function startsWith(s: string, prefix: string): boolean {
  if (s.length < prefix.length) { return false; }
  for (let i = 0; i < prefix.length; i++) {
    if (s.charAt(i) !== prefix.charAt(i)) { return false; }
  }
  return true;
}
