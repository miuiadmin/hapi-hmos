// VoiceVoices —— 预置声音表 + 显示名（纯层，无 @kit，可 LocalUnit 测）
// 对照 web/src/lib/voices.ts（VOICES/DEFAULT_VOICE_ID/getFallbackVoices 文案逐字移植）。
//
// 用途：
//   - 设置：SettingsPage 语音声音分区列出预置声 + 显示名（zh-CN 取中文名，否则英文名）。
//   - boot：VoicePage.doBoot 读持久化 voiceId 传 fetchVoiceToken（''=默认/Hub 路由）。
//
// 设计：预置声固定 10 个；用户克隆声（fetchVoices 拉回）在 SettingsPage 动态并入，不在本表。

export class VoicePreset {
  id: string = '';          // ElevenLabs voice id
  name: string = '';        // 英文名
  zhName: string = '';      // 中文名（zh-CN 显示用；无则空，回落 name）
  gender: string = '';      // 'female' | 'male'
  description: string = ''; // 简述
}

// 构造助手（ArkTS 不支持 class 对象字面量）
function mk(id: string, name: string, zhName: string, gender: string, desc: string): VoicePreset {
  const v: VoicePreset = new VoicePreset();
  v.id = id;
  v.name = name;
  v.zhName = zhName;
  v.gender = gender;
  v.description = desc;
  return v;
}

// 默认声音 id（对照上游 DEFAULT_VOICE_ID；''=Hub 默认 agent 路由，非此预设）
export const DEFAULT_VOICE_ID: string = 'cgSgspJ2msm6clMCkdW9';

// 预置声音表（对照上游 VOICES；顺序/字段逐字）
export const VOICE_PRESETS: VoicePreset[] = [
  mk('cgSgspJ2msm6clMCkdW9', 'Jessica', '杰西卡', 'female', 'Default — warm, conversational'),
  mk('21m00Tcm4TlvDq8ikWAM', 'Rachel', '瑞秋', 'female', 'Calm, professional'),
  mk('EXAVITQu4vr4xnSDxMaL', 'Bella', '贝拉', 'female', 'Soft, warm'),
  mk('TxGEqnHWrfWFTfGW9XjX', 'Josh', '乔什', 'male', 'Deep, smooth'),
  mk('pNInz6obpgDQGcFmaJgB', 'Adam', '亚当', 'male', 'Narration, clear'),
  mk('AZnzlk1XvdvUeBnXmlld', 'Domi', '', 'female', 'Strong, confident'),
  mk('MF3mGyEYCl7XYWbV9V6O', 'Elli', '', 'female', 'Young, clear'),
  mk('VR6AewLTigWG4xSOukaG', 'Arnold', '', 'male', 'Crisp, authoritative'),
  mk('ErXwobaYiN019PkySvjV', 'Antoni', '', 'male', 'Well-rounded'),
  mk('yoZ06aMxZJJ28mfd3POQ', 'Sam', '', 'male', 'Raspy, dynamic')
];

// 「Hub 默认」声音的占位 id（voiceId='' 时不取预设；仅展示用）
export const VOICE_DEFAULT_KEY: string = '';

// 按 id 查预设（对照 getVoiceById；未命中返 null）
export function getPresetById(id: string): VoicePreset | null {
  for (let i = 0; i < VOICE_PRESETS.length; i++) {
    if (VOICE_PRESETS[i].id === id) { return VOICE_PRESETS[i]; }
  }
  return null;
}

// 声音显示名（对照 getFallbackVoices 的 alias 逻辑）：zh-CN → 中文名（无则英文名）；其余 → 英文名。
//   预设外 id（如用户克隆声）→ 回落 id（克隆声无本地化名，列表里由调用方另传 name）。
export function getPresetDisplayName(id: string, locale: string): string {
  const p: VoicePreset | null = getPresetById(id);
  if (p === null) { return id; }
  if (locale === 'zh-CN' && p.zhName !== '') { return p.zhName; }
  return p.name;
}
