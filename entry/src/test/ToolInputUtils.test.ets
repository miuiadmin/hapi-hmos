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
  parseToolUseError,
  extractResultText,
  extractStdoutStderr,
  extractCodexBashDisplay,
  parseCodexBashOutput,
  isMultilineText,
  looksLikeJson,
  looksLikeHtml,
  extractNotebookEditFields,
  formatNotebookCellMeta,
  NotebookEditFields
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

  describe('parseToolUseError', () => {
    it('returns not-an-error when the tag is absent', 0, () => {
      const r = parseToolUseError('just text');
      expect(r.isToolUseError).assertFalse();
      expect(r.errorMessage === null).assertTrue();
    });
    it('extracts the inner message from a pure tag', 0, () => {
      const r = parseToolUseError('<tool_use_error>Permission denied</tool_use_error>');
      expect(r.isToolUseError).assertTrue();
      expect(r.errorMessage).assertEqual('Permission denied');
    });
    it('extracts only the inner message, ignoring surrounding text', 0, () => {
      const r = parseToolUseError('prefix <tool_use_error>msg</tool_use_error> suffix');
      expect(r.isToolUseError).assertTrue();
      expect(r.errorMessage).assertEqual('msg');
    });
    it('trims whitespace inside the tag (incl. newlines)', 0, () => {
      const r = parseToolUseError('<tool_use_error>\n  boom  \n</tool_use_error>');
      expect(r.isToolUseError).assertTrue();
      expect(r.errorMessage).assertEqual('boom');
    });
    it('returns an empty inner message for an empty tag', 0, () => {
      const r = parseToolUseError('<tool_use_error></tool_use_error>');
      expect(r.isToolUseError).assertTrue();
      expect(r.errorMessage).assertEqual('');
    });
    it('returns not-an-error when the close tag is missing', 0, () => {
      const r = parseToolUseError('<tool_use_error>orphan');
      expect(r.isToolUseError).assertFalse();
      expect(r.errorMessage === null).assertTrue();
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
    it('falls back to object.error (latent-bug fix: error was missing from the key list)', 0, () => {
      expect(extractResultText(rec('{"error":"boom"}'))).assertEqual('boom');
    });
    it('returns empty for an object with no recognizable text field', 0, () => {
      expect(extractResultText(rec('{"foo":"bar"}'))).assertEqual('');
    });
    it('strips a <tool_use_error> tag from a string result', 0, () => {
      expect(extractResultText('<tool_use_error>Permission denied</tool_use_error>')).assertEqual('Permission denied');
    });
    it('strips the tag and discards surrounding text in a string result', 0, () => {
      expect(extractResultText('prefix <tool_use_error>msg</tool_use_error> suffix')).assertEqual('msg');
    });
    it('extracts nested output.content', 0, () => {
      expect(extractResultText(rec('{"output":{"content":"oc"}}'))).assertEqual('oc');
    });
    it('extracts nested output.text', 0, () => {
      expect(extractResultText(rec('{"output":{"text":"ot"}}'))).assertEqual('ot');
    });
    it('extracts nested error.message', 0, () => {
      expect(extractResultText(rec('{"error":{"message":"em"}}'))).assertEqual('em');
    });
    it('extracts nested error.error', 0, () => {
      expect(extractResultText(rec('{"error":{"error":"ee"}}'))).assertEqual('ee');
    });
    it('recurses into result', 0, () => {
      expect(extractResultText(rec('{"result":{"text":"deep"}}'))).assertEqual('deep');
    });
    it('recurses into data', 0, () => {
      expect(extractResultText(rec('{"data":{"content":"dd"}}'))).assertEqual('dd');
    });
    it('extracts a content array living on an object', 0, () => {
      const o: Object = JSON.parse('{"content":[{"type":"text","text":"x"},{"text":"y"}]}');
      expect(extractResultText(o)).assertEqual('x\ny');
    });
    it('stops recursing beyond depth 2 (returns empty)', 0, () => {
      const o: Object = JSON.parse('{"result":{"result":{"result":{"text":"too deep"}}}}');
      expect(extractResultText(o)).assertEqual('');
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

  describe('extractNotebookEditFields', () => {
    it('parses all four cell fields', 0, () => {
      const f: NotebookEditFields = extractNotebookEditFields(rec('{"cell_id":"c1","cell_type":"code","edit_mode":"replace","new_source":"print(1)"}'));
      expect(f.cellId).assertEqual('c1');
      expect(f.cellType).assertEqual('code');
      expect(f.editMode).assertEqual('replace');
      expect(f.newSource).assertEqual('print(1)');
    });
    it('insert mode (no cell_id) leaves cellId empty', 0, () => {
      const f: NotebookEditFields = extractNotebookEditFields(rec('{"cell_type":"markdown","edit_mode":"insert","new_source":"# hi"}'));
      expect(f.cellId).assertEqual('');
      expect(f.cellType).assertEqual('markdown');
      expect(f.newSource).assertEqual('# hi');
    });
    it('delete mode (no new_source) leaves newSource empty', 0, () => {
      const f: NotebookEditFields = extractNotebookEditFields(rec('{"cell_id":"c2","edit_mode":"delete"}'));
      expect(f.newSource).assertEqual('');
      expect(f.cellId).assertEqual('c2');
      expect(f.editMode).assertEqual('delete');
    });
    it('returns all-empty for null input', 0, () => {
      const f: NotebookEditFields = extractNotebookEditFields(null);
      expect(f.cellId).assertEqual('');
      expect(f.cellType).assertEqual('');
      expect(f.editMode).assertEqual('');
      expect(f.newSource).assertEqual('');
    });
    it('coerces non-string values to empty', 0, () => {
      const f: NotebookEditFields = extractNotebookEditFields(rec('{"cell_id":42,"cell_type":true}'));
      expect(f.cellId).assertEqual('');
      expect(f.cellType).assertEqual('');
    });
  });

  describe('formatNotebookCellMeta', () => {
    it('joins cellType and #cellId', 0, () => {
      expect(formatNotebookCellMeta('code', 'abc123')).assertEqual('code · #abc123');
    });
    it('uses only cellType when cellId is empty (insert)', 0, () => {
      expect(formatNotebookCellMeta('markdown', '')).assertEqual('markdown');
    });
    it('uses only #cellId when cellType is empty', 0, () => {
      expect(formatNotebookCellMeta('', 'c9')).assertEqual('#c9');
    });
    it('returns empty when both are empty', 0, () => {
      expect(formatNotebookCellMeta('', '')).assertEqual('');
    });
    it('truncates a long cellId to 12 chars + ellipsis', 0, () => {
      const long: string = 'cell-aaaaaaaaaaaaaaaaaa';
      expect(formatNotebookCellMeta('code', long)).assertEqual('code · #' + long.substring(0, 12) + '…');
    });
  });

  describe('extractCodexBashDisplay', () => {
    it('returns null for null', 0, () => {
      expect(extractCodexBashDisplay(null) === null).assertTrue();
    });
    it('returns null for a non-object (string)', 0, () => {
      expect(extractCodexBashDisplay('str') === null).assertTrue();
    });
    it('returns null for an array', 0, () => {
      const arr: Object = JSON.parse('[1,2]');
      expect(extractCodexBashDisplay(arr) === null).assertTrue();
    });
    it('returns null when all four fields are absent', 0, () => {
      expect(extractCodexBashDisplay(rec('{"foo":"bar"}')) === null).assertTrue();
    });
    it('extracts exit_code + stdout + stderr', 0, () => {
      const d = extractCodexBashDisplay(rec('{"exit_code":1,"stdout":"out","stderr":"err"}'));
      expect(d !== null).assertTrue();
      if (d !== null) {
        expect(d.hasExitCode).assertTrue();
        expect(d.exitCode).assertEqual(1);
        expect(d.stdout).assertEqual('out');
        expect(d.stderr).assertEqual('err');
        expect(d.status).assertEqual('');
      }
    });
    it('exit_code 0 sets hasExitCode true with exitCode 0 (falsy-safe)', 0, () => {
      const d = extractCodexBashDisplay(rec('{"exit_code":0,"stdout":"x"}'));
      expect(d !== null).assertTrue();
      if (d !== null) {
        expect(d.hasExitCode).assertTrue();
        expect(d.exitCode).assertEqual(0);
      }
    });
    it('accepts camelCase exitCode as a fallback', 0, () => {
      const d = extractCodexBashDisplay(rec('{"exitCode":42}'));
      expect(d !== null).assertTrue();
      if (d !== null) {
        expect(d.hasExitCode).assertTrue();
        expect(d.exitCode).assertEqual(42);
      }
    });
    it('falls back to output for stdout when stdout is absent', 0, () => {
      const d = extractCodexBashDisplay(rec('{"output":"oo"}'));
      expect(d !== null).assertTrue();
      if (d !== null) {
        expect(d.stdout).assertEqual('oo');
        expect(d.hasExitCode).assertFalse();
      }
    });
    it('reads status (string) alone', 0, () => {
      const d = extractCodexBashDisplay(rec('{"status":"completed"}'));
      expect(d !== null).assertTrue();
      if (d !== null) {
        expect(d.status).assertEqual('completed');
        expect(d.hasExitCode).assertFalse();
      }
    });
  });

  describe('parseCodexBashOutput', () => {
    it('returns null for empty string', 0, () => {
      expect(parseCodexBashOutput('') === null).assertTrue();
    });
    it('returns null when no section is present', 0, () => {
      expect(parseCodexBashOutput('just plain output\nno headers here') === null).assertTrue();
    });
    it('parses the standard three sections', 0, () => {
      const p = parseCodexBashOutput('Exit code: 1\nWall time: 0.5s\nOutput:\nhello\nworld');
      expect(p !== null).assertTrue();
      if (p !== null) {
        expect(p.hasExitCode).assertTrue();
        expect(p.exitCode).assertEqual(1);
        expect(p.wallTime).assertEqual('0.5s');
        expect(p.output).assertEqual('hello\nworld');
      }
    });
    it('defaults output to the full text when no Output: section', 0, () => {
      const p = parseCodexBashOutput('Exit code: 0');
      expect(p !== null).assertTrue();
      if (p !== null) {
        expect(p.exitCode).assertEqual(0);
        expect(p.output).assertEqual('Exit code: 0');
        expect(p.wallTime).assertEqual('');
      }
    });
    it('tolerates whitespace after "Exit code:" before the number', 0, () => {
      const p = parseCodexBashOutput('Exit code:   42');
      expect(p !== null).assertTrue();
      if (p !== null) {
        expect(p.exitCode).assertEqual(42);
      }
    });
    it('non-numeric exit code does not set hasExitCode (and alone → null)', 0, () => {
      expect(parseCodexBashOutput('Exit code: abc') === null).assertTrue();
    });
    it('non-numeric exit code still lets Wall time win', 0, () => {
      const p = parseCodexBashOutput('Exit code: abc\nWall time: 1s');
      expect(p !== null).assertTrue();
      if (p !== null) {
        expect(p.hasExitCode).assertFalse();
        expect(p.wallTime).assertEqual('1s');
      }
    });
    it('does not treat "Output: x" (no newline) as the output section', 0, () => {
      // 行须精确等于 'Output:'；'Output: hello' 非 output 段头，且非 Exit/Wall → null
      expect(parseCodexBashOutput('Output: hello') === null).assertTrue();
    });
  });
}
