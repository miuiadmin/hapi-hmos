// ChatSurfaceColors 单测 —— 聊天气泡自定义配色纯算法层（无 @kit，LocalUnit 可加载）。
//   对照 CodeHighlight.test / TerminalToolDisplay.test 范式：同步断言。
//   覆盖 mixHex（逐字移植上游 round(base+(accent-base)*ratio)，钉算法值）+
//   resolveSurfaceColor（pref×isDark×base×ratio 矩阵）+ normalizeHexColor/isHexColor +
//   getAccentColor/getPickerValue + toPreset/Custom/parseChatSurfaceColorPreference。

import { describe, it, expect } from '@ohos/hypium';
import {
  mixHex,
  rgbToHex,
  isHexColor,
  normalizeHexColor,
  getAccentColor,
  resolveSurfaceColor,
  getPickerValue,
  toPresetPreference,
  toCustomPreference,
  parseChatSurfaceColorPreference,
  DEFAULT_CHAT_SURFACE_COLOR_PREFERENCE,
  DEFAULT_PICKER_COLOR
} from '../main/ets/chat/ChatSurfaceColors';

export default function chatSurfaceColorsTest(): void {
  // —— rgbToHex / clamp ——
  describe('ChatSurfaceColors — rgbToHex + clamp', () => {
    it('基本三原色', 0, () => {
      expect(rgbToHex(0, 0, 0)).assertEqual('#000000');
      expect(rgbToHex(255, 255, 255)).assertEqual('#ffffff');
    });
    it('单位数补 0', 0, () => {
      expect(rgbToHex(10, 11, 12)).assertEqual('#0a0b0c');
    });
    it('越界 clamp 到 [0,255]', 0, () => {
      expect(rgbToHex(300, -5, 128)).assertEqual('#ff0080');
    });
  });

  // —— mixHex：钉算法（逐字移植上游 round(base+(accent-base)*ratio)）——
  //   关键：plan 旧值 #d0daf9 为笔误，正确为 #cfe2f9（逐通道复核见注释）。
  describe('ChatSurfaceColors — mixHex 钉算法', () => {
    it('soft-blue light ratio=0.30 → #cfe2f9', 0, () => {
      // base(242,244,246) accent(125,183,255) ratio 0.30
      //   r=round(242+(125-242)*0.30)=round(206.9)=207=0xCF
      //   g=round(244+(183-244)*0.30)=round(225.7)=226=0xE2
      //   b=round(246+(255-246)*0.30)=round(248.7)=249=0xF9
      expect(mixHex('#f2f4f6', '#7db7ff', 0.30)).assertEqual('#cfe2f9');
    });
    it('soft-green light ratio=0.30 → #d4eadc', 0, () => {
      // r=round(242+(143-242)*0.30)=212=0xD4 g=round(244+(209-244)*0.30)=234=0xEA b=round(246+(158-246)*0.30)=220=0xDC
      expect(mixHex('#f2f4f6', '#8fd19e', 0.30)).assertEqual('#d4eadc');
    });
    it('soft-yellow light ratio=0.30 → #f1ebd1', 0, () => {
      // r=round(242+(240-242)*0.30)=241=0xF1 g=round(244+(215-244)*0.30)=235=0xEB b=round(246+(122-246)*0.30)=209=0xD1
      expect(mixHex('#f2f4f6', '#f0d77a', 0.30)).assertEqual('#f1ebd1');
    });
    it('dark base ratio=0.20 → 中性面混 soft-blue', 0, () => {
      // base(43,47,52) accent #7db7ff(125,183,255) ratio 0.20
      //   r=round(43+(125-43)*0.20)=59=0x3B g=round(47+(183-47)*0.20)=74=0x4A b=round(52+(255-52)*0.20)=93=0x5D
      expect(mixHex('#2b2f34', '#7db7ff', 0.20)).assertEqual('#3b4a5d');
    });
    it('ratio=0 → 等于 base', 0, () => {
      expect(mixHex('#112233', '#aabbcc', 0)).assertEqual('#112233');
    });
    it('ratio=1 → 等于 accent', 0, () => {
      expect(mixHex('#112233', '#aabbcc', 1)).assertEqual('#aabbcc');
    });
  });

  // —— hex 校验 / 归一化 ——
  describe('ChatSurfaceColors — isHexColor / normalizeHexColor', () => {
    it('isHexColor 合法 #rrggbb', 0, () => {
      expect(isHexColor('#88cc44')).assertTrue();
    });
    it('isHexColor 非法（缺#/位数错/非 hex）', 0, () => {
      expect(isHexColor('88cc44')).assertFalse();
      expect(isHexColor('#88cc4')).assertFalse();
      expect(isHexColor('#88cc4g')).assertFalse();
    });
    it('normalizeHexColor 小写归一 + trim', 0, () => {
      expect(normalizeHexColor('#88CC44')).assertEqual('#88cc44');
      expect(normalizeHexColor(' #88cc44 ')).assertEqual('#88cc44');
    });
    it('normalizeHexColor 非法 → null', 0, () => {
      expect(normalizeHexColor('88cc44') === null).assertTrue();
      expect(normalizeHexColor('#88cc4') === null).assertTrue();
    });
  });

  // —— resolveSurfaceColor：pref × isDark × base 矩阵 ——
  describe('ChatSurfaceColors — resolveSurfaceColor 矩阵', () => {
    it('default → null（表用 palette 默认）', 0, () => {
      expect(resolveSurfaceColor('default', false, '#f2f4f6') === null).assertTrue();
      expect(resolveSurfaceColor('default', true, '#2b2f34') === null).assertTrue();
    });
    it('preset soft-blue light（ratio 0.30）', 0, () => {
      expect(resolveSurfaceColor('preset:soft-blue', false, '#f2f4f6')).assertEqual('#cfe2f9');
    });
    it('preset soft-blue dark（ratio 0.20）', 0, () => {
      expect(resolveSurfaceColor('preset:soft-blue', true, '#2b2f34')).assertEqual('#3b4a5d');
    });
    it('custom light（ratio 0.34）', 0, () => {
      // accent #88cc44(136,204,68) base(242,244,246) ratio 0.34
      //   r=round(242+(136-242)*0.34)=206=0xCE g=round(244+(204-244)*0.34)=230=0xE6 b=round(246+(68-246)*0.34)=185=0xB9
      expect(resolveSurfaceColor('custom:#88cc44', false, '#f2f4f6')).assertEqual('#cee6b9');
    });
    it('custom dark（ratio 0.22）', 0, () => {
      // accent #88cc44(136,204,68) base(43,47,52) ratio 0.22
      //   r=round(43+(136-43)*0.22)=63=0x3F g=round(47+(204-47)*0.22)=82=0x52 b=round(52+(68-52)*0.22)=56=0x38
      expect(resolveSurfaceColor('custom:#88cc44', true, '#2b2f34')).assertEqual('#3f5238');
    });
    it('custom 非法 hex → null', 0, () => {
      expect(resolveSurfaceColor('custom:bad', false, '#f2f4f6') === null).assertTrue();
    });
    it('preset 未知 → null', 0, () => {
      expect(resolveSurfaceColor('preset:unknown', false, '#f2f4f6') === null).assertTrue();
    });
  });

  // —— getAccentColor / getPickerValue ——
  describe('ChatSurfaceColors — getAccentColor / getPickerValue', () => {
    it('getAccentColor 各 pref', 0, () => {
      expect(getAccentColor('default') === null).assertTrue();
      expect(getAccentColor('preset:soft-blue')).assertEqual('#7db7ff');
      expect(getAccentColor('preset:soft-green')).assertEqual('#8fd19e');
      expect(getAccentColor('preset:soft-yellow')).assertEqual('#f0d77a');
      expect(getAccentColor('preset:unknown') === null).assertTrue();
      expect(getAccentColor('custom:#88cc44')).assertEqual('#88cc44');
      expect(getAccentColor('custom:bad') === null).assertTrue();
    });
    it('getPickerValue：default→中性灰；preset/custom→强调色', 0, () => {
      expect(getPickerValue('default')).assertEqual(DEFAULT_PICKER_COLOR);
      expect(getPickerValue('preset:soft-blue')).assertEqual('#7db7ff');
      expect(getPickerValue('custom:#88cc44')).assertEqual('#88cc44');
    });
  });

  // —— 偏好串构造 / 解析 ——
  describe('ChatSurfaceColors — toPreset / toCustom / parse', () => {
    it('toPresetPreference', 0, () => {
      expect(toPresetPreference('default')).assertEqual('default');
      expect(toPresetPreference('soft-blue')).assertEqual('preset:soft-blue');
      expect(toPresetPreference('soft-green')).assertEqual('preset:soft-green');
    });
    it('toCustomPreference 合法归一；非法回落 DEFAULT_PICKER_COLOR', 0, () => {
      expect(toCustomPreference('#88cc44')).assertEqual('custom:#88cc44');
      expect(toCustomPreference('#88CC44')).assertEqual('custom:#88cc44');
      expect(toCustomPreference('invalid')).assertEqual('custom:' + DEFAULT_PICKER_COLOR);
    });
    it('parseChatSurfaceColorPreference 合法透传', 0, () => {
      expect(parseChatSurfaceColorPreference('default')).assertEqual('default');
      expect(parseChatSurfaceColorPreference('preset:soft-blue')).assertEqual('preset:soft-blue');
      expect(parseChatSurfaceColorPreference('preset:soft-green')).assertEqual('preset:soft-green');
      expect(parseChatSurfaceColorPreference('preset:soft-yellow')).assertEqual('preset:soft-yellow');
    });
    it('parseChatSurfaceColorPreference custom 归一', 0, () => {
      expect(parseChatSurfaceColorPreference('custom:#88cc44')).assertEqual('custom:#88cc44');
      expect(parseChatSurfaceColorPreference('custom:#88CC44')).assertEqual('custom:#88cc44');
    });
    it('parseChatSurfaceColorPreference 非法 → default', 0, () => {
      expect(parseChatSurfaceColorPreference('garbage')).assertEqual(DEFAULT_CHAT_SURFACE_COLOR_PREFERENCE);
      expect(parseChatSurfaceColorPreference('')).assertEqual(DEFAULT_CHAT_SURFACE_COLOR_PREFERENCE);
      expect(parseChatSurfaceColorPreference('preset:unknown')).assertEqual(DEFAULT_CHAT_SURFACE_COLOR_PREFERENCE);
      expect(parseChatSurfaceColorPreference('custom:bad')).assertEqual(DEFAULT_CHAT_SURFACE_COLOR_PREFERENCE);
    });
  });
}
