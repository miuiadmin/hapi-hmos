// ChatSearch —— 对话内消息搜索（纯客户端过滤，无上游对应：hapi web 无 in-chat search）
//
// 设计取舍：选「过滤模式」而非「跳转+高亮」。理由——
//   过滤改的是 ForEach 的 key 集合（命中项入列、未命中出列），ArkUI 必然重渲染；
//   而高亮是「同 key 块换样式」，会撞 ForEach key 复用冻结（见 ChatPage.recomputeBlocks 注释、
//   ArkUI 文档「修改数据项若键值不变，则组件不更新」）。过滤复用本项目既有范式（Index.filteredSessions）。
//
// 可搜索范围：
//   - user-text / agent-text / reasoning → 正文 b.text（reasoning 也可搜，便于「它当时怎么想的」）
//   - tool-call → 名 + 描述 + 入参(JSON) + 结果(JSON)，扁平化为一条字符串（可按工具名/参数/结果关键词定位）

import { ChatBlock } from './ChatBlock';

// 工具卡入参/结果 → 字符串（JSON 序列化；失败/空 → ''，不影响其余字段）
function tryStringify(obj: Object | null): string {
  if (obj === null || obj === undefined) {
    return '';
  }
  try {
    return JSON.stringify(obj);
  } catch (e) {
    return '';
  }
}

// 块的可搜索文本（小写化由调用方在 blockMatchesQuery 内统一做）
export function blockSearchText(b: ChatBlock): string {
  if (b.kind === 'user-text' || b.kind === 'agent-text' || b.kind === 'reasoning') {
    return b.text;
  }
  // tool-call：扁平化工具名 / 描述 / 入参 / 结果
  if (b.tool === null) {
    return '';
  }
  const parts: string[] = [];
  if (b.tool.name !== '') {
    parts.push(b.tool.name);
  }
  if (b.tool.description !== '') {
    parts.push(b.tool.description);
  }
  const inputStr: string = tryStringify(b.tool.input);
  if (inputStr !== '') {
    parts.push(inputStr);
  }
  const resultStr: string = tryStringify(b.tool.result);
  if (resultStr !== '') {
    parts.push(resultStr);
  }
  return parts.join(' ');
}

// 块是否命中查询。q 任意大小写/前后空白（内部 trim+lower）；空查询 → false（UI 侧空查询走全量，不进本函数）。
export function blockMatchesQuery(b: ChatBlock, q: string): boolean {
  const needle: string = q.trim().toLowerCase();
  if (needle === '') {
    return false;
  }
  return blockSearchText(b).toLowerCase().includes(needle);
}
