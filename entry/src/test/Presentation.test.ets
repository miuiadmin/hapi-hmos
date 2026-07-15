// Presentation 单测 —— 对照 web/src/components/ToolCard/knownTools.tsx getToolPresentation。
//   覆盖本批补齐的 4 个 Codex/蛇形工具：CodexBash（parsed_cmd 图标/标题/minimal）、
//   shell_command/run_shell_command、CodexPatch（changes 文件名）、CodexPermission（tool/message）。
//   外加回归：Bash/Read/未知工具 default 分支不变。
//   input 用 JSON.parse(json) as Record<string,Object> 构造（避 ArkTS 嵌套字面量类型坑，同 AgentState/Checklist 范式）。
//   文案随 i18n locale——显式 setTranslateLocale('zh-CN') 钉死断言中文。

import { describe, it, expect } from '@ohos/hypium';
import { getToolPresentation } from '../main/ets/chat/Presentation';
import { ChatToolCall } from '../main/ets/chat/ChatBlock';
import { setTranslateLocale } from '../main/ets/i18n/Translate';

function rec(json: string): Record<string, Object> {
  return JSON.parse(json) as Record<string, Object>;
}

function mk(name: string, input: Record<string, Object> | null, result: Object | null, desc: string): ChatToolCall {
  const tool: ChatToolCall = new ChatToolCall();
  tool.name = name;
  tool.input = input;
  tool.result = result;
  tool.description = desc;
  return tool;
}

export default function presentationTest(): void {
  setTranslateLocale('zh-CN');

  describe('getToolPresentation — CodexBash', () => {
    it('read 单 cmd → 👁️ + 文件名标题 + 命令 subtitle + minimal true（无输出）', 0, () => {
      const input = rec('{"parsed_cmd":[{"type":"read","name":"src/foo.ts"}],"command":"cat src/foo.ts"}');
      const p = getToolPresentation(mk('CodexBash', input, null, ''));
      expect(p.icon).assertEqual('👁️');
      expect(p.title).assertEqual('src/foo.ts');
      expect(p.subtitle).assertEqual('cat src/foo.ts');
      expect(p.minimal).assertTrue();
    });
    it('write cmd → 📝（非 read，标题 desc??终端）', 0, () => {
      const input = rec('{"parsed_cmd":[{"type":"write","name":"bar.txt"}],"command":"echo x > bar.txt"}');
      const p = getToolPresentation(mk('CodexBash', input, null, ''));
      expect(p.icon).assertEqual('📝');
      expect(p.title).assertEqual('终端');
      expect(p.subtitle).assertEqual('echo x > bar.txt');
    });
    it('无 parsed_cmd → ⌨️ + 终端标题 + minimal true', 0, () => {
      const input = rec('{"command":"ls -la"}');
      const p = getToolPresentation(mk('CodexBash', input, null, ''));
      expect(p.icon).assertEqual('⌨️');
      expect(p.title).assertEqual('终端');
      expect(p.subtitle).assertEqual('ls -la');
      expect(p.minimal).assertTrue();
    });
    it('command 为数组 → subtitle join(空格)', 0, () => {
      const input = rec('{"command":["git","status","--short"]}');
      const p = getToolPresentation(mk('CodexBash', input, null, ''));
      expect(p.subtitle).assertEqual('git status --short');
      expect(p.icon).assertEqual('⌨️');
    });
    it('有 stdout → minimal false（内联展示输出）', 0, () => {
      const input = rec('{"command":"echo hi"}');
      const result = rec('{"stdout":"hi","stderr":""}');
      const p = getToolPresentation(mk('CodexBash', input, result, ''));
      expect(p.minimal).assertFalse();
    });
    it('多 parsed_cmd（非单条）→ 即便首条 read，标题回落终端', 0, () => {
      const input = rec('{"parsed_cmd":[{"type":"read","name":"a"},{"type":"read","name":"b"}],"command":"cat a b"}');
      const p = getToolPresentation(mk('CodexBash', input, null, ''));
      expect(p.icon).assertEqual('👁️');
      expect(p.title).assertEqual('终端');
    });
  });

  describe('getToolPresentation — shell_command / run_shell_command', () => {
    it('shell_command → ⌨️ + 终端 + command subtitle + minimal true', 0, () => {
      const input = rec('{"command":"make build"}');
      const p = getToolPresentation(mk('shell_command', input, null, ''));
      expect(p.icon).assertEqual('⌨️');
      expect(p.title).assertEqual('终端');
      expect(p.subtitle).assertEqual('make build');
      expect(p.minimal).assertTrue();
    });
    it('run_shell_command + cmd 键（无 command）→ subtitle 取 cmd', 0, () => {
      const input = rec('{"cmd":"npm test"}');
      const p = getToolPresentation(mk('run_shell_command', input, null, ''));
      expect(p.subtitle).assertEqual('npm test');
      expect(p.minimal).assertTrue();
    });
    it('带 description → 标题用 description 覆盖终端', 0, () => {
      const input = rec('{"command":"make build"}');
      const p = getToolPresentation(mk('shell_command', input, null, '编译项目'));
      expect(p.title).assertEqual('编译项目');
    });
  });

  describe('getToolPresentation — CodexPatch', () => {
    it('单文件 → 📝 + 应用更改 + basename', 0, () => {
      const input = rec('{"changes":{"src/foo.ts":{"body":"x"}}}');
      const p = getToolPresentation(mk('CodexPatch', input, null, ''));
      expect(p.icon).assertEqual('📝');
      expect(p.title).assertEqual('应用更改');
      expect(p.subtitle).assertEqual('foo.ts');
      expect(p.minimal).assertTrue();
    });
    it('多文件 → 首文件 basename（+N-1）', 0, () => {
      const input = rec('{"changes":{"src/a.ts":{},"src/b.ts":{},"src/c.ts":{}}}');
      const p = getToolPresentation(mk('CodexPatch', input, null, ''));
      expect(p.title).assertEqual('应用更改');
      expect(p.subtitle).assertEqual('a.ts（+2）');
    });
    it('无 changes → subtitle 空', 0, () => {
      const input = rec('{}');
      const p = getToolPresentation(mk('CodexPatch', input, null, ''));
      expect(p.title).assertEqual('应用更改');
      expect(p.subtitle).assertEqual('');
    });
    it('changes 非 object（数组）→ subtitle 空（不误当文件名）', 0, () => {
      const input = rec('{"changes":["x","y"]}');
      const p = getToolPresentation(mk('CodexPatch', input, null, ''));
      expect(p.subtitle).assertEqual('');
    });
  });

  describe('getToolPresentation — CodexPermission', () => {
    it('有 tool → ❓ + 权限：{tool} + message subtitle', 0, () => {
      const input = rec('{"tool":"Bash","message":"允许执行？"}');
      const p = getToolPresentation(mk('CodexPermission', input, null, ''));
      expect(p.icon).assertEqual('❓');
      expect(p.title).assertEqual('权限：Bash');
      expect(p.subtitle).assertEqual('允许执行？');
      expect(p.minimal).assertTrue();
    });
    it('无 tool → 权限请求 + message subtitle', 0, () => {
      const input = rec('{"message":"请授权"}');
      const p = getToolPresentation(mk('CodexPermission', input, null, ''));
      expect(p.title).assertEqual('权限请求');
      expect(p.subtitle).assertEqual('请授权');
    });
    it('无 message 但有 command → command subtitle', 0, () => {
      const input = rec('{"tool":"Edit","command":"rm -rf"}');
      const p = getToolPresentation(mk('CodexPermission', input, null, ''));
      expect(p.title).assertEqual('权限：Edit');
      expect(p.subtitle).assertEqual('rm -rf');
    });
  });

  describe('getToolPresentation — CodexReasoning', () => {
    it('有 title → 💡 + title + minimal true', 0, () => {
      const input = rec('{"title":"为什么选 A 方案"}');
      const p = getToolPresentation(mk('CodexReasoning', input, null, ''));
      expect(p.icon).assertEqual('💡');
      expect(p.title).assertEqual('为什么选 A 方案');
      expect(p.minimal).assertTrue();
    });
    it('无 title → 💡 + 思考', 0, () => {
      const input = rec('{}');
      const p = getToolPresentation(mk('CodexReasoning', input, null, ''));
      expect(p.icon).assertEqual('💡');
      expect(p.title).assertEqual('思考');
    });
  });

  describe('getToolPresentation — SendMessage', () => {
    it('broadcast → 💬 + 广播 + summary subtitle', 0, () => {
      const input = rec('{"type":"broadcast","summary":"全员注意"}');
      const p = getToolPresentation(mk('SendMessage', input, null, ''));
      expect(p.icon).assertEqual('💬');
      expect(p.title).assertEqual('广播');
      expect(p.subtitle).assertEqual('全员注意');
      expect(p.minimal).assertTrue();
    });
    it('shutdown_request 有 recipient → 关停：{recipient}', 0, () => {
      const input = rec('{"type":"shutdown_request","recipient":"researcher"}');
      const p = getToolPresentation(mk('SendMessage', input, null, ''));
      expect(p.title).assertEqual('关停：researcher');
    });
    it('shutdown_request 无 recipient → 关停：Agent 兜底', 0, () => {
      const input = rec('{"type":"shutdown_request"}');
      const p = getToolPresentation(mk('SendMessage', input, null, ''));
      expect(p.title).assertEqual('关停：Agent');
    });
    it('shutdown_response → 关停响应', 0, () => {
      const input = rec('{"type":"shutdown_response"}');
      const p = getToolPresentation(mk('SendMessage', input, null, ''));
      expect(p.title).assertEqual('关停响应');
    });
    it('普通消息有 recipient → 消息：{recipient}', 0, () => {
      const input = rec('{"recipient":"coder","summary":"hi"}');
      const p = getToolPresentation(mk('SendMessage', input, null, ''));
      expect(p.title).assertEqual('消息：coder');
      expect(p.subtitle).assertEqual('hi');
    });
    it('无 type 无 recipient → 发送消息', 0, () => {
      const input = rec('{}');
      const p = getToolPresentation(mk('SendMessage', input, null, ''));
      expect(p.title).assertEqual('发送消息');
      expect(p.subtitle).assertEqual('');
    });
    it('summary 超 120 字符 → 截断为 120 + …', 0, () => {
      let long: string = '';
      for (let i = 0; i < 150; i++) {
        long += 'a';
      }
      const input = rec('{"summary":"' + long + '"}');
      const p = getToolPresentation(mk('SendMessage', input, null, ''));
      expect(p.subtitle.length).assertEqual(121);
    });
  });

  describe('getToolPresentation — NotebookRead / NotebookEdit', () => {
    it('NotebookRead 有 path → 👁️ + path', 0, () => {
      const input = rec('{"notebook_path":"analysis.ipynb"}');
      const p = getToolPresentation(mk('NotebookRead', input, null, ''));
      expect(p.icon).assertEqual('👁️');
      expect(p.title).assertEqual('analysis.ipynb');
      expect(p.minimal).assertTrue();
    });
    it('NotebookRead 无 path → 👁️ + 读取笔记本', 0, () => {
      const input = rec('{}');
      const p = getToolPresentation(mk('NotebookRead', input, null, ''));
      expect(p.title).assertEqual('读取笔记本');
    });
    it('NotebookEdit 有 path + mode → 📝 + path + 模式 subtitle + minimal false（cell body 开）', 0, () => {
      const input = rec('{"notebook_path":"nb.ipynb","edit_mode":"insert"}');
      const p = getToolPresentation(mk('NotebookEdit', input, null, ''));
      expect(p.icon).assertEqual('📝');
      expect(p.title).assertEqual('nb.ipynb');
      expect(p.subtitle).assertEqual('模式：insert');
      expect(p.minimal).assertFalse();
    });
    it('NotebookEdit 无 path 无 mode → 📝 + 编辑笔记本 + 空 subtitle + minimal false', 0, () => {
      const input = rec('{}');
      const p = getToolPresentation(mk('NotebookEdit', input, null, ''));
      expect(p.title).assertEqual('编辑笔记本');
      expect(p.subtitle).assertEqual('');
      expect(p.minimal).assertFalse();
    });
  });

  describe('getToolPresentation — CodexAgent', () => {
    it('有 summary+effort+activity → 🚀 + 代理：{summary} + effort·status + minimal false', 0, () => {
      const input = rec('{"summary":"Do thing","reasoning_effort":"high","activity":"Running","agentStatus":"running"}');
      const p = getToolPresentation(mk('CodexAgent', input, null, ''));
      expect(p.icon).assertEqual('🚀');
      expect(p.title).assertEqual('代理：Do thing');
      expect(p.subtitle).assertEqual('reasoning high · Running');
      expect(p.minimal).assertFalse();
    });
    it('空 → 🚀 + Agent + 空 subtitle + minimal false', 0, () => {
      const p = getToolPresentation(mk('CodexAgent', rec('{}'), null, ''));
      expect(p.icon).assertEqual('🚀');
      expect(p.title).assertEqual('Agent');
      expect(p.subtitle).assertEqual('');
      expect(p.minimal).assertFalse();
    });
  });

  describe('getToolPresentation — spawn_agent', () => {
    it('有 type + result → 🚀 + 启动 {type} 代理 + 已启动 {label} + minimal false', 0, () => {
      const input = rec('{"agent_type":"researcher"}');
      const result = rec('{"agent_id":"a1","nickname":"Bob"}');
      const p = getToolPresentation(mk('spawn_agent', input, result, ''));
      expect(p.icon).assertEqual('🚀');
      expect(p.title).assertEqual('启动 researcher 代理');
      expect(p.subtitle).assertEqual('已启动 Bob (a1)');
      expect(p.minimal).assertFalse();
    });
    it('空 + 无 result → 🚀 + 启动代理 + 后台代理（fallback）+ minimal false', 0, () => {
      const p = getToolPresentation(mk('spawn_agent', rec('{}'), null, ''));
      expect(p.title).assertEqual('启动代理');
      expect(p.subtitle).assertEqual('后台代理');
      expect(p.minimal).assertFalse();
    });
  });

  describe('getToolPresentation — send_input', () => {
    it('有 targets → 💬 + 发送消息给代理 + targets join + minimal false', 0, () => {
      const input = rec('{"targets":["agent-1","agent-2"]}');
      const p = getToolPresentation(mk('send_input', input, null, ''));
      expect(p.icon).assertEqual('💬');
      expect(p.title).assertEqual('发送消息给代理');
      expect(p.subtitle).assertEqual('agent-1, agent-2');
      expect(p.minimal).assertFalse();
    });
    it('空 → 💬 + 发送消息给代理 + 后台消息 + minimal false', 0, () => {
      const p = getToolPresentation(mk('send_input', rec('{}'), null, ''));
      expect(p.title).assertEqual('发送消息给代理');
      expect(p.subtitle).assertEqual('后台消息');
      expect(p.minimal).assertFalse();
    });
  });

  describe('getToolPresentation — resume_agent', () => {
    it('有 targets → 🚀 + 恢复代理 + targets join + minimal false', 0, () => {
      const input = rec('{"targets":["a"]}');
      const p = getToolPresentation(mk('resume_agent', input, null, ''));
      expect(p.icon).assertEqual('🚀');
      expect(p.title).assertEqual('恢复代理');
      expect(p.subtitle).assertEqual('a');
      expect(p.minimal).assertFalse();
    });
    it('空 → 🚀 + 恢复代理 + 空 subtitle + minimal false', 0, () => {
      const p = getToolPresentation(mk('resume_agent', rec('{}'), null, ''));
      expect(p.title).assertEqual('恢复代理');
      expect(p.subtitle).assertEqual('');
      expect(p.minimal).assertFalse();
    });
  });

  describe('getToolPresentation — wait_agent', () => {
    it('targets>1 + result → 🚀 + 等待 N 个代理 + N 个完成 + minimal false', 0, () => {
      const input = rec('{"targets":["a","b"]}');
      const result = rec('{"status":{"a":{"completed":"done"}}}');
      const p = getToolPresentation(mk('wait_agent', input, result, ''));
      expect(p.icon).assertEqual('🚀');
      expect(p.title).assertEqual('等待 2 个代理');
      expect(p.subtitle).assertEqual('1 个完成');
      expect(p.minimal).assertFalse();
    });
    it('空 + 无 result → 🚀 + 等待代理 + 空 subtitle + minimal false', 0, () => {
      const p = getToolPresentation(mk('wait_agent', rec('{}'), null, ''));
      expect(p.title).assertEqual('等待代理');
      expect(p.subtitle).assertEqual('');
      expect(p.minimal).assertFalse();
    });
  });

  describe('getToolPresentation — close_agent', () => {
    it('有 result → 🚀 + 关闭代理 + 已关闭（{state}）+ minimal false', 0, () => {
      const result = rec('{"previous_status":{"completed":"ok"}}');
      const p = getToolPresentation(mk('close_agent', rec('{}'), result, ''));
      expect(p.icon).assertEqual('🚀');
      expect(p.title).assertEqual('关闭代理');
      expect(p.subtitle).assertEqual('已关闭（completed）');
      expect(p.minimal).assertFalse();
    });
    it('空 + 无 result → 🚀 + 关闭代理 + 空 subtitle + minimal false', 0, () => {
      const p = getToolPresentation(mk('close_agent', rec('{}'), null, ''));
      expect(p.title).assertEqual('关闭代理');
      expect(p.subtitle).assertEqual('');
      expect(p.minimal).assertFalse();
    });
  });

  describe('getToolPresentation — 回归（既有分支不变）', () => {
    it('Bash → ⌨️ + 终端 + command subtitle', 0, () => {
      const input = rec('{"command":"pwd"}');
      const p = getToolPresentation(mk('Bash', input, null, ''));
      expect(p.icon).assertEqual('⌨️');
      expect(p.title).assertEqual('终端');
      expect(p.subtitle).assertEqual('pwd');
    });
    it('Read → 👁️ + 文件路径标题', 0, () => {
      const input = rec('{"file_path":"src/main.ts"}');
      const p = getToolPresentation(mk('Read', input, null, ''));
      expect(p.icon).assertEqual('👁️');
      expect(p.title).assertEqual('src/main.ts');
    });
    it('未知工具 → 🔧 default 字段探测兜底', 0, () => {
      const input = rec('{"file_path":"/a/b.ts"}');
      const p = getToolPresentation(mk('SomeUnknownTool', input, null, ''));
      expect(p.icon).assertEqual('🔧');
      expect(p.title).assertEqual('SomeUnknownTool');
      expect(p.subtitle).assertEqual('/a/b.ts');
    });
  });
}
