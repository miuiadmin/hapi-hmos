// VoiceLanguages —— 语音语言表 + ElevenLabs 语言码映射（纯层，无 @kit，可 LocalUnit 测）
// 对照 web/src/lib/languages.ts（文案/映射逐字移植；剔除上游不支持 ElevenLabs 的条目 + 重复 locale 归一）。
//
// 用途：
//   - boot：VoicePage.doBoot 把持久化的 voiceLang（locale 串，如 'zh-CN'）映射成 elevenLabsCode
//     传 voice.html overrides.agent.language（''=自动检测，不覆盖）。
//   - 设置：SettingsPage 语音分区列出可选项 + 当前值显示名。
//
// 语义对齐上游 getElevenLabsCodeFromPreference：null/''/不支持 → undefined（此处用 '' 表示，等同不设 language 覆盖）。

export class VoiceLanguage {
  code: string = '';            // locale 码；'' = 自动检测
  name: string = '';            // 英文名
  nativeName: string = '';      // 原文名
  region: string = '';          // 地区（可空）
  elevenLabsCode: string = '';  // ElevenLabs 语言码；'' = 不支持（本表已剔除）
}

// 构造助手（ArkTS 不支持 class 对象字面量，用工厂）
function mk(code: string, name: string, native: string, region: string, el: string): VoiceLanguage {
  const l: VoiceLanguage = new VoiceLanguage();
  l.code = code;
  l.name = name;
  l.nativeName = native;
  l.region = region;
  l.elevenLabsCode = el;
  return l;
}

// 可选语言表（自动检测在前；仅含 ElevenLabs 支持的语种，对照上游 LANGUAGES 取 elevenLabsCode 非空项）
export const VOICE_LANGUAGES: VoiceLanguage[] = [
  mk('', 'Auto-detect', 'Auto-detect', '', ''),
  mk('en-US', 'English', 'English', 'United States', 'en'),
  mk('en-GB', 'English', 'English', 'United Kingdom', 'en'),
  mk('zh-CN', 'Chinese', '中文', 'Simplified', 'zh'),
  mk('zh-TW', 'Chinese', '中文', 'Traditional', 'zh'),
  mk('ja-JP', 'Japanese', '日本語', '', 'ja'),
  mk('ko-KR', 'Korean', '한국어', '', 'ko'),
  mk('es-ES', 'Spanish', 'Español', 'Spain', 'es'),
  mk('fr-FR', 'French', 'Français', 'France', 'fr'),
  mk('de-DE', 'German', 'Deutsch', 'Germany', 'de'),
  mk('it-IT', 'Italian', 'Italiano', '', 'it'),
  mk('pt-BR', 'Portuguese', 'Português', 'Brazil', 'pt-br'),
  mk('pt-PT', 'Portuguese', 'Português', 'Portugal', 'pt'),
  mk('ru-RU', 'Russian', 'Русский', '', 'ru'),
  mk('ar-SA', 'Arabic', 'العربية', '', 'ar'),
  mk('hi-IN', 'Hindi', 'हिन्दी', '', 'hi'),
  mk('nl-NL', 'Dutch', 'Nederlands', '', 'nl'),
  mk('sv-SE', 'Swedish', 'Svenska', '', 'sv'),
  mk('no-NO', 'Norwegian', 'Norsk', '', 'no'),
  mk('da-DK', 'Danish', 'Dansk', '', 'da'),
  mk('fi-FI', 'Finnish', 'Suomi', '', 'fi'),
  mk('pl-PL', 'Polish', 'Polski', '', 'pl'),
  mk('tr-TR', 'Turkish', 'Türkçe', '', 'tr'),
  mk('vi-VN', 'Vietnamese', 'Tiếng Việt', '', 'vi'),
  mk('id-ID', 'Indonesian', 'Bahasa Indonesia', '', 'id'),
  mk('ms-MY', 'Malay', 'Bahasa Melayu', '', 'ms'),
  mk('tl-PH', 'Tagalog', 'Tagalog', '', 'tl'),
  mk('uk-UA', 'Ukrainian', 'Українська', '', 'uk'),
  mk('cs-CZ', 'Czech', 'Čeština', '', 'cs'),
  mk('hu-HU', 'Hungarian', 'Magyar', '', 'hu'),
  mk('ro-RO', 'Romanian', 'Română', '', 'ro'),
  mk('bg-BG', 'Bulgarian', 'Български', '', 'bg'),
  mk('el-GR', 'Greek', 'Ελληνικά', '', 'el'),
  mk('hr-HR', 'Croatian', 'Hrvatski', '', 'hr'),
  mk('sk-SK', 'Slovak', 'Slovenčina', '', 'sk')
];

// 自动检测的 locale 码常量（空串）
export const VOICE_LANG_AUTO: string = '';

// 按 locale 码查表（对照 findLanguageByCode；'' 找自动检测项；未命中返 null）
export function findLanguageByCode(code: string): VoiceLanguage | null {
  for (let i = 0; i < VOICE_LANGUAGES.length; i++) {
    if (VOICE_LANGUAGES[i].code === code) { return VOICE_LANGUAGES[i]; }
  }
  return null;
}

// locale 偏好 → ElevenLabs 语言码（对照 getElevenLabsCodeFromPreference）
//   ''（自动检测）/不支持/未命中 → ''（VoicePage 据此不设 language 覆盖，交给 ElevenLabs 自动检测）
export function getElevenLabsCodeFromPreference(code: string): string {
  const lang: VoiceLanguage | null = findLanguageByCode(code);
  if (lang === null) { return ''; }
  return lang.elevenLabsCode;
}

// 显示名（对照 getLanguageDisplayName）：name 与 nativeName 不同 → "name (native)"；带 region → " - region"
export function getLanguageDisplayName(lang: VoiceLanguage): string {
  let head: string;
  if (lang.name !== lang.nativeName) {
    head = lang.name + ' (' + lang.nativeName + ')';
  } else {
    head = lang.name;
  }
  if (lang.region !== '') {
    return head + ' - ' + lang.region;
  }
  return head;
}
