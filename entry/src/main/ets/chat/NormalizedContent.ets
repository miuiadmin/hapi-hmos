// NormalizedAgentContent —— 对齐 web/src/chat/types.ts NormalizedAgentContent
// ArkTS 无判别联合 → 单类 + type 字段串判别（ForEach/instanceof 在声明式树里不稳，字符串比较最稳）。
// MVP 范围：text / reasoning / tool-call / tool-result。
//   tool-call 的 id = tool_use.id；tool-result 的 id = tool_use_id（reducer 据此合并两者）。
// 纯数据类，无 ArkUI 依赖。

export type NormalizedBlockType = 'text' | 'reasoning' | 'tool-call' | 'tool-result';

export class NormalizedAgentContent {
  type: NormalizedBlockType = 'text';

  // text / reasoning 块正文
  text: string = '';

  // tool-call 块
  id: string = '';                                    // tool_use.id
  name: string = '';                                   // 工具名（缺省 'Tool'）
  input: Record<string, Object> | null = null;         // 工具入参
  description: string = '';                             // input.description（卡片副标题用）

  // tool-result 块（id = tool_use_id，与对应 tool-call 的 id 相等，作合并键）
  content: Object | null = null;                        // 结果内容（string / 对象 / {type:text}[] 等多种形态）
  isError: boolean = false;                             // tool_result.is_error
}
