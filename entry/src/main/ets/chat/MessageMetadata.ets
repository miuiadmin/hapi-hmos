// 每消息元数据脚注（对照 web AssistantChat/messages/MessageMetadata.tsx buildMessageMetadataLabels）
// 纯逻辑层（无 @kit）：供 ChatPage AgentBubble 调用得 label[]，空数组→不显脚注/开关。
//
// 延后项（见 swirling-weaving-tide 计划）：Duration（需 system/turn_duration SSE 接线）、
//   turnCount（鸿蒙 reducer 一 text 内容一 block，恒 1，N/A）。本层仅 Invoke/Model/Tier/Usage。
//
// import 仅经纯层：i18n/Translate（无 @kit）、models/Message（无 @kit，验过）、utils/DateFormatUtils（无 @kit）。

import { t } from '../i18n/Translate';
import { UsageData, formatTokenCount } from '../models/Message';
import { formatClockSeconds } from '../utils/DateFormatUtils';

// 计费档是否值得显示：非空且非 standard（对齐上游——standard 是默认档，省略以免噪声）。
function isNotableTier(tier: string): boolean {
  if (tier === '') {
    return false;
  }
  return tier.toLowerCase() !== 'standard';
}

// 构建脚注标签串（顺序：Invoke → Model → Tier → Usage）。
//   invokedAt：0/未知 → 不显 Invoke；>0 → t('meta.invoke', {time: HH:mm:ss})。
//   model：'' → 不显（UI 侧已回退会话 model 再传入，故空=会话也无模型）。
//   tier：取自 usage.serviceTier；非 standard 才显 t('meta.tier', {tier})。
//   usage：非 null → t('meta.usage', {total, input, output})，total=input+output（cache 不计，billable）。
export function buildMessageMetadataLabels(invokedAt: number, usage: UsageData | null, model: string): string[] {
  const labels: string[] = [];

  if (invokedAt > 0) {
    labels.push(t('meta.invoke', { time: formatClockSeconds(invokedAt) }));
  }

  if (model !== '') {
    labels.push(t('meta.model', { model }));
  }

  if (usage !== null) {
    if (isNotableTier(usage.serviceTier)) {
      labels.push(t('meta.tier', { tier: usage.serviceTier }));
    }
    const total: number = usage.inputTokens + usage.outputTokens;
    labels.push(t('meta.usage', {
      total: formatTokenCount(total),
      input: formatTokenCount(usage.inputTokens),
      output: formatTokenCount(usage.outputTokens)
    }));
  }

  return labels;
}
