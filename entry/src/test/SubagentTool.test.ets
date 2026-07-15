// SubagentTool 单测 —— 子代理调用工具判定纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 SessionGrouping.test / TerminalToolDisplay.test 范式：同步断言（assertEqual / ===）。
//   覆盖 isSubagentToolName 各分支（Task/Agent 精确 + 'Agent:'/'Task:' 前缀 + 大小写敏感 + 非匹配），
//   对照上游 chat/subagentTool.ts:isSubagentToolName 语义。

import { describe, it, expect } from '@ohos/hypium';
import { isSubagentToolName } from '../main/ets/chat/SubagentTool';

export default function subagentToolTest(): void {
  describe('SubagentTool — isSubagentToolName（精确名匹配）', () => {
    it("'Task' → true", 0, () => {
      expect(isSubagentToolName('Task')).assertTrue();
    });
    it("'Agent' → true", 0, () => {
      expect(isSubagentToolName('Agent')).assertTrue();
    });
  });

  describe('SubagentTool — isSubagentToolName（带前缀变体）', () => {
    it("'Agent:researcher' → true（Agent: 前缀）", 0, () => {
      expect(isSubagentToolName('Agent:researcher')).assertTrue();
    });
    it("'Task:builder' → true（Task: 前缀）", 0, () => {
      expect(isSubagentToolName('Task:builder')).assertTrue();
    });
    it("'Agent:' 空 suffix → true（仅前缀也匹配）", 0, () => {
      expect(isSubagentToolName('Agent:')).assertTrue();
    });
  });

  describe('SubagentTool — isSubagentToolName（非匹配）', () => {
    it("'Bash' → false（普通工具）", 0, () => {
      expect(isSubagentToolName('Bash')).assertFalse();
    });
    it("'' 空串 → false", 0, () => {
      expect(isSubagentToolName('')).assertFalse();
    });
    it("'agent' 小写 → false（大小写敏感）", 0, () => {
      expect(isSubagentToolName('agent')).assertFalse();
    });
    it("'task' 小写 → false（大小写敏感）", 0, () => {
      expect(isSubagentToolName('task')).assertFalse();
    });
    it("'Taskforce' → false（非精确 Task，无 Task: 前缀）", 0, () => {
      expect(isSubagentToolName('Taskforce')).assertFalse();
    });
    it("'MyAgent' → false（非精确 Agent，无 Agent: 前缀）", 0, () => {
      expect(isSubagentToolName('MyAgent')).assertFalse();
    });
    it("'spawn_agent' → false（Codex agent-run，非 Task/Agent 工具名）", 0, () => {
      expect(isSubagentToolName('spawn_agent')).assertFalse();
    });
  });
}
