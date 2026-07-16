// ToastLocalize 纯逻辑单测 —— 对照 web/src/App.tsx:245-297 translateIncomingToast
// 零 @kit：仅 import 被测纯层（chat/ToastLocalize）+ Translate（setTranslateLocale 控制 t() 查表）。
//   覆盖：classifyToastTitle 5 分支、parseReadyBody 命中/未命中/trim、localizeToast 各类（locale=en 断言英文）。

import { describe, it, expect } from '@ohos/hypium';
import { setTranslateLocale } from '../main/ets/i18n/Translate';
import { classifyToastTitle, parseReadyBody, localizeToast } from '../main/ets/chat/ToastLocalize';

export default function toastLocalizeTest(): void {
  describe('classifyToastTitle', () => {
    it('4 个上游字面量精确匹配', 0, () => {
      expect(classifyToastTitle('Ready for input')).assertEqual('ready');
      expect(classifyToastTitle('Permission Request')).assertEqual('permission');
      expect(classifyToastTitle('Task completed')).assertEqual('taskCompleted');
      expect(classifyToastTitle('Task failed')).assertEqual('taskFailed');
    });
    it('trim 容差（前后空白）', 0, () => {
      expect(classifyToastTitle('  Ready for input  ')).assertEqual('ready');
      expect(classifyToastTitle('\tTask completed\n')).assertEqual('taskCompleted');
    });
    it('未知/空/大小写不符 → unknown（大小写敏感，上游同款）', 0, () => {
      expect(classifyToastTitle('Hello')).assertEqual('unknown');
      expect(classifyToastTitle('')).assertEqual('unknown');
      expect(classifyToastTitle('ready for input')).assertEqual('unknown');
    });
  });

  describe('parseReadyBody', () => {
    it('命中 → {agent, session}（取原大小写）', 0, () => {
      const r = parseReadyBody('Claude is waiting in my-session');
      expect(r).assertNotNull();
      if (r !== null) {
        expect(r.agent).assertEqual('Claude');
        expect(r.session).assertEqual('my-session');
      }
    });
    it('大小写不敏感匹配分隔符（上游 /i）', 0, () => {
      const r = parseReadyBody('X IS WAITING IN Y');
      expect(r).assertNotNull();
      if (r !== null) {
        expect(r.agent).assertEqual('X');
        expect(r.session).assertEqual('Y');
      }
    });
    it('trim 容差', 0, () => {
      const r = parseReadyBody('  A is waiting in B  ');
      expect(r).assertNotNull();
      if (r !== null) {
        expect(r.agent).assertEqual('A');
        expect(r.session).assertEqual('B');
      }
    });
    it('未命中 → null', 0, () => {
      expect(parseReadyBody('just some text')).assertNull();
      expect(parseReadyBody('')).assertNull();
      expect(parseReadyBody('is waiting in X')).assertNull(); // 开头即分隔 → agent 空
    });
  });

  describe('localizeToast', () => {
    // 固定 locale=en，断言英文输出（与 locales/en.ets 表一致）
    it('ready + 命中 → 插值 {agent}/{session}', 0, () => {
      setTranslateLocale('en');
      const out = localizeToast('Ready for input', 'Claude is waiting in demo');
      expect(out.title).assertEqual('Ready for input');
      expect(out.body).assertEqual('Claude is waiting in demo');
    });
    it('ready + 未命中 → title 本地化、body 原 trim', 0, () => {
      setTranslateLocale('en');
      const out = localizeToast('Ready for input', '  plain body  ');
      expect(out.title).assertEqual('Ready for input');
      expect(out.body).assertEqual('plain body');
    });
    it('permission → 本地化 title + trim body', 0, () => {
      setTranslateLocale('en');
      const out = localizeToast('Permission Request', ' allow bash ');
      expect(out.title).assertEqual('Permission Request');
      expect(out.body).assertEqual('allow bash');
    });
    it('taskCompleted → 本地化 title + trim body', 0, () => {
      setTranslateLocale('en');
      const out = localizeToast('Task completed', ' done ');
      expect(out.title).assertEqual('Task completed');
      expect(out.body).assertEqual('done');
    });
    it('taskFailed → 本地化 title + trim body', 0, () => {
      setTranslateLocale('en');
      const out = localizeToast('Task failed', ' err ');
      expect(out.title).assertEqual('Task failed');
      expect(out.body).assertEqual('err');
    });
    it('unknown → 原 title/body（不 trim，上游 fallback）', 0, () => {
      setTranslateLocale('en');
      const out = localizeToast('  Hello  ', '  world  ');
      expect(out.title).assertEqual('  Hello  ');
      expect(out.body).assertEqual('  world  ');
    });
  });
}
