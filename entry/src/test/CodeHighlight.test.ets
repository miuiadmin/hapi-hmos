// CodeHighlight 单测 —— 语法高亮纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 TerminalToolDisplay.test / GeneratedImageCacheUtils.test 范式：同步断言。
//   覆盖 normalizeLanguage（扩展名/alias/language-前缀/大小写/未注册→text）+
//   tokenizeLine（comment/string/number/keyword/plain 五类 token + 9 语言关键字命中 +
//   空行占位 + 字符串内含注释标记不误判 + 转义引号 + 标识符查表）。

import { describe, it, expect } from '@ohos/hypium';
import {
  normalizeLanguage,
  tokenizeLine,
  HighlightToken
} from '../main/ets/chat/CodeHighlight';

// 辅助：取首个非 plain token 的类型（断言「该行至少染了一个色」用）。
function firstColoredType(line: string, language: string): string {
  const tokens: HighlightToken[] = tokenizeLine(line, language);
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i].type !== 'plain') {
      return tokens[i].type;
    }
  }
  return 'plain';
}

// 辅助：拼回行文本（token.text 串接应等于输入，验证扫描无丢字符）。
function joinTokenText(line: string, language: string): string {
  const tokens: HighlightToken[] = tokenizeLine(line, language);
  let out: string = '';
  for (let i = 0; i < tokens.length; i++) {
    out += tokens[i].text;
  }
  return out;
}

// 辅助：是否含某类型 token（避免 .some/​.find 的 | undefined 类型坑）。
function hasTokenType(line: string, language: string, type: string): boolean {
  const tokens: HighlightToken[] = tokenizeLine(line, language);
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i].type === type) { return true; }
  }
  return false;
}

// 辅助：取第一个某类型 token 的文本（找不到返回 ''）。
function firstTokenText(line: string, language: string, type: string): string {
  const tokens: HighlightToken[] = tokenizeLine(line, language);
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i].type === type) { return tokens[i].text; }
  }
  return '';
}

export default function codeHighlightTest(): void {
  // —— normalizeLanguage ——
  describe('CodeHighlight — normalizeLanguage 基本映射', () => {
    it('ts → js', 0, () => {
      expect(normalizeLanguage('ts')).assertEqual('js');
    });
    it('tsx → js', 0, () => {
      expect(normalizeLanguage('tsx')).assertEqual('js');
    });
    it('javascript → js', 0, () => {
      expect(normalizeLanguage('javascript')).assertEqual('js');
    });
    it('python → py', 0, () => {
      expect(normalizeLanguage('python')).assertEqual('py');
    });
    it('rust → rs', 0, () => {
      expect(normalizeLanguage('rust')).assertEqual('rs');
    });
    it('kotlin → java', 0, () => {
      expect(normalizeLanguage('kotlin')).assertEqual('java');
    });
    it('cs → java（C# 归 java 关键字表）', 0, () => {
      expect(normalizeLanguage('cs')).assertEqual('java');
    });
    it('bash → sh', 0, () => {
      expect(normalizeLanguage('bash')).assertEqual('sh');
    });
    it('yml → yaml', 0, () => {
      expect(normalizeLanguage('yml')).assertEqual('yaml');
    });
    it('直接命中 profile key（go）', 0, () => {
      expect(normalizeLanguage('go')).assertEqual('go');
    });
    it('直接命中 profile key（json）', 0, () => {
      expect(normalizeLanguage('json')).assertEqual('json');
    });
  });

  describe('CodeHighlight — normalizeLanguage 前缀/归一', () => {
    it('language- 前缀剥除', 0, () => {
      expect(normalizeLanguage('language-typescript')).assertEqual('js');
    });
    it('大小写归一（PYTHON）→ py', 0, () => {
      expect(normalizeLanguage('PYTHON')).assertEqual('py');
    });
    it('text → text', 0, () => {
      expect(normalizeLanguage('text')).assertEqual('text');
    });
    it('txt → text', 0, () => {
      expect(normalizeLanguage('txt')).assertEqual('text');
    });
    it('unknown → text', 0, () => {
      expect(normalizeLanguage('unknown')).assertEqual('text');
    });
    it('未注册（markdown）→ text', 0, () => {
      expect(normalizeLanguage('markdown')).assertEqual('text');
    });
    it('空串 → text', 0, () => {
      expect(normalizeLanguage('')).assertEqual('text');
    });
    it('undefined → text', 0, () => {
      expect(normalizeLanguage(undefined)).assertEqual('text');
    });
  });

  // —— tokenizeLine：五类 token ——
  describe('CodeHighlight — tokenizeLine comment', () => {
    it('js // 行注释 → comment', 0, () => {
      expect(firstColoredType('// hi', 'js')).assertEqual('comment');
    });
    it('py # 行注释 → comment', 0, () => {
      expect(firstColoredType('# hi', 'py')).assertEqual('comment');
    });
    it('sql -- 行注释 → comment', 0, () => {
      expect(firstColoredType('-- hi', 'sql')).assertEqual('comment');
    });
    it('注释消费至行尾（单 token）', 0, () => {
      const tokens: HighlightToken[] = tokenizeLine('const x = 1 // done', 'js');
      // 最后一个 token 应是注释，且文本含 "done"
      const last: HighlightToken = tokens[tokens.length - 1];
      expect(last.type).assertEqual('comment');
      expect(last.text.includes('done')).assertTrue();
    });
  });

  describe('CodeHighlight — tokenizeLine string', () => {
    it('双引号串 → string', 0, () => {
      expect(firstColoredType('"hello"', 'js')).assertEqual('string');
    });
    it('单引号串 → string', 0, () => {
      expect(firstColoredType('\'a\'', 'py')).assertEqual('string');
    });
    it('反引号串 → string', 0, () => {
      expect(firstColoredType('`tmpl`', 'js')).assertEqual('string');
    });
    it('串内含 # 不被当 py 注释（# 在串内）', 0, () => {
      // 期望首个着色 token 是 string（不是 comment）
      expect(firstColoredType('"a#b"', 'py')).assertEqual('string');
    });
    it('转义引号不提前闭合串', 0, () => {
      // "a\"b" 应作为一个 string token（含转义引号），整串文本 6 字符不变。
      const tokText: string = firstTokenText('"a\\"b"', 'js', 'string');
      expect(tokText !== '').assertTrue();
      expect(tokText).assertEqual('"a\\"b"');
    });
  });

  describe('CodeHighlight — tokenizeLine number', () => {
    it('十进制 → number', 0, () => {
      expect(firstColoredType('42', 'js')).assertEqual('number');
    });
    it('浮点 → number', 0, () => {
      expect(firstColoredType('3.14', 'js')).assertEqual('number');
    });
    it('十六进制 0xFF → number', 0, () => {
      expect(firstColoredType('0xFF', 'js')).assertEqual('number');
    });
    it('串中数字不单独成 number（先串优先）', 0, () => {
      // "abc123" 整体是 string，不应出现 number token
      expect(hasTokenType('"abc123"', 'js', 'number')).assertFalse();
    });
  });

  describe('CodeHighlight — tokenizeLine keyword（9 语言命中）', () => {
    it('js: function → keyword', 0, () => {
      expect(firstColoredType('function', 'js')).assertEqual('keyword');
    });
    it('py: def → keyword', 0, () => {
      expect(firstColoredType('def', 'py')).assertEqual('keyword');
    });
    it('go: func → keyword', 0, () => {
      expect(firstColoredType('func', 'go')).assertEqual('keyword');
    });
    it('rs: fn → keyword', 0, () => {
      expect(firstColoredType('fn', 'rs')).assertEqual('keyword');
    });
    it('java: class → keyword', 0, () => {
      expect(firstColoredType('class', 'java')).assertEqual('keyword');
    });
    it('sql: SELECT → keyword（大写）', 0, () => {
      expect(firstColoredType('SELECT', 'sql')).assertEqual('keyword');
    });
    it('sh: echo → keyword', 0, () => {
      expect(firstColoredType('echo', 'sh')).assertEqual('keyword');
    });
    it('json: true → keyword', 0, () => {
      expect(firstColoredType('true', 'json')).assertEqual('keyword');
    });
    it('yaml: yes → keyword', 0, () => {
      expect(firstColoredType('yes', 'yaml')).assertEqual('keyword');
    });
    it('标识符非关键字 → plain（如 myVar）', 0, () => {
      const tokens: HighlightToken[] = tokenizeLine('myVar', 'js');
      // 仅一个 plain token
      expect(tokens.length).assertEqual(1);
      expect(tokens[0].type).assertEqual('plain');
    });
  });

  // —— 边界 ——
  describe('CodeHighlight — tokenizeLine 边界', () => {
    it('空行 → 单个 plain 占位空格', 0, () => {
      const tokens: HighlightToken[] = tokenizeLine('', 'js');
      expect(tokens.length).assertEqual(1);
      expect(tokens[0].type).assertEqual('plain');
      expect(tokens[0].text).assertEqual(' ');
    });
    it('text 语言 → 全 plain（零回归）', 0, () => {
      // 即便含看似关键字/数字/注释，text 无 profile → 全 plain
      const tokens: HighlightToken[] = tokenizeLine('function 42 // x', 'text');
      for (let i = 0; i < tokens.length; i++) {
        expect(tokens[i].type).assertEqual('plain');
      }
    });
    it('未注册语言（markdown）→ 全 plain', 0, () => {
      const tokens: HighlightToken[] = tokenizeLine('# heading', 'markdown');
      expect(tokens.length).assertEqual(1);
      expect(tokens[0].type).assertEqual('plain');
    });
    it('扫描完整性：token 串接 == 原行（js 混合行）', 0, () => {
      const line: string = 'const x = "hi" // c';
      expect(joinTokenText(line, 'js')).assertEqual(line);
    });
    it('相邻 plain 合并（纯符号串单 token）', 0, () => {
      // "===" 无标识符/数字/串，应合并成单个 plain
      const tokens: HighlightToken[] = tokenizeLine('===', 'js');
      expect(tokens.length).assertEqual(1);
      expect(tokens[0].type).assertEqual('plain');
      expect(tokens[0].text).assertEqual('===');
    });
  });
}
