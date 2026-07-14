// ThreadGoal —— 顶部状态行 goal chip 的解析管线纯逻辑（对照 web/src/chat/reducer.ts:36-58 getLatestThreadGoal）。
//   零 @kit 纯层、零 i18n 调用：仅 import models/Message（ChatMessage）+ models/Types（ThreadGoal）。
//   从消息时间线反向遍历取最新有效 thread-goal，含上游三段抑制：
//     1) cleared 事件 → null；2) updated 且 complete 且其后有非 /goal 用户消息 → null；
//     3) /goal 命令用户消息不计入「新非-goal 活动」（保 chip 不被目标设定本身清掉）。
//   未触发定时 user 消息不计入（对照 SessionChat.tsx:53-55 buildGoalStateMessages isUninvokedScheduledMessage）。
import { ChatMessage } from '../models/Message';
import { ThreadGoal } from '../models/Types';

// 用户文本是否为 /goal 斜杠命令（对照 reducer.ts:41 /^\s*\/goal(?:\s|$)/i）。
//   手写扫描避 regex s-flag/backref（照 chat/CodexDiff.ets 范式）：跳前导空白（\s 全集
//   = \t\n\v\f\r space，charCode 9/10/11/12/13/32）→ 大小写不敏感比 '/goal' → 其后须空白或串尾。
//   '/goal'、'/goal ship it'、'/GOAL' 匹配；'/goals'、'/goal-x' 不匹配。
function isGoalSlashCommand(text: string): boolean {
  let i: number = 0;
  // 跳过前导空白（\s 全集：tab9/nl10/vt11/ff12/cr13/space32）
  while (i < text.length) {
    const ch: number = text.charCodeAt(i);
    if (ch === 9 || ch === 10 || ch === 11 || ch === 12 || ch === 13 || ch === 32) { i++; } else { break; }
  }
  const CMD: string = '/goal';
  if (text.length - i < CMD.length) { return false; }
  // 大小写不敏感比较 '/goal'（A-Z 65-90 → +32 → a-z 97-122）
  for (let k = 0; k < CMD.length; k++) {
    let a: number = text.charCodeAt(i + k);
    let b: number = CMD.charCodeAt(k);
    if (a >= 65 && a <= 90) { a += 32; }
    if (b >= 65 && b <= 90) { b += 32; }
    if (a !== b) { return false; }
  }
  // 其后须是空白（\s 全集）或串尾（'/goals'、'/goal-x' 不匹配）
  const after: number = i + CMD.length;
  if (after >= text.length) { return true; }
  const c: number = text.charCodeAt(after);
  return c === 9 || c === 10 || c === 11 || c === 12 || c === 13 || c === 32;
}

// 反向遍历消息取最新有效 thread-goal（对照 reducer.ts:36-58）。
//   agent 消息跳过；user 非 /goal 命令（且非未触发定时）置 sawNewerNonGoalUserMessage；
//   event：goalCleared → null；goal!==null 且 (status==='complete' && sawNewer) → null，否则返 goal。
//   未触发定时 user（scheduledAt>0 && invokedAt===0）整条跳过（不计数、不判 /goal）。
export function getLatestThreadGoal(messages: ChatMessage[]): ThreadGoal | null {
  let sawNewerNonGoalUserMessage: boolean = false;
  for (let i = messages.length - 1; i >= 0; i--) {
    const msg: ChatMessage = messages[i];
    if (msg.role === 'user') {
      if (msg.scheduledAt > 0 && msg.invokedAt === 0) { continue; }   // 未触发定时消息不计入
      if (!isGoalSlashCommand(msg.text)) {
        sawNewerNonGoalUserMessage = true;
      }
      continue;
    }
    if (msg.role !== 'event') { continue; }   // agent 等
    if (msg.goalCleared) { return null; }
    if (msg.goal !== null) {
      if (msg.goal.status === 'complete' && sawNewerNonGoalUserMessage) { return null; }
      return msg.goal;
    }
  }
  return null;
}
