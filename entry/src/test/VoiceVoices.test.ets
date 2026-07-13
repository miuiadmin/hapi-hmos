// VoiceVoices 单测 —— 预置声音表 + 显示名（纯层，无 @kit，LocalUnit 可加载）。
//   对照 VoiceLanguages.test 范式：同步断言，覆盖表结构 + 查找 + 本地化显示名。

import { describe, it, expect } from '@ohos/hypium';
import {
  VOICE_PRESETS,
  DEFAULT_VOICE_ID,
  getPresetById,
  getPresetDisplayName,
  VoicePreset
} from '../main/ets/chat/VoiceVoices';

export default function voiceVoicesTest(): void {
  // —— 表结构 ——
  describe('VoiceVoices — 表结构', () => {
    it('DEFAULT_VOICE_ID = cgSgspJ2msm6clMCkdW9', 0, () => {
      expect(DEFAULT_VOICE_ID).assertEqual('cgSgspJ2msm6clMCkdW9');
    });
    it('VOICE_PRESETS 共 10 项，首项 Jessica（默认声）', 0, () => {
      expect(VOICE_PRESETS.length).assertEqual(10);
      expect(VOICE_PRESETS[0].id).assertEqual(DEFAULT_VOICE_ID);
      expect(VOICE_PRESETS[0].name).assertEqual('Jessica');
      expect(VOICE_PRESETS[0].zhName).assertEqual('杰西卡');
    });
    it('所有预设 id 非空且唯一', 0, () => {
      const seen: string[] = [];
      for (let i = 0; i < VOICE_PRESETS.length; i++) {
        const id: string = VOICE_PRESETS[i].id;
        expect(id !== '').assertTrue();
        expect(seen.indexOf(id)).assertEqual(-1);   // 未出现过
        seen.push(id);
      }
    });
  });

  // —— getPresetById ——
  describe('VoiceVoices — getPresetById', () => {
    it('默认 id 命中 Jessica', 0, () => {
      const v: VoicePreset | null = getPresetById(DEFAULT_VOICE_ID);
      expect(v !== null).assertTrue();
      expect((v as VoicePreset).name).assertEqual('Jessica');
    });
    it('未知 id → null', 0, () => {
      expect(getPresetById('nonExistentVoiceId123')).assertNull();
    });
  });

  // —— getPresetDisplayName ——
  describe('VoiceVoices — getPresetDisplayName', () => {
    it('默认 id + zh-CN → 杰西卡（取中文名）', 0, () => {
      expect(getPresetDisplayName(DEFAULT_VOICE_ID, 'zh-CN')).assertEqual('杰西卡');
    });
    it('默认 id + 非 zh-CN → Jessica（英文名）', 0, () => {
      expect(getPresetDisplayName(DEFAULT_VOICE_ID, 'en')).assertEqual('Jessica');
    });
    it('无中文名的预设（Domi）+ zh-CN → 回落英文名 Domi', 0, () => {
      // AZnzlk1XvdvUeBnXmlld = Domi（zhName=''）
      expect(getPresetDisplayName('AZnzlk1XvdvUeBnXmlld', 'zh-CN')).assertEqual('Domi');
    });
    it('未知 id → 回落 id 本身（克隆声无本地化名）', 0, () => {
      expect(getPresetDisplayName('clonedVoiceXyz', 'zh-CN')).assertEqual('clonedVoiceXyz');
    });
  });
}
