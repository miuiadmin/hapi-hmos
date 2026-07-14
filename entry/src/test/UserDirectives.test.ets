// UserDirectives 单测 —— 用户气泡前导指令（/slash、$skill）抽取纯逻辑（零 @kit，LocalUnit 可加载）。
//   对照 web/src/components/AssistantChat/messages/user-bubble.tsx:13-41
//   （LEADING_DIRECTIVE_REGEX / extractLeadingDirectives / formatDirectiveLabel）。
//   覆盖：无指令；单指令+body；纯指令；多指令；lookahead 失败；$// 无字母数字退化；前导空白。

import { describe, it, expect } from '@ohos/hypium';
import { extractLeadingDirectives, formatDirectiveLabel } from '../main/ets/chat/UserDirectives';

export default function userDirectivesTest(): void {
  describe('UserDirectives — extractLeadingDirectives', () => {
    it('普通文本无指令 → directives 空、body 原样（已 trimStart）', 0, () => {
      const r = extractLeadingDirectives('hello world');
      expect(r.directives.length).assertEqual(0);
      expect(r.body).assertEqual('hello world');
    });
    it('单指令 + 正文', 0, () => {
      const r = extractLeadingDirectives('/clear all the things');
      expect(r.directives.length).assertEqual(1);
      expect(r.directives[0]).assertEqual('/clear');
      expect(r.body).assertEqual('all the things');
    });
    it('$skill + 正文', 0, () => {
      const r = extractLeadingDirectives('$skills do the thing');
      expect(r.directives.length).assertEqual(1);
      expect(r.directives[0]).assertEqual('$skills');
      expect(r.body).assertEqual('do the thing');
    });
    it('纯指令无正文（串尾）→ body 空', 0, () => {
      const r = extractLeadingDirectives('/clear');
      expect(r.directives.length).assertEqual(1);
      expect(r.directives[0]).assertEqual('/clear');
      expect(r.body).assertEqual('');
    });
    it('纯指令无正文但尾随空白 → body 空（trimStart 吃掉）', 0, () => {
      const r = extractLeadingDirectives('/clear   ');
      expect(r.directives.length).assertEqual(1);
      expect(r.directives[0]).assertEqual('/clear');
      expect(r.body).assertEqual('');
    });
    it('多指令连续（$ 与 / 混杂）+ 正文', 0, () => {
      const r = extractLeadingDirectives('$skills /clear  ship it');
      expect(r.directives.length).assertEqual(2);
      expect(r.directives[0]).assertEqual('$skills');
      expect(r.directives[1]).assertEqual('/clear');
      expect(r.body).assertEqual('ship it');
    });
    it('多指令无正文', 0, () => {
      const r = extractLeadingDirectives('$a /b');
      expect(r.directives.length).assertEqual(2);
      expect(r.directives[0]).assertEqual('$a');
      expect(r.directives[1]).assertEqual('/b');
      expect(r.body).assertEqual('');
    });
    it('lookahead 失败（指令后紧跟非空白字符）→ 整体退化，原样 body', 0, () => {
      // $foo(bar)：$foo 后是 '(' 非 [\w-] 也非空白 → lookahead 失败 → 不收，body 原样
      const r = extractLeadingDirectives('$foo(bar)');
      expect(r.directives.length).assertEqual(0);
      expect(r.body).assertEqual('$foo(bar)');
    });
    it('lookahead 失败（/path-style）→ 退化', 0, () => {
      // /usr/bin：/usr 后是 '/' 非 \w- 也非空白 → 失败
      const r = extractLeadingDirectives('/usr/bin');
      expect(r.directives.length).assertEqual(0);
      expect(r.body).assertEqual('/usr/bin');
    });
    it('$ 或 / 后无字母数字 → 不构成指令', 0, () => {
      let r = extractLeadingDirectives('$ foo');
      expect(r.directives.length).assertEqual(0);
      expect(r.body).assertEqual('$ foo');
      r = extractLeadingDirectives('/ 123');
      expect(r.directives.length).assertEqual(0);
      expect(r.body).assertEqual('/ 123');
    });
    it('指令含连字符/下划线 → 计入（[\\w-]*）', 0, () => {
      const r = extractLeadingDirectives('/ship-it now');
      expect(r.directives.length).assertEqual(1);
      expect(r.directives[0]).assertEqual('/ship-it');
      expect(r.body).assertEqual('now');
    });
    it('前导空白被跳过', 0, () => {
      const r = extractLeadingDirectives('  \t\n/clear ok');
      expect(r.directives.length).assertEqual(1);
      expect(r.directives[0]).assertEqual('/clear');
      expect(r.body).assertEqual('ok');
    });
    it('空串 → directives 空、body 空', 0, () => {
      const r = extractLeadingDirectives('');
      expect(r.directives.length).assertEqual(0);
      expect(r.body).assertEqual('');
    });
  });

  describe('UserDirectives — formatDirectiveLabel', () => {
    it('/clear → clear', 0, () => {
      expect(formatDirectiveLabel('/clear')).assertEqual('clear');
    });
    it('$skills → skills', 0, () => {
      expect(formatDirectiveLabel('$skills')).assertEqual('skills');
    });
    it('/ship-it → ship it（连字符折叠为空格）', 0, () => {
      expect(formatDirectiveLabel('/ship-it')).assertEqual('ship it');
    });
    it('$a_b-c → a b c（_ 与 - 混合折叠）', 0, () => {
      expect(formatDirectiveLabel('$a_b-c')).assertEqual('a b c');
    });
    it('前导分隔符被折叠后 trim 掉（-foo- → foo）', 0, () => {
      expect(formatDirectiveLabel('/--foo--')).assertEqual('foo');
    });
    it('全分隔符 → trim 后空串', 0, () => {
      expect(formatDirectiveLabel('/---')).assertEqual('');
    });
    it('无前缀的纯文本原样（去分隔符折叠+trim）', 0, () => {
      expect(formatDirectiveLabel('clear')).assertEqual('clear');
    });
    it('空串 → 空串', 0, () => {
      expect(formatDirectiveLabel('')).assertEqual('');
    });
  });
}
