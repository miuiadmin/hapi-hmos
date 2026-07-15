// Agent flavor 徽章纯逻辑层（无 @kit，LocalUnit 可测）。
//   逐字移植上游 web/src/components/AgentFlavorIcon.tsx FLAVOR_BADGES：
//   claude→'Cl'/#d97706、codex→'Cx'/#111827、cursor→'Cu'/#0f766e、gemini→'Gm'/#2563eb、
//   kimi→'Km'/#7c3aed、opencode→'Op'/#15803d；未知→'Un'/中性灰。
//   上游颜色用 Tailwind bg-[#rrggbb] text-white；本层取 bg hex 作色块背景，字色恒白（ArkUI 渲染）。
//   未知上游为 var(--app-secondary-bg)/var(--app-hint)（主题相关）；本层用固定中性灰 #6b7280 + 白字
//   （纯层不依赖主题，可测；faithfulness gap 注明）。normalizeFlavor = trim + toLowerCase（上游同款）。

// flavor 徽章：双字母 label + 背景色 hex
export interface FlavorBadge {
  label: string;
  bgHex: string;
}

// 6 已知 flavor（对照上游 FLAVOR_BADGES，顺序一致）
export const FLAVOR_BADGES: Record<string, FlavorBadge> = {
  'claude': { label: 'Cl', bgHex: '#d97706' },
  'codex': { label: 'Cx', bgHex: '#111827' },
  'cursor': { label: 'Cu', bgHex: '#0f766e' },
  'gemini': { label: 'Gm', bgHex: '#2563eb' },
  'kimi': { label: 'Km', bgHex: '#7c3aed' },
  'opencode': { label: 'Op', bgHex: '#15803d' }
};

// 未知 flavor 徽章：中性灰 + 白字（固定色，不随主题；上游用 CSS 变量）
export const UNKNOWN_FLAVOR_BADGE: FlavorBadge = { label: 'Un', bgHex: '#6b7280' };

// 归一化：trim + toLowerCase（上游 normalized = (flavor ?? '').trim().toLowerCase()）
export function normalizeFlavor(flavor: string): string {
  let s: string = flavor;
  // trim：手写去首尾空白（ArkTS string.trim() 可用，显式调用）
  s = s.trim();
  // toLowerCase：ASCII 手写（避依赖 locale 的 toLocaleLowerCase；flavor 串均 ASCII）
  let out: string = '';
  for (let i = 0; i < s.length; i++) {
    const code: number = s.charCodeAt(i);
    if (code >= 65 && code <= 90) {   // 'A'..'Z'
      out += String.fromCharCode(code + 32);
    } else {
      out += s.charAt(i);
    }
  }
  return out;
}

// flavor → 徽章（查表 ?? UNKNOWN；上游 badge = FLAVOR_BADGES[normalized] ?? UNKNOWN_FLAVOR_BADGE）
export function flavorBadge(flavor: string): FlavorBadge {
  const key: string = normalizeFlavor(flavor);
  const b: FlavorBadge | undefined = FLAVOR_BADGES[key];
  if (b !== undefined) { return b; }
  return UNKNOWN_FLAVOR_BADGE;
}

// flavor → 双字母 label（'Cl'/'Cx'/…；未知 'Un'）
export function flavorLabel(flavor: string): string {
  return flavorBadge(flavor).label;
}

// flavor → 背景色 hex（'#rrggbb' 串，ArkUI '#rrggbb' 字符串接受）
export function flavorColorHex(flavor: string): string {
  return flavorBadge(flavor).bgHex;
}

// 是否 Codex 系 flavor（对照上游 shared/src/flavors.ts + isCodexFamilyFlavor）。
//   codex / gemini / kimi / opencode 共享 Codex 风格的权限页变体（Yes/Yes-for-session/Abort）。
export function isCodexFamilyFlavor(flavor: string): boolean {
  const f: string = normalizeFlavor(flavor);
  return f === 'codex' || f === 'gemini' || f === 'kimi' || f === 'opencode';
}

// 是否 Codex 系会话（对照上游 PermissionFooter isCodexSession = isCodexFamilyFlavor(flavor)
//   || toolName 前缀 Codex/Gemini/OpenCode）。flavor 命中即视为 Codex 系；否则看工具名前缀。
//   端口惯例用 indexOf===0 替上游 startsWith。
export function isCodexSessionByFlavor(flavor: string, toolName: string): boolean {
  if (isCodexFamilyFlavor(flavor)) {
    return true;
  }
  return toolName.indexOf('Codex') === 0
    || toolName.indexOf('Gemini') === 0
    || toolName.indexOf('OpenCode') === 0;
}
