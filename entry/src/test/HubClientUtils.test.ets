// HubClientUtils 纯逻辑单测 —— 对照 web/src/api/client.ts + 原 HubClient 抽出的纯函数
// 覆盖 resolveBaseUrl（去尾斜杠）、buildApproveBody（仅序列化非空字段）、buildDenyBody、
//       buildSpawnBody（spawn 请求体条件化字段）、categorizeAuthFailure（登录失败归类）。

import { describe, it, expect } from '@ohos/hypium';
import {
  resolveBaseUrl,
  ApproveOptions,
  buildApproveBody,
  buildDenyBody,
  buildSpawnBody,
  categorizeAuthFailure
} from '../main/ets/api/HubClientUtils';

// 取 Record 的键签名（排序），便于断言「只包含哪些键」
function keys(rec: Record<string, Object>): string {
  return Object.keys(rec).sort().join(',');
}

export default function hubClientUtilsTest(): void {
  describe('resolveBaseUrl', () => {
    it('strips a single trailing slash', 0, () => {
      expect(resolveBaseUrl('http://h:3006/')).assertEqual('http://h:3006');
    });
    it('leaves a slashless url unchanged', 0, () => {
      expect(resolveBaseUrl('http://h:3006')).assertEqual('http://h:3006');
    });
    it('returns empty for empty input', 0, () => {
      expect(resolveBaseUrl('')).assertEqual('');
    });
    it('only strips the last slash (keeps path slashes)', 0, () => {
      expect(resolveBaseUrl('http://h/a/b/')).assertEqual('http://h/a/b');
    });
  });

  describe('buildApproveBody', () => {
    it('returns an empty body for undefined options', 0, () => {
      expect(keys(buildApproveBody(undefined))).assertEqual('');
    });
    it('returns an empty body for default ApproveOptions', 0, () => {
      expect(keys(buildApproveBody(new ApproveOptions()))).assertEqual('');
    });
    it('serializes mode only', 0, () => {
      const o = new ApproveOptions();
      o.mode = 'acceptEdits';
      const body = buildApproveBody(o);
      expect(keys(body)).assertEqual('mode');
      expect(body['mode']).assertEqual('acceptEdits');
    });
    it('serializes decision only', 0, () => {
      const o = new ApproveOptions();
      o.decision = 'approved_for_session';
      expect(keys(buildApproveBody(o))).assertEqual('decision');
    });
    it('serializes allowTools only when the array is non-empty', 0, () => {
      const o = new ApproveOptions();
      o.allowTools = ['Bash', 'Edit'];
      const body = buildApproveBody(o);
      expect(keys(body)).assertEqual('allowTools');
      expect((body['allowTools'] as string[]).length).assertEqual(2);
    });
    it('omits allowTools when the array is empty', 0, () => {
      const o = new ApproveOptions();
      o.allowTools = [];
      expect(keys(buildApproveBody(o))).assertEqual('');
    });
    it('serializes answers only when non-null', 0, () => {
      const o = new ApproveOptions();
      o.answers = JSON.parse('{"0":["optA"]}') as Record<string, Object>;
      const body = buildApproveBody(o);
      expect(keys(body)).assertEqual('answers');
      expect(body['answers'] !== undefined).assertTrue();
    });
    it('serializes all four fields together', 0, () => {
      const o = new ApproveOptions();
      o.mode = 'default';
      o.decision = 'approved';
      o.allowTools = ['Read'];
      o.answers = JSON.parse('{"0":["x"]}') as Record<string, Object>;
      expect(keys(buildApproveBody(o))).assertEqual('allowTools,answers,decision,mode');
    });
  });

  describe('buildDenyBody', () => {
    it('returns an empty body for undefined', 0, () => {
      expect(keys(buildDenyBody(undefined) as Record<string, Object>)).assertEqual('');
    });
    it('returns an empty body for empty decision', 0, () => {
      const body = buildDenyBody('') as Record<string, Object>;
      expect(keys(body)).assertEqual('');
    });
    it('serializes a non-empty decision', 0, () => {
      const body = buildDenyBody('denied') as Record<string, Object>;
      expect(keys(body)).assertEqual('decision');
      expect(body['decision']).assertEqual('denied');
    });
  });

  describe('categorizeAuthFailure', () => {
    it('returns "Access Token 无效" for 401', 0, () => {
      expect(categorizeAuthFailure(401, '', '')).assertEqual('Access Token 无效');
    });
    it('returns "无法连接到 Hub" for statusCode 0 with a network error', 0, () => {
      expect(categorizeAuthFailure(0, '', '请求失败: ...')).assertEqual('无法连接到 Hub，请检查地址');
    });
    it('falls back to default for statusCode 0 with no error message', 0, () => {
      expect(categorizeAuthFailure(0, '', '')).assertEqual('登录失败 (0)');
    });
    it('passes through the network error message for other status codes', 0, () => {
      expect(categorizeAuthFailure(500, '', 'HTTP 500')).assertEqual('HTTP 500');
    });
    it('parses {error} from a JSON error body', 0, () => {
      expect(categorizeAuthFailure(400, '{"error":"bad body"}', '')).assertEqual('bad body');
    });
    it('falls back to default when JSON body has no error key', 0, () => {
      expect(categorizeAuthFailure(400, '{"foo":1}', '')).assertEqual('登录失败 (400)');
    });
    it('falls back to default when the body is not JSON', 0, () => {
      expect(categorizeAuthFailure(400, 'not json', '')).assertEqual('登录失败 (400)');
    });
    it('returns the default message otherwise', 0, () => {
      expect(categorizeAuthFailure(503, '', '')).assertEqual('登录失败 (503)');
    });
  });

  // buildSpawnBody：directory/yolo/sessionType 恒发；agent 非空发；model/effort 非 'auto' 发；
  //   worktreeName 仅 sessionType==='worktree' 且 trim 非空发。对照上游 NewSession 提交解析。
  describe('buildSpawnBody', () => {
    it('always sends directory/agent/yolo/sessionType (defaults)', 0, () => {
      const body = buildSpawnBody('/proj', 'claude', 'auto', 'auto', false, 'simple', '');
      expect(keys(body)).assertEqual('agent,directory,sessionType,yolo');
      expect(body['directory']).assertEqual('/proj');
      expect(body['agent']).assertEqual('claude');
      expect(body['yolo']).assertEqual(false);
      expect(body['sessionType']).assertEqual('simple');
    });
    it('omits model when "auto"', 0, () => {
      const body = buildSpawnBody('/p', 'claude', 'auto', 'high', true, 'simple', '');
      expect(keys(body)).assertEqual('agent,directory,effort,sessionType,yolo');
    });
    it('omits effort when "auto"', 0, () => {
      const body = buildSpawnBody('/p', 'claude', 'sonnet', 'auto', true, 'simple', '');
      expect(keys(body)).assertEqual('agent,directory,model,sessionType,yolo');
      expect(body['model']).assertEqual('sonnet');
    });
    it('includes model+effort when both set', 0, () => {
      const body = buildSpawnBody('/p', 'claude', 'opus', 'max', true, 'simple', '');
      expect(keys(body)).assertEqual('agent,directory,effort,model,sessionType,yolo');
    });
    it('omits agent when empty', 0, () => {
      const body = buildSpawnBody('/p', '', 'auto', 'auto', false, 'simple', '');
      expect(keys(body)).assertEqual('directory,sessionType,yolo');
    });
    it('defaults sessionType to "simple" when empty', 0, () => {
      const body = buildSpawnBody('/p', 'claude', 'auto', 'auto', false, '', '');
      expect(body['sessionType']).assertEqual('simple');
    });
    it('omits worktreeName for simple even if provided', 0, () => {
      const body = buildSpawnBody('/p', 'claude', 'auto', 'auto', false, 'simple', 'feat-x');
      expect(keys(body)).assertEqual('agent,directory,sessionType,yolo');
    });
    it('includes worktreeName for worktree when non-empty', 0, () => {
      const body = buildSpawnBody('/p', 'claude', 'auto', 'auto', false, 'worktree', 'feat-x');
      expect(keys(body)).assertEqual('agent,directory,sessionType,worktreeName,yolo');
      expect(body['worktreeName']).assertEqual('feat-x');
    });
    it('trims worktreeName', 0, () => {
      const body = buildSpawnBody('/p', 'claude', 'auto', 'auto', false, 'worktree', '  feat-x  ');
      expect(body['worktreeName']).assertEqual('feat-x');
    });
    it('omits worktreeName when blank (whitespace only)', 0, () => {
      const body = buildSpawnBody('/p', 'claude', 'auto', 'auto', false, 'worktree', '   ');
      expect(keys(body)).assertEqual('agent,directory,sessionType,yolo');
    });
    it('omits worktreeName when empty for worktree', 0, () => {
      const body = buildSpawnBody('/p', 'claude', 'auto', 'auto', false, 'worktree', '');
      expect(keys(body)).assertEqual('agent,directory,sessionType,yolo');
    });
    it('passes yolo=true through', 0, () => {
      const body = buildSpawnBody('/p', 'codex', 'auto', 'auto', true, 'simple', '');
      expect(body['yolo']).assertEqual(true);
    });
  });
}
