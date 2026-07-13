// 外链 scheme 策略（对照 web markdown-text.tsx URI scheme policy；行为对齐上游）。
//   IANA 安全 scheme（http/https/irc/ircs/mailto/xmpp）→ 直接打开；
//   deny scheme（javascript/data/vbscript/file）→ 永远阻止；
//   其余 custom scheme → 首次确认，确认后持久化进 allowed 列表免再确认。
// ArkTS 无 Set/Map 字面量惯用，安全集合用 string[] + indexOf；Preferences 无数组助手 → JSON 串存。

import { getPreferencesService } from '../services/PreferencesService';

const IANA_SAFE_SCHEMES: string[] = ['http', 'https', 'irc', 'ircs', 'mailto', 'xmpp'];
const DENY_SCHEMES: string[] = ['javascript', 'data', 'vbscript', 'file'];
const ALLOWED_SCHEMES_KEY: string = 'hapi_allowed_schemes';

export type SchemeClass = 'iana' | 'deny' | 'custom';

// 归一化提取 scheme：最多两轮 decodeURIComponent（防双重编码绕过：j%2561vascript → j%61vascript → javascript），
//   再剥 scheme 段内 ASCII 控制符(U+0000-U+001F, DEL) + 空白（防 java\nscript 浏览器归一化为 javascript）。
//   用 charCode 逐字符过滤，避免在源码里写字面控制符（不可见、脆弱）。
//   无 ':' 或 ':' 在首位 → null（无 scheme / 相对路径）。
export function normalizedScheme(url: string): string | null {
  let value: string = url.trimStart();
  for (let i = 0; i < 2; i++) {
    try {
      const next: string = decodeURIComponent(value);
      if (next === value) { break; }
      value = next;
    } catch (e) {
      break;
    }
  }
  const colonIndex: number = value.indexOf(':');
  if (colonIndex <= 0) { return null; }
  const raw: string = value.substring(0, colonIndex);
  let cleaned: string = '';
  for (let j = 0; j < raw.length; j++) {
    const code: number = raw.charCodeAt(j);
    if (code <= 0x1F || code === 0x7F) { continue; }
    const ch: string = raw.charAt(j);
    if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r' || ch === '\f' || ch === '\v') { continue; }
    cleaned += ch;
  }
  return cleaned.toLowerCase();
}

export function classifyScheme(url: string): SchemeClass {
  const scheme: string | null = normalizedScheme(url);
  if (scheme === null) { return 'deny'; }
  if (DENY_SCHEMES.indexOf(scheme) >= 0) { return 'deny'; }
  if (IANA_SAFE_SCHEMES.indexOf(scheme) >= 0) { return 'iana'; }
  return 'custom';
}

// href 是否含 scheme 前缀（':' 在首个 /?# 前）——区分 mailto:foo（有 scheme）与 /path:x、#a、?q（相对，无）。
export function hasScheme(href: string): boolean {
  const colonIdx: number = href.indexOf(':');
  if (colonIdx <= 0) { return false; }
  const boundary: number = href.search(/[/?#]/);
  return boundary < 0 || colonIdx < boundary;
}

// 取小写 scheme 字符串作 allowlist key（无 scheme 返 ''）。
export function extractScheme(href: string): string {
  if (!hasScheme(href)) { return ''; }
  const colonIdx: number = href.indexOf(':');
  return href.substring(0, colonIdx).toLowerCase();
}

// 是否在 allowlist（custom scheme 确认过即入列）。内存比对，调用方先 load 缓存或直接 await。
export function isAllowedScheme(scheme: string, allowed: string[]): boolean {
  return scheme !== '' && allowed.indexOf(scheme) >= 0;
}

// 读持久化 allowed custom scheme 列表（JSON 数组；非法/含 deny 项过滤）。
export async function loadAllowedSchemes(): Promise<string[]> {
  try {
    const raw: string = await getPreferencesService().getString(ALLOWED_SCHEMES_KEY, '');
    if (raw === '') { return []; }
    const parsed: Object = JSON.parse(raw);
    if (!Array.isArray(parsed)) { return []; }
    const arr: Object[] = parsed as Object[];
    const out: string[] = [];
    for (let i = 0; i < arr.length; i++) {
      const s: Object = arr[i];
      if (typeof s === 'string') {
        const str: string = s as string;
        if (DENY_SCHEMES.indexOf(str) < 0) { out.push(str); }
      }
    }
    return out;
  } catch (e) {
    return [];
  }
}

// 追加一个 allowed scheme 并持久化（已存在则幂等）。
export async function saveAllowedScheme(scheme: string): Promise<void> {
  if (scheme === '') { return; }
  const list: string[] = await loadAllowedSchemes();
  if (list.indexOf(scheme) >= 0) { return; }
  list.push(scheme);
  try {
    await getPreferencesService().putString(ALLOWED_SCHEMES_KEY, JSON.stringify(list));
  } catch (e) {
    // 持久化失败忽略（本次确认仍生效）
  }
}
