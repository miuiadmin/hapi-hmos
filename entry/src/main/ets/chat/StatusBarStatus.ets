// StatusBar 状态决策纯层（对照 web AssistantChat/StatusBar.tsx getConnectionStatus）
// 无 @kit，LocalUnit 可测。组件侧注入 isThinking/agentState/net/SSE 态 + 随机 vibingIndex。
//
// 状态优先级（对照上游 getConnectionStatus，省略鸿蒙不可达的 voice-connecting / backgroundTaskCount 两态）：
//   设备离线 || SSE 未连 → offline（灰）→ 权限待批（橙）→ 思考中（蓝 + 随机动词）→ 在线（绿）
// pulse 动画 v1 用静态色点（ArkUI 无 animate-pulse 直配；留可选后续）。
//
// import 仅 i18n/Translate（无 @kit）。

import { t } from '../i18n/Translate';

export type StatusBarKind = 'offline' | 'permission' | 'thinking' | 'online';

export class StatusBarState {
  kind: StatusBarKind = 'online';
  label: string = '';
  color: string = '#34C759'; // 默认 online 绿（#34C759，对齐上游）
}

// 思考态动词表（对照上游 VIBING_MESSAGES，原样搬，MIT/AGPL 合规）。87 词。
export const VIBING_MESSAGES: string[] = [
  'Accomplishing', 'Actioning', 'Actualizing', 'Baking', 'Booping', 'Brewing',
  'Calculating', 'Cerebrating', 'Channelling', 'Churning', 'Clauding', 'Coalescing',
  'Cogitating', 'Computing', 'Combobulating', 'Concocting', 'Conjuring', 'Considering',
  'Contemplating', 'Cooking', 'Crafting', 'Creating', 'Crunching', 'Deciphering',
  'Deliberating', 'Determining', 'Discombobulating', 'Divining', 'Doing', 'Effecting',
  'Elucidating', 'Enchanting', 'Envisioning', 'Finagling', 'Flibbertigibbeting',
  'Forging', 'Forming', 'Frolicking', 'Generating', 'Germinating', 'Hatching',
  'Herding', 'Honking', 'Ideating', 'Imagining', 'Incubating', 'Inferring',
  'Manifesting', 'Marinating', 'Meandering', 'Moseying', 'Mulling', 'Mustering',
  'Musing', 'Noodling', 'Percolating', 'Perusing', 'Philosophising', 'Pontificating',
  'Pondering', 'Processing', 'Puttering', 'Puzzling', 'Reticulating', 'Ruminating',
  'Scheming', 'Schlepping', 'Shimmying', 'Simmering', 'Smooshing', 'Spelunking',
  'Spinning', 'Stewing', 'Sussing', 'Synthesizing', 'Thinking', 'Tinkering',
  'Transmuting', 'Unfurling', 'Unravelling', 'Vibing', 'Wandering', 'Whirring',
  'Wibbling', 'Wizarding', 'Working', 'Wrangling'
];

// 取思考动词：index 对长度取模（注入 index 保可测；组件侧 Math.floor(Math.random()*len)）。
//   小写 + 末尾 '…'（对照上游 toLowerCase() + '…'）。负 index 归一化防越界。
export function pickVibingMessage(index: number): string {
  const len: number = VIBING_MESSAGES.length;
  const i: number = ((index % len) + len) % len;
  return VIBING_MESSAGES[i].toLowerCase() + '…';
}

// 决策状态色点 + 文案（对照 getConnectionStatus）。
//   offline = 设备无网 || SSE 非 open；permission = agentState.requests 非空（仅 pending，对照上游）；
//   thinking = isThinking（label = 随机 vibing 动词，不 i18n）；余 online。
export function resolveStatusBarState(deviceOnline: boolean, sseOpen: boolean,
  hasPermissions: boolean, isThinking: boolean, vibingIndex: number): StatusBarState {
  const s: StatusBarState = new StatusBarState();
  if (!deviceOnline || !sseOpen) {
    s.kind = 'offline';
    s.label = t('status.offline');
    s.color = '#999999';
    return s;
  }
  if (hasPermissions) {
    s.kind = 'permission';
    s.label = t('status.permissionRequired');
    s.color = '#FF9500';
    return s;
  }
  if (isThinking) {
    s.kind = 'thinking';
    s.label = pickVibingMessage(vibingIndex);
    s.color = '#007AFF';
    return s;
  }
  s.kind = 'online';
  s.label = t('status.online');
  s.color = '#34C759';
  return s;
}
