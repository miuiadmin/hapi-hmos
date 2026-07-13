// Translate 纯逻辑单测 —— i18n 翻译层（无 @kit / 无 ArkUI，LocalUnit 可直 import）。
// 覆盖：interpolate（{name} 插值 + 未命中保留 + number）、translate（locale 查表 + 中文兜底 + key 回落）、
//       t + setTranslateLocale/getTranslateLocale（模块级 locale）。
//
// 自清理：t() 依赖模块级 _locale（跨套件共享）。本套件首行复位 zh-CN，末尾 it 再复位 zh-CN，
//         保证不污染依赖默认中文的 Outline / Message 等套件（hypium 不会因前序 it 失败而跳过后续 it）。

import { describe, it, expect } from '@ohos/hypium';
import { interpolate, translate, t, setTranslateLocale, getTranslateLocale } from '../main/ets/i18n/Translate';

export default function translateTest(): void {
  setTranslateLocale('zh-CN');   // 套件起始复位默认 locale

  describe('interpolate', () => {
    it('returns input unchanged when params undefined', 0, () => {
      expect(interpolate('hello {name}')).assertEqual('hello {name}');
    });
    it('substitutes a single named placeholder', 0, () => {
      expect(interpolate('hello {name}', { name: 'world' })).assertEqual('hello world');
    });
    it('substitutes multiple placeholders', 0, () => {
      expect(interpolate('{a}+{b}={c}', { a: '1', b: '2', c: '3' })).assertEqual('1+2=3');
    });
    it('coerces number params to string', 0, () => {
      expect(interpolate('{n} 项', { n: 5 })).assertEqual('5 项');
    });
    it('leaves unmatched {name} as-is', 0, () => {
      expect(interpolate('{a}/{b}', { a: 'x' })).assertEqual('x/{b}');
    });
    it('is a no-op when there are no placeholders', 0, () => {
      expect(interpolate('plain text', { x: 'y' })).assertEqual('plain text');
    });
    it('handles adjacent placeholders', 0, () => {
      expect(interpolate('{a}{b}', { a: 'A', b: 'B' })).assertEqual('AB');
    });
  });

  describe('translate', () => {
    it('returns the zh-CN value for a known key (locale zh-CN)', 0, () => {
      expect(translate('zh-CN', 'common.cancel')).assertEqual('取消');
    });
    it('returns the en value for a known key (locale en)', 0, () => {
      expect(translate('en', 'common.cancel')).assertEqual('Cancel');
    });
    it('interpolates params into the resolved value', 0, () => {
      expect(translate('zh-CN', 'sessions.time.minutesAgo', { n: 3 })).assertEqual('3分钟前');
      expect(translate('en', 'sessions.time.minutesAgo', { n: 3 })).assertEqual('3m ago');
    });
    // 注：zh-CN/en 两表 key 全对齐，无法用真实 key 触发 en→zhCN 分支；
    //     未知 key 走最终 key 回落分支（结构与中文兜底分支同款）。
    it('falls back to the key itself when key is unknown', 0, () => {
      expect(translate('zh-CN', '__totally_unknown_key__')).assertEqual('__totally_unknown_key__');
      expect(translate('en', '__totally_unknown_key__')).assertEqual('__totally_unknown_key__');
    });
    it('interpolates even when falling back to the key', 0, () => {
      expect(translate('zh-CN', 'missing.{n}', { n: 9 })).assertEqual('missing.9');
    });
  });

  describe('setTranslateLocale / getTranslateLocale', () => {
    it('getTranslateLocale reflects setTranslateLocale', 0, () => {
      setTranslateLocale('en');
      expect(getTranslateLocale()).assertEqual('en');
      setTranslateLocale('zh-CN');
      expect(getTranslateLocale()).assertEqual('zh-CN');
    });
  });

  describe('t (module-level locale)', () => {
    it('returns Chinese when locale is zh-CN', 0, () => {
      setTranslateLocale('zh-CN');
      expect(t('common.confirm')).assertEqual('确定');
      expect(t('chat.send')).assertEqual('发送');
    });
    it('returns English when locale is en', 0, () => {
      setTranslateLocale('en');
      expect(t('common.confirm')).assertEqual('OK');
      expect(t('chat.send')).assertEqual('Send');
    });
    it('interpolates params', 0, () => {
      setTranslateLocale('zh-CN');
      expect(t('chat.newMessages', { n: 7 })).assertEqual('7 条新消息');
      setTranslateLocale('en');
      expect(t('chat.newMessages', { n: 7 })).assertEqual('7 new messages');
    });
    it('falls back to the key when unknown', 0, () => {
      setTranslateLocale('zh-CN');
      expect(t('no.such.key')).assertEqual('no.such.key');
    });

    // 末尾复位默认 locale，避免污染后续依赖默认中文的套件（Outline/Message/…）
    it('restores default locale (cleanup)', 0, () => {
      setTranslateLocale('zh-CN');
      expect(getTranslateLocale()).assertEqual('zh-CN');
    });
  });
}
