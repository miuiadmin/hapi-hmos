// CodexAgents 单测 —— 对照 web/src/components/ToolCard/codexAgents.ts。
//   覆盖 6 子代理工具的入参/结果解析 + 文案 helper：getCodexAgentPrompt/Summary/Activity/Type/Targets/
//   ReasoningEffortLabel/FieldRows、3 个 parse*Result、summarizeCodexAgentResult。
//   input 用 JSON.parse(json) as Record<string,Object> 构造（避嵌套字面量类型坑，同 AgentState 范式）。
//   文案随 i18n locale——显式 setTranslateLocale('zh-CN') 钉死断言中文（reasoning effort / state 等裸英 loanword 不译）。

import { describe, it, expect } from '@ohos/hypium';
import {
  getCodexAgentPrompt,
  getCodexAgentSummary,
  getCodexAgentActivity,
  getCodexAgentType,
  getCodexAgentTargets,
  getCodexAgentReasoningEffortLabel,
  getCodexAgentFieldRows,
  parseCodexSpawnAgentResult,
  parseCodexWaitAgentResult,
  parseCodexCloseAgentResult,
  summarizeCodexAgentResult
} from '../main/ets/chat/CodexAgents';
import { setTranslateLocale } from '../main/ets/i18n/Translate';

function rec(json: string): Record<string, Object> {
  return JSON.parse(json) as Record<string, Object>;
}

export default function codexAgentsTest(): void {
  setTranslateLocale('zh-CN');

  describe('getCodexAgentPrompt', () => {
    it('message 直取', 0, () => {
      expect(getCodexAgentPrompt(rec('{"message":"hello world"}'))).assertEqual('hello world');
    });
    it('prompt 直取', 0, () => {
      expect(getCodexAgentPrompt(rec('{"prompt":"do the thing"}'))).assertEqual('do the thing');
    });
    it('message 优先于 prompt', 0, () => {
      expect(getCodexAgentPrompt(rec('{"message":"m","prompt":"p"}'))).assertEqual('m');
    });
    it('items[].text 以空行拼接（滤空/非串）', 0, () => {
      const input = rec('{"items":[{"text":"a"},{"x":1},{"text":"   "},{"text":"b"}]}');
      expect(getCodexAgentPrompt(input)).assertEqual('a\n\nb');
    });
    it('null → 空', 0, () => {
      expect(getCodexAgentPrompt(null)).assertEqual('');
    });
    it('空对象 → 空', 0, () => {
      expect(getCodexAgentPrompt(rec('{}'))).assertEqual('');
    });
  });

  describe('getCodexAgentSummary', () => {
    it('显式 summary → 折叠截 80（短串原样）', 0, () => {
      expect(getCodexAgentSummary(rec('{"summary":"Fix the bug"}'))).assertEqual('Fix the bug');
    });
    it('显式 title 回退', 0, () => {
      expect(getCodexAgentSummary(rec('{"title":"My Title"}'))).assertEqual('My Title');
    });
    it('prompt 回退：剥 "Task:" 前缀 label', 0, () => {
      // cleanAgentPromptForSummary 剥 ^task:\s* label（手写扫描器，忠实上游 /^(task|...)\s*[:：]\s*/i）
      expect(getCodexAgentSummary(rec('{"message":"Task: implement feature X"}'))).assertEqual('implement feature X');
    });
    it('type 回退 → {type} agent', 0, () => {
      expect(getCodexAgentSummary(rec('{"type":"researcher"}'))).assertEqual('researcher agent');
    });
    it('null → 空', 0, () => {
      expect(getCodexAgentSummary(null)).assertEqual('');
    });
  });

  describe('getCodexAgentActivity', () => {
    it('终态状态 → 不归一（原样返回）', 0, () => {
      // status=completed 终态 → activity 原样，不走 normalize
      const input = rec('{"activity":"Command completed: foo","status":"completed"}');
      expect(getCodexAgentActivity(input)).assertEqual('Command completed: foo');
    });
    it('Command completed: → Command finished:（非终态归一）', 0, () => {
      // 无 status → 非终态 → normalize：^Command completed\b → Command finished
      expect(getCodexAgentActivity(rec('{"activity":"Command completed: foo"}'))).assertEqual('Command finished: foo');
    });
    it('Completed: → Output ready:（非终态归一）', 0, () => {
      expect(getCodexAgentActivity(rec('{"activity":"Completed: bar"}'))).assertEqual('Output ready: bar');
    });
    it('整串 Completed → Running', 0, () => {
      expect(getCodexAgentActivity(rec('{"activity":"Completed"}'))).assertEqual('Running');
    });
    it('普通活动文案 → 原样（无前缀命中）', 0, () => {
      expect(getCodexAgentActivity(rec('{"activity":"Thinking"}'))).assertEqual('Thinking');
    });
    it('null → 空', 0, () => {
      expect(getCodexAgentActivity(null)).assertEqual('');
    });
  });

  describe('getCodexAgentType', () => {
    it('agent_type', 0, () => {
      expect(getCodexAgentType(rec('{"agent_type":"researcher"}'))).assertEqual('researcher');
    });
    it('subagent_type 回退', 0, () => {
      expect(getCodexAgentType(rec('{"subagent_type":"analyst"}'))).assertEqual('analyst');
    });
    it('type 回退', 0, () => {
      expect(getCodexAgentType(rec('{"type":"generic"}'))).assertEqual('generic');
    });
    it('null → 空', 0, () => {
      expect(getCodexAgentType(null)).assertEqual('');
    });
  });

  describe('getCodexAgentTargets', () => {
    it('targets[] 滤串', 0, () => {
      const out: string[] = getCodexAgentTargets(rec('{"targets":["a","b"]}'));
      expect(out.length).assertEqual(2);
      expect(out[0]).assertEqual('a');
      expect(out[1]).assertEqual('b');
    });
    it('targets 含非串 → 滤除（仅留串）', 0, () => {
      const out: string[] = getCodexAgentTargets(rec('{"targets":[123,"a"]}'));
      expect(out.length).assertEqual(1);
      expect(out[0]).assertEqual('a');
    });
    it('targets 空/缺 → 回退 target 直取', 0, () => {
      const out: string[] = getCodexAgentTargets(rec('{"targets":[],"target":"x"}'));
      expect(out.length).assertEqual(1);
      expect(out[0]).assertEqual('x');
    });
    it('id 回退', 0, () => {
      const out: string[] = getCodexAgentTargets(rec('{"id":"i1"}'));
      expect(out.length).assertEqual(1);
      expect(out[0]).assertEqual('i1');
    });
    it('null → 空数组', 0, () => {
      expect(getCodexAgentTargets(null).length).assertEqual(0);
    });
  });

  describe('getCodexAgentReasoningEffortLabel', () => {
    it('high → reasoning high（裸英 loanword 不译）', 0, () => {
      expect(getCodexAgentReasoningEffortLabel(rec('{"reasoning_effort":"high"}'))).assertEqual('reasoning high');
    });
    it('default → reasoning default', 0, () => {
      expect(getCodexAgentReasoningEffortLabel(rec('{"reasoning_effort":"default"}'))).assertEqual('reasoning default');
    });
    it('camelCase reasoningEffort', 0, () => {
      expect(getCodexAgentReasoningEffortLabel(rec('{"reasoningEffort":"low"}'))).assertEqual('reasoning low');
    });
    it('空 → 空', 0, () => {
      expect(getCodexAgentReasoningEffortLabel(rec('{}'))).assertEqual('');
    });
  });

  describe('getCodexAgentFieldRows', () => {
    it('全字段 → 顺序 Agent/Status/Work/Type/Model/Reasoning/Fork/Timeout/Targets', 0, () => {
      const input = rec('{"agentId":"a1","activity":"Thinking","summary":"Do work","type":"researcher","model":"gpt-5","reasoning_effort":"high","fork_context":true,"timeout_ms":30000,"targets":["t1","t2"]}');
      const rows = getCodexAgentFieldRows('CodexAgent', input);
      expect(rows.length).assertEqual(9);
      // 顺序标签（本地化）
      expect(rows[0].label).assertEqual('代理');      // Agent
      expect(rows[0].value).assertEqual('a1');
      expect(rows[1].label).assertEqual('状态');      // Status
      expect(rows[1].value).assertEqual('Thinking');
      expect(rows[2].label).assertEqual('任务');      // Work
      expect(rows[2].value).assertEqual('Do work');
      expect(rows[3].label).assertEqual('类型');      // Type
      expect(rows[3].value).assertEqual('researcher');
      expect(rows[4].label).assertEqual('模型');      // Model
      expect(rows[4].value).assertEqual('gpt-5');
      expect(rows[5].label).assertEqual('推理');      // Reasoning（裸 effort 值）
      expect(rows[5].value).assertEqual('high');
      expect(rows[6].label).assertEqual('分支上下文'); // Fork context
      expect(rows[6].value).assertEqual('true');
      expect(rows[7].label).assertEqual('超时');      // Timeout
      expect(rows[7].value).assertEqual('30000 ms');
      expect(rows[8].label).assertEqual('目标');      // Targets（多→targets）
      expect(rows[8].value).assertEqual('t1, t2');
    });
    it('resume_agent 单 target → 标签「代理」（非「目标」）', 0, () => {
      const rows = getCodexAgentFieldRows('resume_agent', rec('{"targets":["x"]}'));
      expect(rows.length).assertEqual(1);
      expect(rows[0].label).assertEqual('代理');
      expect(rows[0].value).assertEqual('x');
    });
    it('非 resume 单 target → 标签「目标」', 0, () => {
      const rows = getCodexAgentFieldRows('send_input', rec('{"targets":["x"]}'));
      expect(rows.length).assertEqual(1);
      expect(rows[0].label).assertEqual('目标');
    });
    it('timeout_ms → {n} ms', 0, () => {
      const rows = getCodexAgentFieldRows('CodexAgent', rec('{"timeout_ms":5000}'));
      expect(rows.length).assertEqual(1);
      expect(rows[0].value).assertEqual('5000 ms');
    });
    it('空对象 → 0 行', 0, () => {
      expect(getCodexAgentFieldRows('CodexAgent', rec('{}')).length).assertEqual(0);
    });
    it('null input → 0 行', 0, () => {
      expect(getCodexAgentFieldRows('CodexAgent', null).length).assertEqual(0);
    });
  });

  describe('parseCodexSpawnAgentResult', () => {
    it('典型对象（agent_id + nickname）', 0, () => {
      const r = parseCodexSpawnAgentResult(rec('{"agent_id":"a1","nickname":"Bob"}'));
      expect(r === null).assertFalse();
      expect(r!.agentId).assertEqual('a1');
      expect(r!.nickname).assertEqual('Bob');
    });
    it('JSON 串（camelCase：agentId + name）', 0, () => {
      const r = parseCodexSpawnAgentResult('{"agentId":"a2","name":"Carol"}');
      expect(r === null).assertFalse();
      expect(r!.agentId).assertEqual('a2');
      expect(r!.nickname).assertEqual('Carol');
    });
    it('仅 id（id 键）→ nickname 空', 0, () => {
      const r = parseCodexSpawnAgentResult(rec('{"id":"a3"}'));
      expect(r === null).assertFalse();
      expect(r!.agentId).assertEqual('a3');
      expect(r!.nickname).assertEqual('');
    });
    it('空对象 → null（两者皆空）', 0, () => {
      expect(parseCodexSpawnAgentResult(rec('{}')) === null).assertTrue();
    });
    it('null → null', 0, () => {
      expect(parseCodexSpawnAgentResult(null) === null).assertTrue();
    });
    it('非 JSON 串 → null', 0, () => {
      expect(parseCodexSpawnAgentResult('not an object') === null).assertTrue();
    });
  });

  describe('parseCodexWaitAgentResult', () => {
    it('典型：status 映射 + timed_out=false', 0, () => {
      const r = parseCodexWaitAgentResult(rec('{"status":{"a1":{"completed":"done"},"a2":{"failed":"oops"}},"timed_out":false}'));
      expect(r === null).assertFalse();
      expect(r!.statuses.length).assertEqual(2);
      expect(r!.statuses[0].agentId).assertEqual('a1');
      expect(r!.statuses[0].state).assertEqual('completed');
      expect(r!.statuses[0].text).assertEqual('done');
      expect(r!.statuses[1].agentId).assertEqual('a2');
      expect(r!.statuses[1].state).assertEqual('failed');
      expect(r!.statuses[1].text).assertEqual('oops');
      expect(r!.timedOut).assertFalse();
    });
    it('JSON 串 + camelCase timedOut', 0, () => {
      const r = parseCodexWaitAgentResult('{"status":{"x":{"completed":"go"}},"timedOut":true}');
      expect(r === null).assertFalse();
      expect(r!.statuses.length).assertEqual(1);
      expect(r!.statuses[0].state).assertEqual('completed');
      expect(r!.timedOut).assertTrue();
    });
    it('仅 timed_out（0 状态）→ 非 null，timedOut=true', 0, () => {
      const r = parseCodexWaitAgentResult(rec('{"timed_out":true}'));
      expect(r === null).assertFalse();
      expect(r!.statuses.length).assertEqual(0);
      expect(r!.timedOut).assertTrue();
    });
    it('空对象 → null（无状态无超时）', 0, () => {
      expect(parseCodexWaitAgentResult(rec('{}')) === null).assertTrue();
    });
    it('null → null', 0, () => {
      expect(parseCodexWaitAgentResult(null) === null).assertTrue();
    });
  });

  describe('parseCodexCloseAgentResult', () => {
    it('典型：previous_status（completed）', 0, () => {
      const r = parseCodexCloseAgentResult(rec('{"previous_status":{"completed":"ok"}}'));
      expect(r === null).assertFalse();
      expect(r!.agentId).assertEqual('');
      expect(r!.state).assertEqual('completed');
      expect(r!.text).assertEqual('ok');
    });
    it('JSON 串 + camelCase previousStatus（failed）', 0, () => {
      const r = parseCodexCloseAgentResult('{"previousStatus":{"failed":"err"}}');
      expect(r === null).assertFalse();
      expect(r!.state).assertEqual('failed');
      expect(r!.text).assertEqual('err');
    });
    it('无 previous_status → null', 0, () => {
      expect(parseCodexCloseAgentResult(rec('{"foo":"bar"}')) === null).assertTrue();
    });
    it('null → null', 0, () => {
      expect(parseCodexCloseAgentResult(null) === null).assertTrue();
    });
  });

  describe('summarizeCodexAgentResult', () => {
    it('spawn nickname+id → 已启动 {label}', 0, () => {
      expect(summarizeCodexAgentResult('spawn_agent', rec('{"agent_id":"a1","nickname":"Bob"}'))).assertEqual('已启动 Bob (a1)');
    });
    it('spawn 仅 id → 已启动 {id}', 0, () => {
      expect(summarizeCodexAgentResult('spawn_agent', rec('{"agent_id":"a1"}'))).assertEqual('已启动 a1');
    });
    it('spawn 空 → 空（parse null）', 0, () => {
      expect(summarizeCodexAgentResult('spawn_agent', rec('{}'))).assertEqual('');
    });
    it('wait 0 状态+超时 → 已超时', 0, () => {
      expect(summarizeCodexAgentResult('wait_agent', rec('{"timed_out":true}'))).assertEqual('已超时');
    });
    it('wait 多状态 → N 个完成, N 个未完成', 0, () => {
      const result = rec('{"status":{"a1":{"completed":"done"},"a2":{"failed":"x"}}}');
      expect(summarizeCodexAgentResult('wait_agent', result)).assertEqual('1 个完成, 1 个未完成');
    });
    it('wait 全完成 → 仅 N 个完成', 0, () => {
      expect(summarizeCodexAgentResult('wait_agent', rec('{"status":{"a1":{"completed":"done"}}}'))).assertEqual('1 个完成');
    });
    it('wait 空对象 → 空（parse null）', 0, () => {
      expect(summarizeCodexAgentResult('wait_agent', rec('{}'))).assertEqual('');
    });
    it('close → 已关闭（{state}）', 0, () => {
      expect(summarizeCodexAgentResult('close_agent', rec('{"previous_status":{"completed":"ok"}}'))).assertEqual('已关闭（completed）');
    });
    it('close 无 previous_status → 空', 0, () => {
      expect(summarizeCodexAgentResult('close_agent', rec('{}'))).assertEqual('');
    });
    it('send_input / resume_agent / CodexAgent → 空', 0, () => {
      expect(summarizeCodexAgentResult('send_input', rec('{"x":1}'))).assertEqual('');
      expect(summarizeCodexAgentResult('resume_agent', rec('{"x":1}'))).assertEqual('');
      expect(summarizeCodexAgentResult('CodexAgent', rec('{"x":1}'))).assertEqual('');
    });
  });
}
