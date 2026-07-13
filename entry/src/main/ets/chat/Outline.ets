// 对话大纲 —— 对照 web/src/chat/outline.ts
//   只索引 user-text 块（用户提问），文本折叠空白 + 截断 96 字符作 label。
//   跳过未发送的 optimistic 块（除非 failed）—— 与上游 isLocatableOutlineBlock 同语义：
//     上游 `!(invokedAt===null && status!=='failed')`；ArkTS 端 invokedAt===null ≡ userOptimistic===true，
//     status==='failed' ≡ userStatus==='failed'（ChatBlock 无 invokedAt/status，用 userOptimistic/userStatus 替代）。
//   跳转：OutlinePanel 点 item → onJump(blockId) → ChatPage 在 filteredBlocks 内查 index → scrollToIndex。
//   ArkTS List 全量渲染 filteredBlocks，目标必在数组内，无需上游 load-older 翻页循环。
// 纯逻辑（无 ArkUI 依赖），单测见 Outline.test.ets。

import { ChatBlock } from './ChatBlock';
import { t } from '../i18n/Translate';

export const MAX_OUTLINE_LABEL_LENGTH: number = 96;

export class ConversationOutlineItem {
  id: string = '';                 // 大纲项稳定 id（'outline:user-text:<blockId>'）
  blockId: string = '';            // 目标 ChatBlock.id（filteredBlocks 内查 index 用）
  label: string = '';
  createdAt: number = 0;
}

// 空白折叠（\s+ → 单空格 + trim）。ArkTS 支持 \s 正则。
function collapseWhitespace(value: string): string {
  return value.replace(/\s+/g, ' ').trim();
}

// 截断 label：超长取前 maxLength-3 + 去尾空白 + '...'（对照 truncateOutlineLabel）。
export function truncateOutlineLabel(value: string, maxLength: number = MAX_OUTLINE_LABEL_LENGTH): string {
  const normalized: string = collapseWhitespace(value);
  if (normalized.length <= maxLength) { return normalized; }
  const cut: number = maxLength - 3;
  const head: string = normalized.substring(0, cut > 0 ? cut : 0);
  return `${head.replace(/\s+$/, '')}...`;
}

// user-text 块是否可定位（上游 isLocatableOutlineBlock）：非 user-text 或未发送 optimistic（非 failed）跳过。
function isLocatableUserBlock(b: ChatBlock): boolean {
  if (b.kind !== 'user-text') { return false; }
  if (b.userOptimistic && b.userStatus !== 'failed') { return false; }
  return true;
}

// 遍历 blocks 产出大纲项（仅 user-text，保序）。label 空回落「空消息」。
export function buildConversationOutline(blocks: ChatBlock[]): ConversationOutlineItem[] {
  const items: ConversationOutlineItem[] = [];
  for (let i = 0; i < blocks.length; i++) {
    const b: ChatBlock = blocks[i];
    if (!isLocatableUserBlock(b)) { continue; }
    const item: ConversationOutlineItem = new ConversationOutlineItem();
    item.id = `outline:user-text:${b.id}`;
    item.blockId = b.id;
    const label: string = truncateOutlineLabel(b.text);
    item.label = label !== '' ? label : t('outline.emptyMessage');
    item.createdAt = b.createdAt;
    items.push(item);
  }
  return items;
}
