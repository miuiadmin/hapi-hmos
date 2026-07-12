// ToolInputUtils 纯逻辑单测 —— 对照 web ToolCard 字段读取 / 结果文本提取
// 覆盖 getInputStr / hasInputStr / getInputStrAny / truncateStr /
//   extractResultText（string / 文本块数组 / 字符串数组 / 对象回退）/ extractStdoutStderr（平铺 / 嵌套 / null）/
//   isMultilineText / looksLikeJson / looksLikeHtml。

import { describe, it, expect } from '@ohos/hypium';
import {
  getInputStr,
  hasInputStr,
  getInputStrAny,
  truncateStr,
  extractResultText,
  extractStdoutStderr,
  isMultilineText,
  looksLikeJson,
  looksLikeHtml
} from '../main/ets/chat/ToolInputUtils';

function rec(json: string): Record<string, Object> {
  return JSON.parse(json) as Record<string, Object>;
}

export default function toolInputUtilsTest(): void {
  describe('getInputStr / hasInputStr', () => {
    it('returns a present string field', 0, () => {
      expect(getInputStr(rec('{"file_path":"/a"}'), 'file_path')).assertEqual('/a');
    });
    it('returns empty string for a missing key', 0, () => {
      expect(getInputStr(rec('{"a":1}'), 'file_path')).assertEqual('');
    });
    it('returns empty string for a non-string value', 0, () => {
      expect(getInputStr(rec('{"file_path":123}'), 'file_path')).assertEqual('');
    });
    it('returns empty string when input is null', 0, () => {
      expect(getInputStr(null, 'file_path')).assertEqual('');
    });

    it('hasInputStr is true for a string value (even empty)', 0, () => {
      expect(hasInputStr(rec('{"old_string":""}'), 'old_string')).assertTrue();
    });
    it('hasInputStr is false for a missing key', 0, () => {
      expect(hasInputStr(rec('{"a":1}'), 'old_string')).assertFalse();
    });
    it('hasInputStr is false for a non-string value', 0, () => {
      expect(hasInputStr(rec('{"old_string":5}'), 'old_string')).assertFalse();
    });
    it('hasInputStr is false when input is null', 0, () => {
      expect(hasInputStr(null, 'old_string')).assertFalse();
    });
  });

  describe('getInputStrAny', () => {
    it('returns the first non-empty candidate', 0, () => {
      const keys: string[] = ['file_path', 'path', 'file'];
      expect(getInputStrAny(rec('{"path":"/p"}'), keys)).assertEqual('/p');
    });
    it('skips empty-string candidates', 0, () => {
      const keys: string[] = ['file_path', 'path'];
      expect(getInputStrAny(rec('{"file_path":"","path":"/p"}'), keys)).assertEqual('/p');
    });
    it('returns empty string when no candidate matches', 0, () => {
      const keys: string[] = ['file_path', 'path'];
      expect(getInputStrAny(rec('{"x":1}'), keys)).assertEqual('');
    });
    it('returns empty string when input is null', 0, () => {
      const keys: string[] = ['file_path'];
      expect(getInputStrAny(null, keys)).assertEqual('');
    });
  });

  describe('truncateStr', () => {
    it('leaves a short string unchanged', 0, () => {
      expect(truncateStr('abc', 10)).assertEqual('abc');
    });
    it('leaves an exactly-max-length string unchanged', 0, () => {
      expect(truncateStr('abcde', 5)).assertEqual('abcde');
    });
    it('truncates and adds an ellipsis when over max', 0, () => {
      expect(truncateStr('abcdef', 3)).assertEqual('abc…');
    });
    it('does not truncate when max is <= 0', 0, () => {
      expect(truncateStr('abcdef', 0)).assertEqual('abcdef');
    });
  });

  describe('extractResultText', () => {
    it('returns empty for null', 0, () => {
      expect(extractResultText(null)).assertEqual('');
    });
    it('returns a plain string as-is', 0, () => {
      expect(extractResultText('done')).assertEqual('done');
    });
    it('joins text blocks with newlines', 0, () => {
      const arr: Object = JSON.parse('[{"type":"text","text":"a"},{"type":"text","text":"b"}]');
      expect(extractResultText(arr)).assertEqual('a\nb');
    });
    it('joins a string array with newlines', 0, () => {
      const arr: Object = JSON.parse('["x","y"]');
      expect(extractResultText(arr)).assertEqual('x\ny');
    });
    it('handles a mixed array (strings + text blocks, skipping numbers/nulls)', 0, () => {
      const arr: Object = JSON.parse('["x",{"text":"y"},123,null]');
      expect(extractResultText(arr)).assertEqual('x\ny');
    });
    it('falls back to object.output when there is no text', 0, () => {
      expect(extractResultText(rec('{"output":"o"}'))).assertEqual('o');
    });
    it('falls back to object.message', 0, () => {
      expect(extractResultText(rec('{"message":"m"}'))).assertEqual('m');
    });
    it('returns empty for an object with no recognizable text field', 0, () => {
      expect(extractResultText(rec('{"foo":"bar"}'))).assertEqual('');
    });
  });

  describe('extractStdoutStderr', () => {
    it('returns null for null', 0, () => {
      expect(extractStdoutStderr(null) === null).assertTrue();
    });
    it('returns null for a non-object (string)', 0, () => {
      expect(extractStdoutStderr('str') === null).assertTrue();
    });
    it('returns null for an array', 0, () => {
      const arr: Object = JSON.parse('[1,2]');
      expect(extractStdoutStderr(arr) === null).assertTrue();
    });
    it('extracts flat stdout and stderr', 0, () => {
      const r = extractStdoutStderr(rec('{"stdout":"out","stderr":"err"}'));
      expect(r !== null).assertTrue();
      if (r !== null) {
        expect(r.stdout).assertEqual('out');
        expect(r.stderr).assertEqual('err');
      }
    });
    it('returns a pair when only stdout is present', 0, () => {
      const r = extractStdoutStderr(rec('{"stdout":"out"}'));
      expect(r !== null).assertTrue();
      if (r !== null) {
        expect(r.stdout).assertEqual('out');
        expect(r.stderr).assertEqual('');
      }
    });
    it('extracts nested output.stdout/stderr', 0, () => {
      const r = extractStdoutStderr(rec('{"output":{"stdout":"x","stderr":"y"}}'));
      expect(r !== null).assertTrue();
      if (r !== null) {
        expect(r.stdout).assertEqual('x');
        expect(r.stderr).assertEqual('y');
      }
    });
    it('returns null when neither flat nor nested stdout/stderr is present', 0, () => {
      expect(extractStdoutStderr(rec('{"foo":"bar"}') ) === null).assertTrue();
    });
  });

  describe('isMultilineText', () => {
    it('is true for more than 3 lines', 0, () => {
      expect(isMultilineText('a\nb\nc\nd')).assertTrue();
    });
    it('is false for exactly 3 lines', 0, () => {
      expect(isMultilineText('a\nb\nc')).assertFalse();
    });
    it('is false for a single line', 0, () => {
      expect(isMultilineText('only')).assertFalse();
    });
  });

  describe('looksLikeJson', () => {
    it('recognizes a JSON object', 0, () => {
      expect(looksLikeJson('{"a":1}')).assertTrue();
    });
    it('recognizes a JSON array', 0, () => {
      expect(looksLikeJson('[1,2]')).assertTrue();
    });
    it('ignores surrounding whitespace', 0, () => {
      expect(looksLikeJson('  {"a":1}  ')).assertTrue();
    });
    it('rejects plain text', 0, () => {
      expect(looksLikeJson('hello')).assertFalse();
    });
    it('rejects an unclosed brace', 0, () => {
      expect(looksLikeJson('{"a":1')).assertFalse();
    });
  });

  describe('looksLikeHtml', () => {
    it('recognizes a DOCTYPE document', 0, () => {
      expect(looksLikeHtml('<!DOCTYPE html>')).assertTrue();
    });
    it('recognizes <html> / <div> / <span> starts', 0, () => {
      expect(looksLikeHtml('<html>')).assertTrue();
      expect(looksLikeHtml('<div>x</div>')).assertTrue();
      expect(looksLikeHtml('<span>y</span>')).assertTrue();
    });
    it('ignores leading whitespace', 0, () => {
      expect(looksLikeHtml('   <div>')).assertTrue();
    });
    it('rejects plain text and non-listed tags', 0, () => {
      expect(looksLikeHtml('plain')).assertFalse();
      expect(looksLikeHtml('<p>')).assertFalse(); // <p> 不在识别列表
    });
  });
}
