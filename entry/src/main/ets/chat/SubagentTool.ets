// SubagentTool —— 子代理调用工具判定（纯层，无 @kit，LocalUnit 可加载）
//
// 原样移植上游 chat/subagentTool.ts：isSubagentToolName。供 Reducer（Flow A sidechain 分组）与
//   TerminalToolDisplay（shouldShowInlineToolCardBody 首判：子代理恒不内联）共用，避免重复定义。
//
//   Task=早期 SDK；Agent=后期 SDK（OPUS 4.7+）；另容错 'Agent:'/'Task:' 带前缀变体。
//   ArkTS 无 startsWith → indexOf('X')===0 替代。

// 是否子代理调用工具（发起 sidechain 子代理流）。
export function isSubagentToolName(name: string): boolean {
  return name === 'Task' || name === 'Agent' ||
    name.indexOf('Agent:') === 0 || name.indexOf('Task:') === 0;
}
