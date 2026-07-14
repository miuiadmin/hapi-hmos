// ChatBlock / ChatToolCall / ToolPermission —— 对齐 web/src/chat/types.ts
// ArkTS 无判别联合 → 单类 + kind/state/status 字符串判别。
// 0 表示 null 时间戳（startedAt/completedAt/createdAt of permission）。
// 纯数据类（reducer 每次产出全新实例），无 ArkUI 依赖。

import { UsageData } from '../models/Message';
import { AttachmentMetadata, AgentEvent } from '../models/Types';
import { CodexReview } from './CodexReview';

export type ChatBlockKind = 'user-text' | 'agent-text' | 'tool-call' | 'reasoning' | 'generated-image' | 'cli-output' | 'codex-review' | 'agent-event';
export type ToolState = 'pending' | 'running' | 'completed' | 'error';
export type PermissionStatus = 'pending' | 'approved' | 'denied' | 'canceled';

// 工具权限（pending=等用户决定；approved/denied/canceled=已决）
export class ToolPermission {
  id: string = '';
  status: PermissionStatus = 'pending';
  reason: string = '';                                    // 拒绝/取消原因（可空）
  mode: string = '';                                       // PermissionMode（可空）
  decision: string = '';                                   // 'approved'|'approved_for_session'|'denied'|'abort'（可空）
  allowedTools: string[] = [];                             // 会话级放行工具（可空）
  answers: Record<string, Object> | null = null;           // 答题回填（flat 或 nested，按工具名判形）
  createdAt: number = 0;                                   // 0 = null
  completedAt: number = 0;                                 // 0 = null
}

// 单次工具调用（tool-call + 对应 tool-result 合并后的有状态卡）
export class ChatToolCall {
  id: string = '';                         // tool_use id（跨 call+result 的合并键）
  name: string = '';
  state: ToolState = 'running';
  input: Record<string, Object> | null = null;
  createdAt: number = 0;                    // 最早出现时间（保序用）
  startedAt: number = 0;                    // 0 = null
  completedAt: number = 0;                  // 0 = null
  description: string = '';
  result: Object | null = null;             // tool-result 内容；null = 尚无结果
  permission: ToolPermission | null = null;
}

// 渲染单元（reducer 产出，ForEach 按 id 作 key）
export class ChatBlock {
  kind: ChatBlockKind = 'agent-text';
  id: string = '';                          // 稳定 key：user-text→msg.id；agent-text→`${msgId}:${idx}`；tool-call→tool_use_id
  createdAt: number = 0;
  text: string = '';                        // user-text / agent-text 正文
  tool: ChatToolCall | null = null;          // 仅 tool-call

  // 仅 user-text：携带乐观发送态（迁移到 blocks 模型后仍需显示「发送中/排队中/失败」）
  userOptimistic: boolean = false;
  userStatus: string = '';                   // ''|'sending'|'queued'|'failed'

  // 仅 user-text：用户附件（对照 web MessageAttachments）。reducer 从 ChatMessage.attachments 透传；
  //   图片附件（previewUrl 非空）→ 缩略图网格（点击 ImagePreviewSheet 放大）；其余 → 文件卡片。
  //   纯图消息（text 空）也产出 user-text 块以渲染附件。
  attachments: AttachmentMetadata[] = [];

  // 渲染标记：本块前是否插入跨日日期分隔（首条或与上一块不同日）。
  //   由 ChatPage.recomputeBlocks 在 reducer 产出后盖戳（纯序列判定，无 now 依赖）；
  //   不放进 reduceChatBlocks 以保持 reducer 纯净/不影响其单测。DateDivider 文本（今天/昨天/日期）在渲染时取。
  dividerBefore: boolean = false;

  // 渲染标记：本块是否为「进入会话时的首条未读」（createdAt > entryLastSeenAt 的首块）。
  //   上游无对照（web 进会话总滚底、无未读分隔）——客户端自创，复用 #113 lastSeenAt 基础设施。
  //   entryLastSeenAt 在 aboutToAppear 捕获（markSeen 前），本页期间不变；下次进会话重算。
  //   渲染时在本块前插「以下为未读」分隔；过滤视图不显示（同 dividerBefore）。
  unreadDividerBefore: boolean = false;

  // 仅 generated-image：agent 调 display_image 登记的图（对照 web GeneratedImageBlock）。
  //   二进制按 imageId 按 GET 拉 → data URI → Image()；fileName 用作 caption，mimeType 用作 data URI 媒体类型。
  imageId: string = '';
  fileName: string = '';
  mimeType: string = '';

  // 仅 cli-output：CLI 命令输出块（对照 web CliOutputBlock）。
  //   text 为带 <command-name>/<local-command-stdout> 等标签的原始文本；CliOutputCard 解析渲染。
  //   source = 'user' | 'assistant'（消息角色来源，对照上游；mergeCliOutputBlocks 据此判断相邻块同源可合并）。
  source: string = '';

  // 仅 agent-text：消息元数据脚注（对照 web MessageMetadata）。usage=消息用量（null=无）；
  //   model=消息模型名（'' 时 UI 回退会话 model）；invokedAt=消息调用时间（0=未知，脚注不显 Invoke）。
  //   reducer 从 ChatMessage 拷贝；多条 agent-text 共享同消息的同一份 usage（与上游「每块挂消息用量」一致）。
  usage: UsageData | null = null;
  model: string = '';
  invokedAt: number = 0;
  // turn 耗时（对照 web block.durationMs）：-1 = 无；>=0 = turn-duration event 回填的毫秒。
  //   仅 agent-text/reasoning/tool-call/cli-output/codex-review 块被回填（Reducer.applyTurnDuration 据
  //   targetMessageId 匹配，对照 reducerTimeline.ts:443-468）。MessageMetadata 据此显 Duration 脚注。
  durationMs: number = -1;

  // 仅 codex-review：Codex agent 偶把 review JSON 当文本发出；parse 嗅探命中后携带解析结果
  //   （对照 web CodexReviewBlock）。reducer 从 NormalizedAgentContent.review 映射；null = 非 review 块。
  review: CodexReview | null = null;

  // 仅 agent-event：agent 事件系统消息条（对照 web AgentEventBlock）。reducer 从 event 消息（api-error/
  //   microcompact/compact）或 agent-text 限额文本嗅探（limit-warning/reached）映射；null = 非事件块。
  //   EventPresentation 据 event 产 icon+text，渲染为居中灰条（#1 系统消息条 / #4 限额提示）。
  event: AgentEvent | null = null;

  // 便捷工厂
  static agentText(id: string, createdAt: number, text: string, invokedAt: number = 0,
    model: string = '', usage: UsageData | null = null): ChatBlock {
    const b: ChatBlock = new ChatBlock();
    b.kind = 'agent-text';
    b.id = id;
    b.createdAt = createdAt;
    b.text = text;
    b.invokedAt = invokedAt;
    b.model = model;
    b.usage = usage;
    return b;
  }

  static userText(id: string, createdAt: number, text: string): ChatBlock {
    const b: ChatBlock = new ChatBlock();
    b.kind = 'user-text';
    b.id = id;
    b.createdAt = createdAt;
    b.text = text;
    b.attachments = [];
    return b;
  }

  // 思考过程块（agent 的 reasoning/thinking，对照上游 NormalizedAgentContent{type:'reasoning'}）
  static reasoning(id: string, createdAt: number, text: string): ChatBlock {
    const b: ChatBlock = new ChatBlock();
    b.kind = 'reasoning';
    b.id = id;
    b.createdAt = createdAt;
    b.text = text;
    return b;
  }

  // 生成图片块（agent 调 display_image 登记的图，对照上游 GeneratedImageBlock）
  static generatedImage(id: string, createdAt: number, imageId: string, fileName: string, mimeType: string): ChatBlock {
    const b: ChatBlock = new ChatBlock();
    b.kind = 'generated-image';
    b.id = id;
    b.createdAt = createdAt;
    b.imageId = imageId;
    b.fileName = fileName;
    b.mimeType = mimeType;
    return b;
  }

  // CLI 命令输出块（对照上游 CliOutputBlock；source='user'|'assistant' 为消息角色来源）
  static cliOutput(id: string, createdAt: number, text: string, source: string): ChatBlock {
    const b: ChatBlock = new ChatBlock();
    b.kind = 'cli-output';
    b.id = id;
    b.createdAt = createdAt;
    b.text = text;
    b.source = source;
    return b;
  }

  // Codex review 块（对照上游 CodexReviewBlock；review=parseCodexReviewMessage 解析结果）
  static codexReview(id: string, createdAt: number, review: CodexReview): ChatBlock {
    const b: ChatBlock = new ChatBlock();
    b.kind = 'codex-review';
    b.id = id;
    b.createdAt = createdAt;
    b.review = review;
    return b;
  }

  // 系统消息条块（对照上游 AgentEventBlock；event=AgentEvent 解析/嗅探结果）。EventPresentation 据此产居中灰条。
  static agentEvent(id: string, createdAt: number, event: AgentEvent): ChatBlock {
    const b: ChatBlock = new ChatBlock();
    b.kind = 'agent-event';
    b.id = id;
    b.createdAt = createdAt;
    b.event = event;
    return b;
  }
}

// getPermissions 的中间结构（对齐 web PermissionEntry）
export class PermissionEntry {
  toolName: string = '';
  input: Object | null = null;
  permission: ToolPermission = new ToolPermission();
}
