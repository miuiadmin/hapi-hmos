// LinkSchemes 单测 —— 非 HTTP scheme 自动链接列表纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 CodeHighlight.test 范式：同步断言。钉 SCHEMES 内容（含 agent 生态 scheme、不含 http/https/deny）。

import { describe, it, expect } from '@ohos/hypium';
import { NON_HTTPS_LINKIFY_SCHEMES, isLinkifyScheme } from '../main/ets/chat/LinkSchemes';

export default function linkSchemesTest(): void {
  describe('LinkSchemes — 列表非空且为 string[]', () => {
    it('SCHEMES 非空', 0, () => {
      expect(NON_HTTPS_LINKIFY_SCHEMES.length > 0).assertTrue();
    });
    it('每项为非空小写 ASCII 串', 0, () => {
      for (let i = 0; i < NON_HTTPS_LINKIFY_SCHEMES.length; i++) {
        const s: string = NON_HTTPS_LINKIFY_SCHEMES[i];
        expect(s.length > 0).assertTrue();
        // 小写 ASCII 字母/数字：无大写、无 scheme 分隔符 ':'
        for (let j = 0; j < s.length; j++) {
          const code: number = s.charCodeAt(j);
          const isLower: boolean = (code >= 97 && code <= 122) || (code >= 48 && code <= 57);
          expect(isLower).assertTrue();
        }
      }
    });
  });

  describe('LinkSchemes — 含上游 agent 生态 scheme', () => {
    it('含 gemini / cursor / opencode', 0, () => {
      expect(isLinkifyScheme('gemini')).assertTrue();
      expect(isLinkifyScheme('cursor')).assertTrue();
      expect(isLinkifyScheme('opencode')).assertTrue();
    });
    it('含 mailto 类常见协议（tel/ftp/ssh 等）', 0, () => {
      expect(isLinkifyScheme('tel')).assertTrue();
      expect(isLinkifyScheme('ftp')).assertTrue();
      expect(isLinkifyScheme('ssh')).assertTrue();
    });
  });

  describe('LinkSchemes — 不含 http/https（由 CJMarkdown 默认处理）', () => {
    it("不含 'http'", 0, () => {
      expect(isLinkifyScheme('http')).assertFalse();
    });
    it("不含 'https'", 0, () => {
      expect(isLinkifyScheme('https')).assertFalse();
    });
  });

  describe('LinkSchemes — 不含 deny 类危险 scheme', () => {
    it("不含 'javascript'", 0, () => {
      expect(isLinkifyScheme('javascript')).assertFalse();
    });
    it("不含 'data' / 'file' / 'vbscript'", 0, () => {
      expect(isLinkifyScheme('data')).assertFalse();
      expect(isLinkifyScheme('file')).assertFalse();
      expect(isLinkifyScheme('vbscript')).assertFalse();
    });
  });

  describe('LinkSchemes — isLinkifyScheme 边界', () => {
    it('未知 scheme → false', 0, () => {
      expect(isLinkifyScheme('foobar')).assertFalse();
    });
    it('空串 → false', 0, () => {
      expect(isLinkifyScheme('')).assertFalse();
    });
    it('大小写敏感（大写 GEMINI 不命中，CJMarkdown scheme 归一由库处理）', 0, () => {
      expect(isLinkifyScheme('GEMINI')).assertFalse();
    });
    it('去重：列表无重复项', 0, () => {
      const seen: string[] = [];
      for (let i = 0; i < NON_HTTPS_LINKIFY_SCHEMES.length; i++) {
        const s: string = NON_HTTPS_LINKIFY_SCHEMES[i];
        expect(seen.indexOf(s) < 0).assertTrue();
        seen.push(s);
      }
    });
  });
}
