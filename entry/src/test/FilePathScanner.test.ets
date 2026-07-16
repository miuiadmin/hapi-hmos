// FilePathScanner 纯逻辑单测 —— 对照 web/src/lib/remark-file-path-links.test.ts
// 零 @kit：仅 import 被测纯层（utils/FilePathScanner）。
//   覆盖：上游 4 用例（含行号剥离 / 双链接 / abs·home·parent·win 否决 / URL 否决）
//         + 豁免（围栏代码 / 行内代码 / link span）+ 幂等（同引用）+ decodeFilePathHref。

import { describe, it, expect } from '@ohos/hypium';
import { scanFilePaths, decodeFilePathHref } from '../main/ets/utils/FilePathScanner';

class FileLink {
  display: string = '';
  target: string = '';
}

// 从 scan 输出里抽 [display](hapi-file:enc) 链接（手写扫描，无 regex）—— 镜像上游测试 linkedPath（解码 url）。
function extractHapiFileLinks(md: string): FileLink[] {
  const links: FileLink[] = [];
  const marker: string = '](hapi-file:';
  let from: number = 0;
  while (true) {
    const idx: number = md.indexOf(marker, from);
    if (idx < 0) { break; }
    // display = '[' 与 ']' 之间（marker 首字符即 ']'，故 idx 指向 ']'）
    let open: number = -1;
    for (let k: number = idx - 1; k >= 0; k--) {
      if (md.charAt(k) === '[') { open = k; break; }
    }
    const display: string = open >= 0 ? md.substring(open + 1, idx) : '';
    // target = 'hapi-file:' 之后到 ')' ，再 decodeFilePathHref
    const hrefStart: number = idx + marker.length;
    const closeParen: number = md.indexOf(')', hrefStart);
    if (closeParen < 0) { break; }
    const href: string = 'hapi-file:' + md.substring(hrefStart, closeParen);
    const target: string | null = decodeFilePathHref(href);
    const fl: FileLink = new FileLink();
    fl.display = display;
    fl.target = target !== null ? target : '';
    links.push(fl);
    from = closeParen + 1;
  }
  return links;
}

export default function filePathScannerTest(): void {
  describe('scanFilePaths（上游 4 用例）', () => {
    it('相对代码路径 + 行号剥离 target', 0, () => {
      const out: string = scanFilePaths('Open web/src/router.tsx:42 please');
      const links: FileLink[] = extractHapiFileLinks(out);
      expect(links.length).assertEqual(1);
      expect(links[0].display).assertEqual('web/src/router.tsx:42');   // display 含行号
      expect(links[0].target).assertEqual('web/src/router.tsx');       // target 剥行号
    });

    it('图片 / markdown 文件名双链接', 0, () => {
      const out: string = scanFilePaths('See screenshot.png and README.md');
      const links: FileLink[] = extractHapiFileLinks(out);
      expect(links.length).assertEqual(2);
      expect(links[0].target).assertEqual('screenshot.png');
      expect(links[1].target).assertEqual('README.md');
    });

    it('abs / ~ / ../ / Win 盘符路径否决（会话工作区外）', 0, () => {
      const out: string = scanFilePaths('Skip /Users/dev/project/a.png, ~/a.png, ../a.png and C:\\tmp\\a.png');
      const links: FileLink[] = extractHapiFileLinks(out);
      expect(links.length).assertEqual(0);
    });

    it('普通 URL 不改写（:// + previousChar / 双重否决）', 0, () => {
      const out: string = scanFilePaths('Visit https://example.com/web/src/router.tsx');
      const links: FileLink[] = extractHapiFileLinks(out);
      expect(links.length).assertEqual(0);
    });
  });

  describe('scanFilePaths（行号形态）', () => {
    it(':line:col 双段行号 target 全剥、display 全留', 0, () => {
      const out: string = scanFilePaths('see web/x.ts:42:7 here');
      const links: FileLink[] = extractHapiFileLinks(out);
      expect(links.length).assertEqual(1);
      expect(links[0].display).assertEqual('web/x.ts:42:7');
      expect(links[0].target).assertEqual('web/x.ts');
    });

    it('行尾标点（句号 / 逗号）剥出 trailing，不计入 target', 0, () => {
      const out: string = scanFilePaths('edit a.ts, then b.py.');
      const links: FileLink[] = extractHapiFileLinks(out);
      expect(links.length).assertEqual(2);
      expect(links[0].target).assertEqual('a.ts');
      expect(links[1].target).assertEqual('b.py');
      expect(out.indexOf('a.ts,')).assertGreaterThanOrEqual(0);   // 逗号留在链接外
    });
  });

  describe('scanFilePaths（豁免区）', () => {
    it('围栏代码块内路径 verbatim（不链）', 0, () => {
      const md: string = '```\nsrc/foo.ts:1\nbar.ts:2\n```';
      const out: string = scanFilePaths(md);
      const links: FileLink[] = extractHapiFileLinks(out);
      expect(links.length).assertEqual(0);
      expect(out.indexOf('src/foo.ts:1')).assertGreaterThanOrEqual(0);   // 文本保留
    });

    it('行内代码内路径 verbatim（不链）', 0, () => {
      const md: string = 'see `src/foo.ts` here';
      const out: string = scanFilePaths(md);
      const links: FileLink[] = extractHapiFileLinks(out);
      expect(links.length).assertEqual(0);
      expect(out.indexOf('`src/foo.ts`')).assertGreaterThanOrEqual(0);
    });

    it('link span 内路径不二次链（[...](...) verbatim）', 0, () => {
      const md: string = '[see web/x.ts](http://y)';
      const out: string = scanFilePaths(md);
      const links: FileLink[] = extractHapiFileLinks(out);
      expect(links.length).assertEqual(0);   // span 内 web/x.ts 不被注入
      expect(out).assertEqual(md);           // 原样
    });
  });

  describe('scanFilePaths（幂等）', () => {
    it('无路径内容返回同引用（===）', 0, () => {
      const plain: string = 'just some text with no paths here';
      const out: string = scanFilePaths(plain);
      expect(out === plain).assertTrue();
    });

    it('已链接输出再扫返回同引用（不二次注入）', 0, () => {
      const once: string = scanFilePaths('open web/x.ts');
      const twice: string = scanFilePaths(once);
      expect(twice === once).assertTrue();
    });

    it('空串返回同引用', 0, () => {
      const empty: string = '';
      expect(scanFilePaths(empty) === empty).assertTrue();
    });
  });

  describe('decodeFilePathHref', () => {
    it('剥前缀 + 解码 %2F → /', 0, () => {
      expect(decodeFilePathHref('hapi-file:web%2Fsrc%2Frouter.tsx')).assertEqual('web/src/router.tsx');
    });

    it('无前缀 → null', 0, () => {
      expect(decodeFilePathHref('https://example.com')).assertNull();
      expect(decodeFilePathHref('web/src/x.ts')).assertNull();
    });

    it('非法转义 → null（不抛）', 0, () => {
      expect(decodeFilePathHref('hapi-file:%')).assertNull();
    });
  });
}
