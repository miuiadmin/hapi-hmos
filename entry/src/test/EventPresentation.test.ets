// EventPresentation 单测 —— 对照 web/src/chat/presentation.ts getEventPresentation。
//   覆盖当前产出的 type：api-error（四态）/ microcompact（saved 阈值）/ compact / limit-warning /
//   limit-reached（带/不带 endsAt、limitType 标签）/ 通用 JSON 回退。
//   文案随 i18n locale——显式 setTranslateLocale('zh-CN') 钉死，断言中文。endsAt>0 的时间段依赖运行
//   时区/日期，只断前缀 + 尾缀（'重置'/起点），不断精确时间；endsAt=0 走精确断言（对照 MessageMetadata.test 范式）。

import { describe, it, expect } from '@ohos/hypium';
import { getEventPresentation } from '../main/ets/chat/EventPresentation';
import { AgentEvent } from '../main/ets/models/Types';
import { setTranslateLocale } from '../main/ets/i18n/Translate';

function ev(type: string): AgentEvent {
  const e: AgentEvent = new AgentEvent();
  e.type = type;
  return e;
}

export default function eventPresentationTest(): void {
  setTranslateLocale('zh-CN');

  describe('getEventPresentation — api-error 四态', () => {
    it('maxRetries>0 且 retry>=max → 已达最大重试 + ⚠️', 0, () => {
      const e: AgentEvent = ev('api-error'); e.retryAttempt = 3; e.maxRetries = 3;
      const p = getEventPresentation(e);
      expect(p.icon).assertEqual('⚠️');
      expect(p.text).assertEqual('API 错误：已达最大重试次数');
    });
    it('maxRetries>0 且 retry<max → 重试中（n/m）+ ⏳', 0, () => {
      const e: AgentEvent = ev('api-error'); e.retryAttempt = 1; e.maxRetries = 3;
      const p = getEventPresentation(e);
      expect(p.icon).assertEqual('⏳');
      expect(p.text).assertEqual('API 错误：重试中（1/3）');
    });
    it('maxRetries=0 且 retry>0 → 重试中… + ⏳', 0, () => {
      const e: AgentEvent = ev('api-error'); e.retryAttempt = 2; e.maxRetries = 0;
      const p = getEventPresentation(e);
      expect(p.icon).assertEqual('⏳');
      expect(p.text).assertEqual('API 错误：重试中…');
    });
    it('maxRetries=0 且 retry=0 → API 错误 + ⚠️', 0, () => {
      const e: AgentEvent = ev('api-error');
      const p = getEventPresentation(e);
      expect(p.icon).assertEqual('⚠️');
      expect(p.text).assertEqual('API 错误');
    });
  });

  describe('getEventPresentation — microcompact saved 阈值', () => {
    it('tokensSaved>=1000 → NK（12000→12K）', 0, () => {
      const e: AgentEvent = ev('microcompact'); e.tokensSaved = 12000;
      const p = getEventPresentation(e);
      expect(p.icon).assertEqual('📦');
      expect(p.text).assertEqual('上下文已压缩（节省 12K tokens）');
    });
    it('tokensSaved<1000 → 原值（500→500）', 0, () => {
      const e: AgentEvent = ev('microcompact'); e.tokensSaved = 500;
      expect(getEventPresentation(e).text).assertEqual('上下文已压缩（节省 500 tokens）');
    });
    it('tokensSaved=1500 → Math.round(1.5)=2K', 0, () => {
      const e: AgentEvent = ev('microcompact'); e.tokensSaved = 1500;
      expect(getEventPresentation(e).text).assertEqual('上下文已压缩（节省 2K tokens）');
    });
  });

  describe('getEventPresentation — compact', () => {
    it('compact → 对话已压缩 + 📦', 0, () => {
      const e: AgentEvent = ev('compact');
      const p = getEventPresentation(e);
      expect(p.icon).assertEqual('📦');
      expect(p.text).assertEqual('对话已压缩');
    });
  });

  describe('getEventPresentation — limit-warning', () => {
    it('endsAt=0 + five_hour → 精确「用量达限额 90% (5-hour)」', 0, () => {
      const e: AgentEvent = ev('limit-warning'); e.utilization = 0.9; e.limitType = 'five_hour';
      const p = getEventPresentation(e);
      expect(p.icon).assertEqual('⚠️');
      expect(p.text).assertEqual('用量达限额 90% (5-hour)');
    });
    it('endsAt=0 + 空 limitType → 无括号后缀', 0, () => {
      const e: AgentEvent = ev('limit-warning'); e.utilization = 0.9;
      expect(getEventPresentation(e).text).assertEqual('用量达限额 90%');
    });
    it('utilization=0.855 → Math.round→86%；未知 limitType 下划线→空格', 0, () => {
      const e: AgentEvent = ev('limit-warning'); e.utilization = 0.855; e.limitType = 'thirty_day';
      expect(getEventPresentation(e).text).assertEqual('用量达限额 86% (thirty day)');
    });
    it('endsAt>0 → 前缀 + 尾缀「重置」（时间随区不断精确）', 0, () => {
      const e: AgentEvent = ev('limit-warning'); e.utilization = 0.9; e.endsAt = 1700000000000; e.limitType = 'five_hour';
      const txt: string = getEventPresentation(e).text;
      expect(txt.indexOf('用量达限额 90% (5-hour) · ')).assertEqual(0);
      expect(txt.indexOf('重置') >= 0).assertTrue();
    });
  });

  describe('getEventPresentation — limit-reached', () => {
    it('endsAt=0 + seven_day → 精确「已达用量限额 (7-day)」', 0, () => {
      const e: AgentEvent = ev('limit-reached'); e.limitType = 'seven_day';
      const p = getEventPresentation(e);
      expect(p.icon).assertEqual('⏳');
      expect(p.text).assertEqual('已达用量限额 (7-day)');
    });
    it('endsAt>0 → 前缀「…，至 」（时间随区不断精确）', 0, () => {
      const e: AgentEvent = ev('limit-reached'); e.endsAt = 1700000000000; e.limitType = 'seven_day';
      const txt: string = getEventPresentation(e).text;
      expect(txt.indexOf('已达用量限额 (7-day)，至 ')).assertEqual(0);
    });
  });

  describe('getEventPresentation — message（summary 灰条文本）', () => {
    it('type message + 非空 message → 原文 + 无图标', 0, () => {
      const e: AgentEvent = ev('message'); e.message = '对话已压缩摘要';
      const p = getEventPresentation(e);
      expect(p.icon).assertEqual('');
      expect(p.text).assertEqual('对话已压缩摘要');
    });
    it('type message + 空 message → 字面 Message 回退', 0, () => {
      const e: AgentEvent = ev('message');
      const p = getEventPresentation(e);
      expect(p.icon).assertEqual('');
      expect(p.text).assertEqual('Message');
    });
  });

  describe('getEventPresentation — 通用回退', () => {
    it('未知 type → JSON 串含 type + 无图标', 0, () => {
      const e: AgentEvent = ev('switch');
      const p = getEventPresentation(e);
      expect(p.icon).assertEqual('');
      expect(p.text.indexOf('"type":"switch"') >= 0).assertTrue();
    });
  });
}
