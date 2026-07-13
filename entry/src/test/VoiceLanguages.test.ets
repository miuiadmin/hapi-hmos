// VoiceLanguages 单测 —— 语音语言表 + ElevenLabs 语言码映射（纯层，无 @kit，LocalUnit 可加载）。
//   对照 VoiceFormatters.test / CodeHighlight.test 范式：同步断言，覆盖表结构 + 映射 + 显示名。

import { describe, it, expect } from '@ohos/hypium';
import {
  VOICE_LANGUAGES,
  VOICE_LANG_AUTO,
  findLanguageByCode,
  getElevenLabsCodeFromPreference,
  getLanguageDisplayName,
  VoiceLanguage
} from '../main/ets/chat/VoiceLanguages';

export default function voiceLanguagesTest(): void {
  // —— 表结构 ——
  describe('VoiceLanguages — 表结构', () => {
    it('VOICE_LANGUAGES 非空且首项为自动检测（code=""）', 0, () => {
      expect(VOICE_LANGUAGES.length > 0).assertTrue();
      expect(VOICE_LANGUAGES[0].code).assertEqual(VOICE_LANG_AUTO);
      expect(VOICE_LANGUAGES[0].code).assertEqual('');
    });
    it('elevenLabsCode 项除自动检测外均非空', 0, () => {
      for (let i = 1; i < VOICE_LANGUAGES.length; i++) {
        expect(VOICE_LANGUAGES[i].elevenLabsCode !== '').assertTrue();
      }
    });
  });

  // —— findLanguageByCode ——
  describe('VoiceLanguages — findLanguageByCode', () => {
    it('zh-CN 命中', 0, () => {
      const l: VoiceLanguage | null = findLanguageByCode('zh-CN');
      expect(l !== null).assertTrue();
      expect((l as VoiceLanguage).elevenLabsCode).assertEqual('zh');
    });
    it('"" 命中自动检测项', 0, () => {
      const l: VoiceLanguage | null = findLanguageByCode('');
      expect(l !== null).assertTrue();
      expect((l as VoiceLanguage).elevenLabsCode).assertEqual('');
    });
    it('未知 locale → null', 0, () => {
      expect(findLanguageByCode('he-IL')).assertNull();   // 未入表（不支持 ElevenLabs）
      expect(findLanguageByCode('xx-XX')).assertNull();
    });
  });

  // —— getElevenLabsCodeFromPreference ——
  describe('VoiceLanguages — getElevenLabsCodeFromPreference', () => {
    it('zh-CN → zh；en-US → en；ja-JP → ja；pt-BR → pt-br', 0, () => {
      expect(getElevenLabsCodeFromPreference('zh-CN')).assertEqual('zh');
      expect(getElevenLabsCodeFromPreference('en-US')).assertEqual('en');
      expect(getElevenLabsCodeFromPreference('ja-JP')).assertEqual('ja');
      expect(getElevenLabsCodeFromPreference('pt-BR')).assertEqual('pt-br');
    });
    it('""（自动检测）→ ""（不设 language 覆盖）', 0, () => {
      expect(getElevenLabsCodeFromPreference('')).assertEqual('');
    });
    it('不支持/未命中 locale → ""', 0, () => {
      expect(getElevenLabsCodeFromPreference('he-IL')).assertEqual('');
      expect(getElevenLabsCodeFromPreference('foobar')).assertEqual('');
    });
  });

  // —— getLanguageDisplayName ——
  describe('VoiceLanguages — getLanguageDisplayName', () => {
    it('zh-CN → "Chinese (中文) - Simplified"（name≠native 带括号 + region）', 0, () => {
      const l: VoiceLanguage | null = findLanguageByCode('zh-CN');
      expect(getLanguageDisplayName(l as VoiceLanguage)).assertEqual('Chinese (中文) - Simplified');
    });
    it('en-US → "English - United States"（name=native 无括号 + region）', 0, () => {
      const l: VoiceLanguage | null = findLanguageByCode('en-US');
      expect(getLanguageDisplayName(l as VoiceLanguage)).assertEqual('English - United States');
    });
    it('ja-JP → "Japanese (日本語)"（无 region）', 0, () => {
      const l: VoiceLanguage | null = findLanguageByCode('ja-JP');
      expect(getLanguageDisplayName(l as VoiceLanguage)).assertEqual('Japanese (日本語)');
    });
    it('自动检测 → "Auto-detect"', 0, () => {
      const l: VoiceLanguage | null = findLanguageByCode('');
      expect(getLanguageDisplayName(l as VoiceLanguage)).assertEqual('Auto-detect');
    });
  });
}
