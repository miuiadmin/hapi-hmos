// 目录建议纯逻辑层（无 @kit，LocalUnit 可测）。
//   对照上游 web/src/hooks/useDirectorySuggestions.ts（逐字移植语义）：
//     1. machineId 非空 → 过滤 sessions.metadata.machineId===machineId；否则用全部。
//     2. 两源收集：session.metadata.path + session.metadata.worktree.basePath。
//     3. dedupedRecent = 去重 recentPaths（保序）；recentSet = 其 Set。
//     4. otherPaths = [sessionPaths + worktreePaths] 去重 → 排除 recentSet 内 → localeCompare 升序。
//     5. 返回 [...dedupedRecent, ...otherPaths]（recent 在前，其余按字典序）。
//   ArkTS 约束：不用 [...new Set()] spread，手写循环去重；不用 replace-fn；localeCompare 可用。

import { SessionSummary } from '../models/Types';

// 取会话的 machineId（metadata 可能 null；空串表无 machineId）。
function sessionMachineId(s: SessionSummary): string {
  return s.metadata !== null ? s.metadata.machineId : '';
}

// 取会话的 path（metadata 可能 null）。
function sessionPath(s: SessionSummary): string {
  return s.metadata !== null ? s.metadata.path : '';
}

// 取会话的 worktree.basePath（metadata / worktreeBasePath 可能空）。
function sessionWorktreeBasePath(s: SessionSummary): string {
  return s.metadata !== null ? s.metadata.worktreeBasePath : '';
}

// 手写 pushUnique：arr 内已含 v 则不追加（替代 [...new Set()]）。
function pushUnique(arr: string[], v: string): void {
  for (let i = 0; i < arr.length; i++) {
    if (arr[i] === v) { return; }
  }
  arr.push(v);
}

// 手写 contains（替代 Set.has，避 Set<string> 与数组互转啰嗦）。
function contains(arr: string[], v: string): boolean {
  for (let i = 0; i < arr.length; i++) {
    if (arr[i] === v) { return true; }
  }
  return false;
}

// 主入口：machineId + sessions + recentPaths → 建议目录串数组（recent 在前，余 localeCompare 升序）。
export function buildDirectorySuggestions(
  machineId: string | null,
  sessions: SessionSummary[],
  recentPaths: string[]
): string[] {
  // 1. machineId 过滤（null → 全部）
  const machineSessions: SessionSummary[] = [];
  for (let i = 0; i < sessions.length; i++) {
    const s: SessionSummary = sessions[i];
    if (machineId === null || sessionMachineId(s) === machineId) {
      machineSessions.push(s);
    }
  }

  // 2. 两源收集（path + worktreeBasePath），过滤空串
  const sessionPaths: string[] = [];
  const worktreePaths: string[] = [];
  for (let i = 0; i < machineSessions.length; i++) {
    const s: SessionSummary = machineSessions[i];
    const p: string = sessionPath(s);
    if (p !== '') { sessionPaths.push(p); }
    const w: string = sessionWorktreeBasePath(s);
    if (w !== '') { worktreePaths.push(w); }
  }

  // 3. dedupedRecent（保序去重）；recentSet 同义（contains 判定用 dedupedRecent）
  const dedupedRecent: string[] = [];
  for (let i = 0; i < recentPaths.length; i++) {
    pushUnique(dedupedRecent, recentPaths[i]);
  }

  // 4. otherPaths = [sessionPaths + worktreePaths] 去重 → 排除 recent → localeCompare 升序
  const otherPaths: string[] = [];
  for (let i = 0; i < sessionPaths.length; i++) {
    pushUnique(otherPaths, sessionPaths[i]);
  }
  for (let i = 0; i < worktreePaths.length; i++) {
    pushUnique(otherPaths, worktreePaths[i]);
  }
  const filtered: string[] = [];
  for (let i = 0; i < otherPaths.length; i++) {
    if (!contains(dedupedRecent, otherPaths[i])) { filtered.push(otherPaths[i]); }
  }
  filtered.sort((a: string, b: string): number => { return a.localeCompare(b); });

  // 5. 拼接：recent 在前 + 其余
  const result: string[] = [];
  for (let i = 0; i < dedupedRecent.length; i++) { result.push(dedupedRecent[i]); }
  for (let i = 0; i < filtered.length; i++) { result.push(filtered[i]); }
  return result;
}
