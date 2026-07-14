// Types 纯逻辑单测 —— 对照 hapi shared/src 的会话解析（SessionSummary / Session）
// 覆盖 pick* 安全取值、parseSessionSummary（含 metadata / todoProgress / title / summaryText）、
//   parseSessionsResponse（数组解析 + 过滤 + 非法输入）、parseSessionDetail（session 信封 + agentStateRaw）。

import { describe, it, expect } from '@ohos/hypium';
import {
  pickStr,
  pickNum,
  pickBool,
  pickObj,
  pickStrArr,
  parseSessionSummary,
  parseSessionsResponse,
  parseSessionDetail,
  parseMachinesResponse,
  parseListDirectoryResponse,
  parseSpawnResponse,
  parseCodexModelsResponse,
  parseOpencodeModelsResponse,
  parseTeamState,
  parseTodoList,
  parseSlashCommandsResponse,
  parseSkillsResponse,
  AGENT_FLAVORS,
  agentDisplayName,
  permissionModesForFlavor,
  reasoningEffortsForFlavor,
  permissionModeDisplayName,
  collaborationModeDisplayName,
  reasoningEffortDisplayName,
  FileSearchItem,
  parseFileSearchResponse,
  parseCommandResponse,
  parseFileReadResponse,
  SessionDirEntry,
  parseSessionDirectoryResponse,
  parseUploadFileResponse,
  parseThreadGoal
} from '../main/ets/models/Types';

function rec(json: string): Record<string, Object> {
  return JSON.parse(json) as Record<string, Object>;
}

export default function typesTest(): void {
  describe('pick helpers', () => {
    it('pickStr returns the string or empty', 0, () => {
      expect(pickStr(rec('{"a":"hi"}'), 'a')).assertEqual('hi');
      expect(pickStr(rec('{"a":5}'), 'a')).assertEqual('');
      expect(pickStr(rec('{}'), 'a')).assertEqual('');
    });
    it('pickNum returns the number or 0', 0, () => {
      expect(pickNum(rec('{"a":7}'), 'a')).assertEqual(7);
      expect(pickNum(rec('{"a":"x"}'), 'a')).assertEqual(0);
      expect(pickNum(rec('{}'), 'a')).assertEqual(0);
    });
    it('pickBool returns the boolean or false', 0, () => {
      expect(pickBool(rec('{"a":true}'), 'a')).assertTrue();
      expect(pickBool(rec('{"a":1}'), 'a')).assertFalse();
      expect(pickBool(rec('{}'), 'a')).assertFalse();
    });
    it('pickObj returns a non-array object or null', 0, () => {
      expect(pickObj(rec('{"a":{"x":1}}'), 'a') !== null).assertTrue();
      expect(pickObj(rec('{"a":5}'), 'a') === null).assertTrue(); // 非对象
      expect(pickObj(rec('{"a":null}'), 'a') === null).assertTrue();
      expect(pickObj(rec('{}'), 'a') === null).assertTrue();
    });
  });

  describe('parseSessionSummary', () => {
    it('parses all top-level fields, metadata, summary and todoProgress', 0, () => {
      const s = parseSessionSummary(rec(
        '{"id":"s1","active":true,"thinking":false,"activeAt":100,"updatedAt":200,' +
        '"pendingRequestsCount":2,"backgroundTaskCount":3,"model":"claude-sonnet","effort":"high",' +
        '"metadata":{"name":"My Chat","path":"/work/repo","machineId":"m1","summary":{"text":"doing stuff"},"flavor":"hapi"},' +
        '"todoProgress":{"completed":4,"total":7}}'));
      expect(s.id).assertEqual('s1');
      expect(s.active).assertTrue();
      expect(s.thinking).assertFalse();
      expect(s.activeAt).assertEqual(100);
      expect(s.updatedAt).assertEqual(200);
      expect(s.pendingRequestsCount).assertEqual(2);
      expect(s.backgroundTaskCount).assertEqual(3);
      expect(s.model).assertEqual('claude-sonnet');
      expect(s.effort).assertEqual('high');
      expect(s.todoCompleted).assertEqual(4);
      expect(s.todoTotal).assertEqual(7);
      expect(s.metadata !== null).assertTrue();
      if (s.metadata !== null) {
        expect(s.metadata.name).assertEqual('My Chat');
        expect(s.metadata.path).assertEqual('/work/repo');
        expect(s.metadata.machineId).assertEqual('m1');
        expect(s.metadata.summaryText).assertEqual('doing stuff');
        expect(s.metadata.flavor).assertEqual('hapi');
      }
    });

    it('title prefers metadata.name', 0, () => {
      const s = parseSessionSummary(rec('{"id":"s1","metadata":{"name":"Named","path":"/p"}}'));
      expect(s.title).assertEqual('Named');
    });

    it('title falls back to the last path segment when name is empty', 0, () => {
      const s = parseSessionSummary(rec('{"id":"s1","metadata":{"name":"","path":"/work/repo"}}'));
      expect(s.title).assertEqual('repo');
    });

    it('title returns the whole path when it has no slash', 0, () => {
      const s = parseSessionSummary(rec('{"id":"s1","metadata":{"name":"","path":"repo"}}'));
      expect(s.title).assertEqual('repo');
    });

    it('title falls back to id when name and path are both empty', 0, () => {
      const s = parseSessionSummary(rec('{"id":"sX","metadata":{"name":"","path":""}}'));
      expect(s.title).assertEqual('sX');
    });

    it('title falls back to id when metadata is absent', 0, () => {
      const s = parseSessionSummary(rec('{"id":"sY"}'));
      expect(s.title).assertEqual('sY');
    });

    it('summaryText comes from metadata.summary.text', 0, () => {
      const s = parseSessionSummary(rec('{"id":"s1","metadata":{"summary":{"text":"sum"}}}'));
      expect(s.summaryText).assertEqual('sum');
    });

    it('summaryText is empty when metadata has no summary', 0, () => {
      const s = parseSessionSummary(rec('{"id":"s1","metadata":{"name":"x"}}'));
      expect(s.summaryText).assertEqual('');
    });

    it('summaryText is empty when metadata is absent', 0, () => {
      const s = parseSessionSummary(rec('{"id":"s1"}'));
      expect(s.summaryText).assertEqual('');
    });

    it('leaves todoCompleted/todoTotal at 0 when todoProgress is absent', 0, () => {
      const s = parseSessionSummary(rec('{"id":"s1","metadata":{"name":"x"}}'));
      expect(s.todoCompleted).assertEqual(0);
      expect(s.todoTotal).assertEqual(0);
    });
  });

  describe('parseSessionsResponse', () => {
    it('parses a sessions array', 0, () => {
      const json: string = '{"sessions":[' +
        '{"id":"a","metadata":{"name":"A"}},' +
        '{"id":"b","metadata":{"name":"B"}}' +
        ']}';
      const list = parseSessionsResponse(json);
      expect(list.length).assertEqual(2);
      expect(list[0].id).assertEqual('a');
      expect(list[0].title).assertEqual('A');
      expect(list[1].title).assertEqual('B');
    });

    it('returns an empty array for invalid JSON', 0, () => {
      expect(parseSessionsResponse('not json').length).assertEqual(0);
    });

    it('returns an empty array when sessions is missing', 0, () => {
      expect(parseSessionsResponse('{"foo":1}').length).assertEqual(0);
    });

    it('returns an empty array when sessions is not an array', 0, () => {
      expect(parseSessionsResponse('{"sessions":"nope"}').length).assertEqual(0);
    });

    it('filters out non-object entries', 0, () => {
      const json: string = '{"sessions":["str",123,null,{"id":"ok","metadata":{"name":"OK"}}]}';
      const list = parseSessionsResponse(json);
      expect(list.length).assertEqual(1);
      expect(list[0].id).assertEqual('ok');
    });
  });

  describe('parseSessionDetail', () => {
    it('parses the session envelope with all fields and agentStateRaw', 0, () => {
      const s = parseSessionDetail(
        '{"session":{"id":"s1","namespace":"ns","seq":5,"createdAt":1,"updatedAt":2,' +
        '"active":true,"activeAt":3,"thinking":true,"model":"m","effort":"low","agentStateVersion":9,' +
        '"permissionMode":"plan","collaborationMode":"default","modelReasoningEffort":"xhigh",' +
        '"agentState":{"controlledByUser":true,"requests":{}}}}');
      expect(s.id).assertEqual('s1');
      expect(s.namespace).assertEqual('ns');
      expect(s.seq).assertEqual(5);
      expect(s.createdAt).assertEqual(1);
      expect(s.updatedAt).assertEqual(2);
      expect(s.active).assertTrue();
      expect(s.activeAt).assertEqual(3);
      expect(s.thinking).assertTrue();
      expect(s.model).assertEqual('m');
      expect(s.effort).assertEqual('low');
      expect(s.agentStateVersion).assertEqual(9);
      expect(s.permissionMode).assertEqual('plan');
      expect(s.collaborationMode).assertEqual('default');
      expect(s.modelReasoningEffort).assertEqual('xhigh');
      expect(s.agentStateRaw !== null).assertTrue();
      if (s.agentStateRaw !== null) {
        expect(s.agentStateRaw['controlledByUser']).assertTrue();
      }
    });

    it('returns a default Session for invalid JSON', 0, () => {
      const s = parseSessionDetail('not json');
      expect(s.id).assertEqual('');
      expect(s.agentStateRaw === null).assertTrue();
    });

    it('returns a default Session when the session key is missing', 0, () => {
      const s = parseSessionDetail('{"foo":1}');
      expect(s.id).assertEqual('');
      expect(s.agentStateRaw === null).assertTrue();
    });

    it('leaves nullable fields empty when absent', 0, () => {
      const s = parseSessionDetail('{"session":{"id":"s1"}}');
      expect(s.id).assertEqual('s1');
      expect(s.model).assertEqual('');
      expect(s.effort).assertEqual('');
      expect(s.permissionMode).assertEqual('');
      expect(s.collaborationMode).assertEqual('');
      expect(s.modelReasoningEffort).assertEqual('');
      expect(s.seq).assertEqual(0);
      expect(s.agentStateRaw === null).assertTrue();
    });
  });

  describe('parseMachinesResponse', () => {
    it('parses machines with all fields and displayName from metadata.displayName', 0, () => {
      const list = parseMachinesResponse(
        '{"machines":[' +
        '{"id":"m1","namespace":"ns","active":true,"activeAt":100,"updatedAt":200,"metadata":{"displayName":"My Mac"}}' +
        ']}');
      expect(list.length).assertEqual(1);
      expect(list[0].id).assertEqual('m1');
      expect(list[0].namespace).assertEqual('ns');
      expect(list[0].active).assertTrue();
      expect(list[0].activeAt).assertEqual(100);
      expect(list[0].updatedAt).assertEqual(200);
      expect(list[0].displayName).assertEqual('My Mac');
    });

    it('falls back to metadata.host when displayName is empty', 0, () => {
      const list = parseMachinesResponse(
        '{"machines":[{"id":"m2","metadata":{"displayName":"","host":"host-42"}}]}');
      expect(list[0].displayName).assertEqual('host-42');
    });

    it('leaves displayName empty when metadata is absent', 0, () => {
      const list = parseMachinesResponse('{"machines":[{"id":"m3"}]}');
      expect(list[0].displayName).assertEqual('');
    });

    it('returns an empty array for invalid JSON', 0, () => {
      expect(parseMachinesResponse('not json').length).assertEqual(0);
    });

    it('returns an empty array when machines is missing or not an array', 0, () => {
      expect(parseMachinesResponse('{"foo":1}').length).assertEqual(0);
      expect(parseMachinesResponse('{"machines":"nope"}').length).assertEqual(0);
    });

    it('filters out non-object entries', 0, () => {
      const list = parseMachinesResponse('{"machines":["str",null,{"id":"ok"}]}');
      expect(list.length).assertEqual(1);
      expect(list[0].id).assertEqual('ok');
    });
  });

  describe('parseListDirectoryResponse', () => {
    it('parses entries with name/type/isGitRepo', 0, () => {
      const list = parseListDirectoryResponse(
        '{"entries":[' +
        '{"name":"src","type":"directory","isGitRepo":true},' +
        '{"name":"readme.md","type":"file","isGitRepo":false}' +
        ']}');
      expect(list.length).assertEqual(2);
      expect(list[0].name).assertEqual('src');
      expect(list[0].type).assertEqual('directory');
      expect(list[0].isGitRepo).assertTrue();
      expect(list[1].name).assertEqual('readme.md');
      expect(list[1].type).assertEqual('file');
      expect(list[1].isGitRepo).assertFalse();
    });

    it('defaults type to empty and isGitRepo to false when missing', 0, () => {
      const list = parseListDirectoryResponse('{"entries":[{"name":"x"}]}');
      expect(list[0].type).assertEqual('');
      expect(list[0].isGitRepo).assertFalse();
    });

    it('returns an empty array for invalid JSON', 0, () => {
      expect(parseListDirectoryResponse('not json').length).assertEqual(0);
    });

    it('returns an empty array when entries is missing or not an array', 0, () => {
      expect(parseListDirectoryResponse('{"foo":1}').length).assertEqual(0);
      expect(parseListDirectoryResponse('{"entries":"nope"}').length).assertEqual(0);
    });

    it('filters out non-object entries', 0, () => {
      const list = parseListDirectoryResponse('{"entries":["a",null,{"name":"ok"}]}');
      expect(list.length).assertEqual(1);
      expect(list[0].name).assertEqual('ok');
    });
  });

  describe('parseSpawnResponse', () => {
    it('returns sessionId on success', 0, () => {
      expect(parseSpawnResponse('{"type":"success","sessionId":"s-new"}')).assertEqual('s-new');
    });

    it('throws on error type and surfaces the message', 0, () => {
      let msg: string = '';
      try {
        parseSpawnResponse('{"type":"error","message":"machine offline"}');
      } catch (e) {
        msg = e instanceof Error ? e.message : '';
      }
      expect(msg).assertEqual('machine offline');
    });

    it('throws a generic message on error with empty message', 0, () => {
      let msg: string = '';
      try {
        parseSpawnResponse('{"type":"error","message":""}');
      } catch (e) {
        msg = e instanceof Error ? e.message : '';
      }
      expect(msg).assertEqual('启动会话失败');
    });

    it('throws when sessionId is missing on success', 0, () => {
      let threw: boolean = false;
      try {
        parseSpawnResponse('{"type":"success"}');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('throws on invalid JSON', 0, () => {
      let threw: boolean = false;
      try {
        parseSpawnResponse('not json');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });
  });

  describe('AGENT_FLAVORS / agentDisplayName', () => {
    it('AGENT_FLAVORS matches the upstream list', 0, () => {
      expect(AGENT_FLAVORS.length).assertEqual(6);
      expect(AGENT_FLAVORS[0]).assertEqual('claude');
      expect(AGENT_FLAVORS[5]).assertEqual('opencode');
    });

    it('maps known flavors to display names and passes unknown through', 0, () => {
      expect(agentDisplayName('claude')).assertEqual('Claude Code');
      expect(agentDisplayName('codex')).assertEqual('Codex');
      expect(agentDisplayName('gemini')).assertEqual('Gemini CLI');
      expect(agentDisplayName('unknown')).assertEqual('unknown');
    });
  });

  describe('session config helpers (permission / collaboration / reasoning)', () => {
    it('permissionModesForFlavor routes each flavor to its domain', 0, () => {
      expect(permissionModesForFlavor('claude')[0]).assertEqual('default');
      expect(permissionModesForFlavor('claude')[1]).assertEqual('acceptEdits');
      expect(permissionModesForFlavor('claude').length).assertEqual(4);
      expect(permissionModesForFlavor('codex')[3]).assertEqual('yolo');
      expect(permissionModesForFlavor('gemini')[1]).assertEqual('read-only');
      expect(permissionModesForFlavor('kimi')[1]).assertEqual('read-only');
      expect(permissionModesForFlavor('opencode').length).assertEqual(3);
      expect(permissionModesForFlavor('opencode')[2]).assertEqual('yolo');
      expect(permissionModesForFlavor('cursor')[2]).assertEqual('ask');
      expect(permissionModesForFlavor('whatever')[0]).assertEqual('default'); // 未知回退 claude 域
    });

    it('reasoningEffortsForFlavor picks opencode (max) vs others (xhigh)', 0, () => {
      expect(reasoningEffortsForFlavor('opencode')[3]).assertEqual('max');
      expect(reasoningEffortsForFlavor('codex')[3]).assertEqual('xhigh');
      expect(reasoningEffortsForFlavor('claude')[3]).assertEqual('xhigh'); // 非展示项，仍按 codex 域取
    });

    it('permissionModeDisplayName maps known modes and passes unknown through', 0, () => {
      expect(permissionModeDisplayName('default')).assertEqual('默认');
      expect(permissionModeDisplayName('acceptEdits')).assertEqual('接受编辑');
      expect(permissionModeDisplayName('bypassPermissions')).assertEqual('跳过权限 (Yolo)');
      expect(permissionModeDisplayName('plan')).assertEqual('计划模式');
      expect(permissionModeDisplayName('read-only')).assertEqual('只读');
      expect(permissionModeDisplayName('safe-yolo')).assertEqual('安全 Yolo');
      expect(permissionModeDisplayName('yolo')).assertEqual('Yolo');
      expect(permissionModeDisplayName('ask')).assertEqual('询问模式');
      expect(permissionModeDisplayName('weird')).assertEqual('weird');
    });

    it('collaborationModeDisplayName and reasoningEffortDisplayName', 0, () => {
      expect(collaborationModeDisplayName('default')).assertEqual('默认');
      expect(collaborationModeDisplayName('plan')).assertEqual('计划');
      expect(collaborationModeDisplayName('zzz')).assertEqual('zzz');
      expect(reasoningEffortDisplayName('low')).assertEqual('Low');
      expect(reasoningEffortDisplayName('xhigh')).assertEqual('XHigh');
      expect(reasoningEffortDisplayName('max')).assertEqual('Max');
      expect(reasoningEffortDisplayName('unknown')).assertEqual('unknown');
    });
  });

  describe('parseTeamState', () => {
    it('returns null when raw is null', 0, () => {
      expect(parseTeamState(null) === null).assertTrue();
    });

    it('returns null when teamName is empty (no team)', 0, () => {
      expect(parseTeamState(rec('{"teamName":""}')) === null).assertTrue();
      expect(parseTeamState(rec('{}')) === null).assertTrue();
    });

    it('parses teamName, description, updatedAt with empty sub-arrays when absent', 0, () => {
      const t = parseTeamState(rec('{"teamName":"Squad","description":"a team","updatedAt":99}'));
      expect(t !== null).assertTrue();
      if (t !== null) {
        expect(t.teamName).assertEqual('Squad');
        expect(t.description).assertEqual('a team');
        expect(t.updatedAt).assertEqual(99);
        expect(t.members.length).assertEqual(0);
        expect(t.tasks.length).assertEqual(0);
        expect(t.messages.length).assertEqual(0);
      }
    });

    it('parses members with name/agentType/status', 0, () => {
      const t = parseTeamState(rec(
        '{"teamName":"T","members":[' +
        '{"name":"lead","agentType":"claude","status":"active"},' +
        '{"name":"dev"}' +
        ']}'));
      expect(t !== null).assertTrue();
      if (t !== null) {
        expect(t.members.length).assertEqual(2);
        expect(t.members[0].name).assertEqual('lead');
        expect(t.members[0].agentType).assertEqual('claude');
        expect(t.members[0].status).assertEqual('active');
        expect(t.members[1].name).assertEqual('dev');
        expect(t.members[1].agentType).assertEqual('');
        expect(t.members[1].status).assertEqual('');
      }
    });

    it('parses tasks with id/title/description/status/owner', 0, () => {
      const t = parseTeamState(rec(
        '{"teamName":"T","tasks":[' +
        '{"id":"t1","title":"do thing","status":"in_progress","owner":"dev"},' +
        '{"id":"t2","title":"done","status":"completed"}' +
        ']}'));
      expect(t !== null).assertTrue();
      if (t !== null) {
        expect(t.tasks.length).assertEqual(2);
        expect(t.tasks[0].id).assertEqual('t1');
        expect(t.tasks[0].title).assertEqual('do thing');
        expect(t.tasks[0].status).assertEqual('in_progress');
        expect(t.tasks[0].owner).assertEqual('dev');
        expect(t.tasks[1].description).assertEqual('');
        expect(t.tasks[1].owner).assertEqual('');
      }
    });

    it('parses messages with from/to/summary/type/timestamp', 0, () => {
      const t = parseTeamState(rec(
        '{"teamName":"T","messages":[' +
        '{"from":"lead","to":"dev","summary":"hi","type":"message","timestamp":123}' +
        ']}'));
      expect(t !== null).assertTrue();
      if (t !== null) {
        expect(t.messages.length).assertEqual(1);
        expect(t.messages[0].from).assertEqual('lead');
        expect(t.messages[0].to).assertEqual('dev');
        expect(t.messages[0].summary).assertEqual('hi');
        expect(t.messages[0].type).assertEqual('message');
        expect(t.messages[0].timestamp).assertEqual(123);
      }
    });

    it('treats non-array members/tasks/messages as empty arrays', 0, () => {
      const t = parseTeamState(rec('{"teamName":"T","members":"x","tasks":5,"messages":{}}'));
      expect(t !== null).assertTrue();
      if (t !== null) {
        expect(t.members.length).assertEqual(0);
        expect(t.tasks.length).assertEqual(0);
        expect(t.messages.length).assertEqual(0);
      }
    });

    it('filters out non-object entries in sub-arrays', 0, () => {
      const t = parseTeamState(rec(
        '{"teamName":"T","members":["str",null,{"name":"ok"}]}'));
      expect(t !== null).assertTrue();
      if (t !== null) {
        expect(t.members.length).assertEqual(1);
        expect(t.members[0].name).assertEqual('ok');
      }
    });
  });

  describe('parseTodoList', () => {
    it('returns empty for null or non-array', 0, () => {
      expect(parseTodoList(JSON.parse('null')).length).assertEqual(0);
      expect(parseTodoList(JSON.parse('"notarray"')).length).assertEqual(0);
      expect(parseTodoList(JSON.parse('5')).length).assertEqual(0);
      expect(parseTodoList(JSON.parse('{}')).length).assertEqual(0);
    });

    it('parses full fields content/status/priority/id/activeForm', 0, () => {
      const list = parseTodoList(JSON.parse(
        '[{"content":"重构认证","status":"in_progress","priority":"high","id":"t1","activeForm":"正在重构认证"}]'));
      expect(list.length).assertEqual(1);
      expect(list[0].content).assertEqual('重构认证');
      expect(list[0].status).assertEqual('in_progress');
      expect(list[0].priority).assertEqual('high');
      expect(list[0].id).assertEqual('t1');
      expect(list[0].activeForm).assertEqual('正在重构认证');
    });

    it('requires string content (skips non-string content entries)', 0, () => {
      const list = parseTodoList(JSON.parse(
        '[{"content":"ok","status":"completed"},{"content":5},{"content":null}]'));
      expect(list.length).assertEqual(1);
      expect(list[0].content).assertEqual('ok');
      expect(list[0].status).assertEqual('completed');
    });

    it('defaults priority to medium and normalizes unknown status to pending', 0, () => {
      const list = parseTodoList(JSON.parse(
        '[{"content":"a","priority":"low"},{"content":"b","status":"weird"},{"content":"c"}]'));
      expect(list.length).assertEqual(3);
      expect(list[0].priority).assertEqual('low');
      expect(list[0].status).assertEqual('pending');
      expect(list[1].status).assertEqual('pending');
      expect(list[1].priority).assertEqual('medium');
      expect(list[2].priority).assertEqual('medium');
      expect(list[2].status).assertEqual('pending');
    });

    it('optional id/activeForm default to empty string', 0, () => {
      const list = parseTodoList(JSON.parse('[{"content":"x"}]'));
      expect(list.length).assertEqual(1);
      expect(list[0].id).assertEqual('');
      expect(list[0].activeForm).assertEqual('');
    });

    it('filters out non-object entries in the array', 0, () => {
      const list = parseTodoList(JSON.parse('["str",null,5,{"content":"keep"}]'));
      expect(list.length).assertEqual(1);
      expect(list[0].content).assertEqual('keep');
    });
  });

  // ThreadGoal（codex 持久目标，对照 shared/src/schemas.ts:150-164 + normalizeAgent.ts:35-52）。
  describe('parseThreadGoal', () => {
    it('合法 camelCase 全字段 → 返 ThreadGoal', 0, () => {
      const g = parseThreadGoal(rec(
        '{"threadId":"t1","objective":"ship it","status":"active","tokenBudget":5000,"tokensUsed":1200,' +
        '"timeUsedSeconds":42,"createdAt":1700000000000,"updatedAt":1700000001000}'));
      expect(g).assertNotNull();
      expect(g!.threadId).assertEqual('t1');
      expect(g!.objective).assertEqual('ship it');
      expect(g!.status).assertEqual('active');
      expect(g!.tokenBudget).assertEqual(5000);
      expect(g!.tokensUsed).assertEqual(1200);
      expect(g!.timeUsedSeconds).assertEqual(42);
      expect(g!.createdAt).assertEqual(1700000000000);
      expect(g!.updatedAt).assertEqual(1700000001000);
    });
    it('snake_case 双向容错', 0, () => {
      const g = parseThreadGoal(rec(
        '{"thread_id":"t2","objective":"o","status":"complete","token_budget":1000,"tokens_used":10,' +
        '"time_used_seconds":5,"created_at":1,"updated_at":2}'));
      expect(g).assertNotNull();
      expect(g!.threadId).assertEqual('t2');
      expect(g!.tokenBudget).assertEqual(1000);
      expect(g!.tokensUsed).assertEqual(10);
      expect(g!.timeUsedSeconds).assertEqual(5);
      expect(g!.createdAt).assertEqual(1);
      expect(g!.updatedAt).assertEqual(2);
      expect(g!.status).assertEqual('complete');
    });
    it('status 四值合法（active/paused/budgetLimited/complete）', 0, () => {
      const statuses: string[] = ['active', 'paused', 'budgetLimited', 'complete'];
      for (let i = 0; i < statuses.length; i++) {
        const s = statuses[i];
        const g = parseThreadGoal(rec('{"threadId":"t","objective":"o","status":"' + s + '"}'));
        expect(g).assertNotNull();
        expect(g!.status).assertEqual(s);
      }
    });
    it('缺 threadId/objective/status 任一 → null', 0, () => {
      expect(parseThreadGoal(rec('{"objective":"o","status":"active"}'))).assertNull();    // 无 threadId
      expect(parseThreadGoal(rec('{"threadId":"t","status":"active"}'))).assertNull();     // 无 objective
      expect(parseThreadGoal(rec('{"threadId":"t","objective":"o"}'))).assertNull();       // 无 status
    });
    it('status 非四值之一 → null', 0, () => {
      expect(parseThreadGoal(rec('{"threadId":"t","objective":"o","status":"running"}'))).assertNull();
      expect(parseThreadGoal(rec('{"threadId":"t","objective":"o","status":""}'))).assertNull();
    });
    it('tokenBudget 缺省 → -1 哨兵（上游 nullable）；其余数值缺省 0', 0, () => {
      const g = parseThreadGoal(rec('{"threadId":"t","objective":"o","status":"active"}'));
      expect(g).assertNotNull();
      expect(g!.tokenBudget).assertEqual(-1);
      expect(g!.tokensUsed).assertEqual(0);
      expect(g!.timeUsedSeconds).assertEqual(0);
    });
    it('非对象输入 → null', 0, () => {
      expect(parseThreadGoal(JSON.parse('null') as Record<string, Object>)).assertNull();
      expect(parseThreadGoal(JSON.parse('5') as Record<string, Object>)).assertNull();
    });
  });

  describe('Files 浏览 parse', () => {
    it('parseFileSearchResponse parses items + filters non-objects', 0, () => {
      const list = parseFileSearchResponse(
        '{"success":true,"files":[' +
        '{"fileName":"foo.ts","filePath":"src","fullPath":"src/foo.ts","fileType":"file"},' +
        '"bad",null,' +
        '{"fileName":"bar","filePath":"","fullPath":"bar","fileType":"folder"}' +
        ']}');
      expect(list.length).assertEqual(2);
      expect(list[0].fileName).assertEqual('foo.ts');
      expect(list[0].fullPath).assertEqual('src/foo.ts');
      expect(list[0].fileType).assertEqual('file');
      expect(list[1].fileType).assertEqual('folder');
    });

    it('parseFileSearchResponse returns empty for missing/invalid', 0, () => {
      expect(parseFileSearchResponse('not json').length).assertEqual(0);
      expect(parseFileSearchResponse('{"success":false}').length).assertEqual(0);   // 无 files 键
      expect(parseFileSearchResponse('{"files":"nope"}').length).assertEqual(0);     // 非数组
    });

    it('parseCommandResponse parses success + stdout + exitCode', 0, () => {
      const c = parseCommandResponse('{"success":true,"stdout":"1 .M N...","stderr":"","exitCode":0}');
      expect(c.success).assertTrue();
      expect(c.stdout).assertEqual('1 .M N...');
      expect(c.exitCode).assertEqual(0);
    });

    it('parseCommandResponse carries error + -1 sentinel exitCode', 0, () => {
      const c = parseCommandResponse('{"success":false,"error":"not a git repo"}');
      expect(c.success).assertFalse();
      expect(c.error).assertEqual('not a git repo');
      expect(c.exitCode).assertEqual(-1);   // 缺省 -1 哨兵
    });

    it('parseCommandResponse returns failure shell for invalid JSON', 0, () => {
      const c = parseCommandResponse('xxx');
      expect(c.success).assertFalse();
      expect(c.stdout).assertEqual('');
    });

    it('parseFileReadResponse parses base64 content', 0, () => {
      const f = parseFileReadResponse('{"success":true,"content":"aGVsbG8="}');
      expect(f.success).assertTrue();
      expect(f.content).assertEqual('aGVsbG8=');
    });

    it('parseFileReadResponse carries error', 0, () => {
      const f = parseFileReadResponse('{"success":false,"error":"too large"}');
      expect(f.success).assertFalse();
      expect(f.error).assertEqual('too large');
      expect(f.content).assertEqual('');
    });

    it('parseSessionDirectoryResponse parses entries + -1 sentinel size/modified', 0, () => {
      const list = parseSessionDirectoryResponse(
        '{"success":true,"entries":[' +
        '{"name":"src","type":"directory","size":0,"modified":1700000000000},' +
        '{"name":"readme.md","type":"file"}' +
        ']}');
      expect(list.length).assertEqual(2);
      expect(list[0].name).assertEqual('src');
      expect(list[0].type).assertEqual('directory');
      expect(list[0].modified).assertEqual(1700000000000);
      expect(list[1].name).assertEqual('readme.md');
      expect(list[1].size).assertEqual(-1);    // 缺省 -1 哨兵
      expect(list[1].modified).assertEqual(-1);
    });

    it('parseSessionDirectoryResponse returns empty for missing/invalid', 0, () => {
      expect(parseSessionDirectoryResponse('not json').length).assertEqual(0);
      expect(parseSessionDirectoryResponse('{"foo":1}').length).assertEqual(0);
      expect(parseSessionDirectoryResponse('{"entries":"x"}').length).assertEqual(0);
    });
  });

  describe('附件上传 parse', () => {
    it('parseUploadFileResponse parses success + path', 0, () => {
      const r = parseUploadFileResponse('{"success":true,"path":"/tmp/up/abc.png"}');
      expect(r.success).assertTrue();
      expect(r.path).assertEqual('/tmp/up/abc.png');
      expect(r.error).assertEqual('');
    });

    it('parseUploadFileResponse carries error on failure', 0, () => {
      const r = parseUploadFileResponse('{"success":false,"error":"file too large"}');
      expect(r.success).assertFalse();
      expect(r.error).assertEqual('file too large');
      expect(r.path).assertEqual('');
    });

    it('parseUploadFileResponse returns failure shell for invalid JSON', 0, () => {
      const r = parseUploadFileResponse('xxx');
      expect(r.success).assertFalse();
      expect(r.path).assertEqual('');
    });
  });

  describe('pickStrArr — 安全取字符串数组', () => {
    it('正常字符串数组', 0, () => {
      const r = rec('{"k":["a","b"]}');
      const arr = pickStrArr(r, 'k');
      expect(arr.length).assertEqual(2);
      expect(arr[0]).assertEqual('a');
      expect(arr[1]).assertEqual('b');
    });
    it('缺键 → []', 0, () => {
      expect(pickStrArr(rec('{}'), 'k').length).assertEqual(0);
    });
    it('非数组 → []', 0, () => {
      expect(pickStrArr(rec('{"k":"x"}'), 'k').length).assertEqual(0);
      expect(pickStrArr(rec('{"k":123}'), 'k').length).assertEqual(0);
    });
    it('混合元素：仅取 string，丢非 string', 0, () => {
      const arr = pickStrArr(rec('{"k":["a",1,true,"b"]}'), 'k');
      // 非字符串元素被过滤（手写校验逐元素 typeof）
      expect(arr.length).assertEqual(2);
      expect(arr[0]).assertEqual('a');
      expect(arr[1]).assertEqual('b');
    });
  });

  describe('parseSlashCommandsResponse — 服务端斜杠命令', () => {
    it('success + commands 数组 → 逐项映射（缺 source 归 user）', 0, () => {
      const json = '{"success":true,"commands":[{"name":"foo","description":"d","content":"x"},{"name":"bar"}]}';
      const r = parseSlashCommandsResponse(json);
      expect(r.length).assertEqual(2);
      expect(r[0].name).assertEqual('foo');
      expect(r[0].description).assertEqual('d');
      expect(r[0].content).assertEqual('x');
      expect(r[1].name).assertEqual('bar');
      expect(r[1].source).assertEqual('user');   // 缺省归 user
    });
    it('success=false → []', 0, () => {
      expect(parseSlashCommandsResponse('{"success":false}').length).assertEqual(0);
    });
    it('无 commands 字段 → []', 0, () => {
      expect(parseSlashCommandsResponse('{"success":true}').length).assertEqual(0);
    });
    it('非法 JSON → []', 0, () => {
      expect(parseSlashCommandsResponse('xxx').length).assertEqual(0);
    });
    it('元素非对象被跳过', 0, () => {
      const json = '{"success":true,"commands":["str",123,{"name":"ok"}]}';
      const r = parseSlashCommandsResponse(json);
      expect(r.length).assertEqual(1);
      expect(r[0].name).assertEqual('ok');
    });
  });

  describe('parseSkillsResponse — 技能列表', () => {
    it('success + skills 数组 → SkillItem[]', 0, () => {
      const json = '{"success":true,"skills":[{"name":"git","description":"g"},{"name":"deploy"}]}';
      const r = parseSkillsResponse(json);
      expect(r.length).assertEqual(2);
      expect(r[0].name).assertEqual('git');
      expect(r[0].description).assertEqual('g');
      expect(r[1].name).assertEqual('deploy');
    });
    it('success=false → []', 0, () => {
      expect(parseSkillsResponse('{"success":false,"skills":[]}').length).assertEqual(0);
    });
    it('无 skills 字段 → []', 0, () => {
      expect(parseSkillsResponse('{"success":true}').length).assertEqual(0);
    });
    it('非法 JSON → []', 0, () => {
      expect(parseSkillsResponse('not json').length).assertEqual(0);
    });
  });

  describe('parseCodexModelsResponse', () => {
    it('解析 models → ModelOption[]（label=displayName，缺 displayName 回落 id）', 0, () => {
      const r = parseCodexModelsResponse(
        '{"models":[' +
        '{"id":"gpt-5","displayName":"GPT-5","isDefault":true},' +
        '{"id":"o3"}' +
        ']}');
      expect(r.length).assertEqual(2);
      expect(r[0].id).assertEqual('gpt-5');
      expect(r[0].label).assertEqual('GPT-5');
      expect(r[1].id).assertEqual('o3');
      expect(r[1].label).assertEqual('o3');   // 缺 displayName → 回落 id
    });

    it('过滤空 id 与 auto（UI 自加「默认」=auto 项，避免重复）', 0, () => {
      const r = parseCodexModelsResponse(
        '{"models":[{"id":"","displayName":"空"},{"id":"auto"},{"id":"real"}]}');
      expect(r.length).assertEqual(1);
      expect(r[0].id).assertEqual('real');
    });

    it('非法 JSON → []', 0, () => {
      expect(parseCodexModelsResponse('not json').length).assertEqual(0);
    });

    it('缺 models / 非数组 → []', 0, () => {
      expect(parseCodexModelsResponse('{"foo":1}').length).assertEqual(0);
      expect(parseCodexModelsResponse('{"models":"nope"}').length).assertEqual(0);
    });

    it('过滤非对象项', 0, () => {
      const r = parseCodexModelsResponse('{"models":["a",null,{"id":"ok"}]}');
      expect(r.length).assertEqual(1);
      expect(r[0].id).assertEqual('ok');
    });
  });

  describe('parseOpencodeModelsResponse', () => {
    it('解析 availableModels → ModelOption[]（id=modelId，label=name ?? modelId）', 0, () => {
      const r = parseOpencodeModelsResponse(
        '{"availableModels":[' +
        '{"modelId":"anthropic/claude","name":"Claude"},' +
        '{"modelId":"openai/gpt"}' +
        '],"currentModelId":"anthropic/claude"}');
      expect(r.length).assertEqual(2);
      expect(r[0].id).assertEqual('anthropic/claude');
      expect(r[0].label).assertEqual('Claude');
      expect(r[1].id).assertEqual('openai/gpt');
      expect(r[1].label).assertEqual('openai/gpt');   // 缺 name → 回落 modelId
    });

    it('过滤空 modelId 与 auto', 0, () => {
      const r = parseOpencodeModelsResponse(
        '{"availableModels":[{"modelId":""},{"modelId":"auto"},{"modelId":"real"}]}');
      expect(r.length).assertEqual(1);
      expect(r[0].id).assertEqual('real');
    });

    it('非法 JSON → []', 0, () => {
      expect(parseOpencodeModelsResponse('not json').length).assertEqual(0);
    });

    it('缺 availableModels / 非数组 → []', 0, () => {
      expect(parseOpencodeModelsResponse('{"foo":1}').length).assertEqual(0);
      expect(parseOpencodeModelsResponse('{"availableModels":"nope"}').length).assertEqual(0);
    });

    it('过滤非对象项', 0, () => {
      const r = parseOpencodeModelsResponse('{"availableModels":["a",null,{"modelId":"ok"}]}');
      expect(r.length).assertEqual(1);
      expect(r[0].id).assertEqual('ok');
    });
  });
}
