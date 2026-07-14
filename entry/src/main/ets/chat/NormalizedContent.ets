// NormalizedAgentContent —— 对齐 web/src/chat/types.ts NormalizedAgentContent
// ArkTS 无判别联合 → 单类 + type 字段串判别（ForEach/instanceof 在声明式树里不稳，字符串比较最稳）。
// MVP 范围：text / reasoning / tool-call / tool-result / generated-image / codex-review。
//   tool-call 的 id = tool_use.id；tool-result 的 id = tool_use_id（reducer 据此合并两者）。
//   generated-image：agent 调 display_image 工具登记的图，元数据随 SSE 推送（imageId/fileName/mimeType），
//     二进制按需 GET /api/sessions/:id/generated-images/:imageId 拉（对照 web GeneratedImageContent）。
//   codex-review：Codex agent 偶把 review JSON 当文本发出（data.type==='message' && data.message 为字符串）；
//     parse 时嗅探（parseCodexReviewMessage）命中 → codex-review 块携带解析后 review（对照上游同处分支）。
// 纯数据类，无 ArkUI 依赖。

import { CodexReview } from './CodexReview';

export type NormalizedBlockType = 'text' | 'reasoning' | 'tool-call' | 'tool-result' | 'generated-image' | 'codex-review';

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

  // generated-image 块（对照 web/src/chat/types.ts:59-66 GeneratedImageContent）
  //   SSE new-message 推送的 data.type==='generated-image' 消息解析而来；二进制不在报文里，渲染时按 imageId 拉。
  imageId: string = '';                                 // 后端内存图的 id（GET .../generated-images/:imageId 用）
  fileName: string = '';                                 // 原始文件名（caption + 预览标题）
  mimeType: string = '';                                 // '' = 未知（渲染时按扩展名/响应头回退）

  // codex-review 块（对照 web/src/chat/types.ts:102-107）：data.message 字符串嗅探 parseCodexReviewMessage
  //   命中后携带解析后的 review；reducer 映射为 ChatBlock.codexReview。null = 非 codex-review 块。
  review: CodexReview | null = null;
}
