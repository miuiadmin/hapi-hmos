// ExternalLink 纯逻辑单测 —— 对照 web markdown-text.tsx URI scheme policy（normalizedScheme/classifyScheme/hasScheme）。
// 重点覆盖安全绕过：双重编码（j%2561vascript→javascript）、控制符注入（java\nscript）、
//   相对路径误判（/path:x 无 scheme）、deny 黑名单。Preferences 相关（load/save）不在 LocalUnit 跑。

import { describe, it, expect } from '@ohos/hypium';
import {
  normalizedScheme,
  classifyScheme,
  hasScheme,
  extractScheme,
  isAllowedScheme
} from '../main/ets/utils/ExternalLink';

export default function externalLinkTest(): void {
  describe('normalizedScheme', () => {
    it('extracts plain scheme lowercased', 0, () => {
      expect(normalizedScheme('http://example.com')).assertEqual('http');
      expect(normalizedScheme('HTTPS://x')).assertEqual('https');
      expect(normalizedScheme('MAILTO:foo@bar.com')).assertEqual('mailto');
    });

    it('decodes single-round percent-encoding', 0, () => {
      // %6a%61... = "javascript"; 解码后命中 deny（见 classifyScheme 测试）
      expect(normalizedScheme('%6a%61%76%61%73%63%72%69%70%74:alert(1)')).assertEqual('javascript');
    });

    it('decodes double-encoded scheme (bypass defense)', 0, () => {
      // j%2561vascript → (round1) j%61vascript → (round2) javascript
      expect(normalizedScheme('j%2561vascript:alert(1)')).assertEqual('javascript');
    });

    it('strips ASCII control chars inside scheme', 0, () => {
      expect(normalizedScheme('java\nscript:x')).assertEqual('javascript');
      expect(normalizedScheme('java\tscript:x')).assertEqual('javascript');
      expect(normalizedScheme('java\rscript:x')).assertEqual('javascript');
    });

    it('strips DEL (0x7F) inside scheme', 0, () => {
      // 0x7F 夹在 scheme 中：java\x7Fscript → javascript
      const payload: string = 'java' + String.fromCharCode(0x7F) + 'script:x';
      expect(normalizedScheme(payload)).assertEqual('javascript');
    });

    it('returns null for relative/anchor (no scheme colon)', 0, () => {
      expect(normalizedScheme('/path/to/x')).assertEqual(null);
      expect(normalizedScheme('#anchor')).assertEqual(null);
      expect(normalizedScheme('?q=1')).assertEqual(null);
      expect(normalizedScheme('')).assertEqual(null);
    });

    it('returns null when colon is at position 0', 0, () => {
      expect(normalizedScheme(':foo')).assertEqual(null);
    });
  });

  describe('classifyScheme', () => {
    it('iana-safe schemes → iana', 0, () => {
      expect(classifyScheme('http://x')).assertEqual('iana');
      expect(classifyScheme('https://x')).assertEqual('iana');
      expect(classifyScheme('mailto:a@b.com')).assertEqual('iana');
      expect(classifyScheme('xmpp:user@srv')).assertEqual('iana');
      expect(classifyScheme('irc://net/%23chan')).assertEqual('iana');
    });

    it('deny schemes → deny (blocked)', 0, () => {
      expect(classifyScheme('javascript:alert(1)')).assertEqual('deny');
      expect(classifyScheme('data:text/html,<x>')).assertEqual('deny');
      expect(classifyScheme('vbscript:msgbox')).assertEqual('deny');
      expect(classifyScheme('file:///etc/passwd')).assertEqual('deny');
    });

    it('custom schemes → custom', 0, () => {
      expect(classifyScheme('intent:#Intent;end')).assertEqual('custom');
      expect(classifyScheme('market://details?id=x')).assertEqual('custom');
      expect(classifyScheme('tg://resolve?domain=x')).assertEqual('custom');
    });

    it('relative link → deny (no scheme)', 0, () => {
      expect(classifyScheme('/path:x')).assertEqual('deny');
      expect(classifyScheme('#a')).assertEqual('deny');
    });

    it('blocks encoded deny bypass', 0, () => {
      // 双重编码 javascript 仍归一化为 deny
      expect(classifyScheme('j%2561vascript:alert(1)')).assertEqual('deny');
      // 控制符注入仍归一化为 deny
      expect(classifyScheme('java\nscript:alert(1)')).assertEqual('deny');
    });
  });

  describe('hasScheme', () => {
    it('true when colon precedes first / ? #', 0, () => {
      expect(hasScheme('http://x')).assertEqual(true);
      expect(hasScheme('mailto:a@b')).assertEqual(true);
      expect(hasScheme('intent:#Intent')).assertEqual(true);   // 'intent:' before '#'
    });

    it('false for relative/anchor/query (colon after boundary or absent)', 0, () => {
      expect(hasScheme('/path:x')).assertEqual(false);         // ':' after '/'
      expect(hasScheme('#a:b')).assertEqual(false);            // ':' after '#'
      expect(hasScheme('?q=x:y')).assertEqual(false);          // ':' after '?'
      expect(hasScheme('no-colon')).assertEqual(false);
      expect(hasScheme(':leading')).assertEqual(false);        // colon at 0
    });
  });

  describe('extractScheme', () => {
    it('returns lowercased scheme', 0, () => {
      expect(extractScheme('HTTP://x')).assertEqual('http');
      expect(extractScheme('Intent:#x')).assertEqual('intent');
    });

    it('returns empty string when no scheme', 0, () => {
      expect(extractScheme('/path:x')).assertEqual('');
      expect(extractScheme('no-colon')).assertEqual('');
    });
  });

  describe('isAllowedScheme', () => {
    it('true when scheme in allowlist', 0, () => {
      expect(isAllowedScheme('intent', ['intent', 'market'])).assertEqual(true);
    });

    it('false when absent', 0, () => {
      expect(isAllowedScheme('tg', ['intent', 'market'])).assertEqual(false);
    });

    it('false for empty scheme (never allowlisted)', 0, () => {
      expect(isAllowedScheme('', ['intent'])).assertEqual(false);
    });
  });
}
