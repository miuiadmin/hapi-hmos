// 会话列表「机器→目录」三级分组纯逻辑层（无 @kit，LocalUnit 可测）。
//   对照上游 web/src/components/SessionList.tsx:
//     groupSessionsByDirectory(135-183) + getGroupDisplayName(91-97) + groupByMachine(208-236)
//     + 组内排序(154-159) + 目录组排序(177-182) + 机器组排序(232-235) + isGroupCollapsed(732-740)。
//   差异：本项目 SessionSummaryMetadata 无 worktree 字段（沿用 sessionMatches 取实用子集先例），
//     分组键 = machineId(??__unknown__) + directory(path ?? Other)，无 worktree.basePath 优先级。
//   渲染：flattenGroups 展平为 RenderRow[] 供 Index List 单层 ForEach（机器头/目录头/会话项三态）。

import { SessionSummary } from '../models/Types';

// 兜底标识（对照上游 UNKNOWN_MACHINE_ID / 'Other'）
export const UNKNOWN_MACHINE_ID: string = '__unknown__';
export const OTHER_DIRECTORY: string = 'Other';

// 目录组（机器下某工作目录的会话集合）
export class DirectoryGroup {
  machineId: string = '';            // 真实 id or UNKNOWN_MACHINE_ID
  directory: string = '';            // 真实路径 or OTHER_DIRECTORY（兜底）
  displayName: string = '';          // 末两段名（OTHER_DIRECTORY 时为 ''，由渲染层 i18n）
  sessions: SessionSummary[] = [];   // 组内已排序
}

// 机器组（某机器下若干目录组）
export class MachineGroup {
  machineId: string = '';            // 真实 id or UNKNOWN_MACHINE_ID
  label: string = '';                // 短标识（id 前 8 字符；UNKNOWN → ''，渲染层可被 displayName 覆盖）
  groups: DirectoryGroup[] = [];     // 目录子组，已排序
  totalSessions: number = 0;
}

// 渲染行（展平后单层 ForEach 用；kind 区分三态）
export type RenderRowKind = 'machine' | 'directory' | 'session';
export class RenderRow {
  kind: RenderRowKind = 'session';
  machineGroup: MachineGroup | null = null;       // kind==='machine'
  directoryGroup: DirectoryGroup | null = null;   // kind==='directory'
  session: SessionSummary | null = null;          // kind==='session'
  key: string = '';                                // ForEach 稳定 key
}

// 取会话的分组目录：metadata.path 非空 → path；否则 OTHER_DIRECTORY 兜底。
export function sessionDirectory(s: SessionSummary): string {
  const path: string = s.metadata !== null ? s.metadata.path : '';
  return path !== '' ? path : OTHER_DIRECTORY;
}

// 取会话的机器 id：metadata.machineId 非空 → id；否则 UNKNOWN_MACHINE_ID 兜底。
export function sessionMachineId(s: SessionSummary): string {
  const mid: string = s.metadata !== null ? s.metadata.machineId : '';
  return mid !== '' ? mid : UNKNOWN_MACHINE_ID;
}

// 目录显示名：末两段 '/' 连接（对照上游 getGroupDisplayName）。
//   '/a/b/c' → 'b/c'；'/a' → 'a'；'a' → 'a'；全斜杠/空 → ''。
//   OTHER_DIRECTORY 由渲染层 i18n，本函数仅处理真实路径。
export function getGroupDisplayName(directory: string): string {
  if (directory === '') { return ''; }
  const all: string[] = [];
  let cur: string = '';
  for (let i = 0; i < directory.length; i++) {
    const ch: string = directory.charAt(i);
    if (ch === '/') {
      if (cur !== '') { all.push(cur); cur = ''; }
    } else {
      cur += ch;
    }
  }
  if (cur !== '') { all.push(cur); }
  const n: number = all.length;
  if (n === 0) { return ''; }
  const a: string = n >= 2 ? all[n - 2] : '';
  const b: string = all[n - 1];
  return a !== '' ? `${a}/${b}` : b;
}

// 机器短标识（id 前 8 字符；UNKNOWN/空 → ''）。渲染层可被 machine.displayName 覆盖。
export function shortMachineLabel(machineId: string): string {
  if (machineId === UNKNOWN_MACHINE_ID || machineId === '') { return ''; }
  return machineId.length > 8 ? machineId.substring(0, 8) : machineId;
}

// 会话排序权重：active+pending(0) → active(1) → inactive(2)（对照上游 SessionList.tsx:154-159）。
function sessionSortRank(s: SessionSummary): number {
  if (s.active && s.pendingRequestsCount > 0) { return 0; }
  if (s.active) { return 1; }
  return 2;
}

// 组内会话排序：rank 升序，同 rank updatedAt 降序（返回新数组，不污染入参）。
export function sortSessionsWithinGroup(sessions: SessionSummary[]): SessionSummary[] {
  const arr: SessionSummary[] = sessions.slice();
  arr.sort((x: SessionSummary, y: SessionSummary): number => {
    const rx: number = sessionSortRank(x);
    const ry: number = sessionSortRank(y);
    if (rx !== ry) { return rx - ry; }
    return y.updatedAt - x.updatedAt;
  });
  return arr;
}

// 目录组是否有活跃会话。
export function directoryGroupHasActive(g: DirectoryGroup): boolean {
  for (let i = 0; i < g.sessions.length; i++) {
    if (g.sessions[i].active) { return true; }
  }
  return false;
}

// 目录组最新 updatedAt（空组 → 0）。
function directoryGroupLatestUpdatedAt(g: DirectoryGroup): number {
  let latest: number = 0;
  for (let i = 0; i < g.sessions.length; i++) {
    if (g.sessions[i].updatedAt > latest) { latest = g.sessions[i].updatedAt; }
  }
  return latest;
}

// 机器组是否有活跃会话。
export function machineGroupHasActive(mg: MachineGroup): boolean {
  for (let i = 0; i < mg.groups.length; i++) {
    if (directoryGroupHasActive(mg.groups[i])) { return true; }
  }
  return false;
}

// 机器组最新 updatedAt。
function machineGroupLatestUpdatedAt(mg: MachineGroup): number {
  let latest: number = 0;
  for (let i = 0; i < mg.groups.length; i++) {
    const t: number = directoryGroupLatestUpdatedAt(mg.groups[i]);
    if (t > latest) { latest = t; }
  }
  return latest;
}

// 目录组排序：有活跃优先，同档 latestUpdatedAt 降序（对照上游 177-182；返回新数组）。
export function sortDirectoryGroups(groups: DirectoryGroup[]): DirectoryGroup[] {
  const arr: DirectoryGroup[] = groups.slice();
  arr.sort((x: DirectoryGroup, y: DirectoryGroup): number => {
    const ax: boolean = directoryGroupHasActive(x);
    const ay: boolean = directoryGroupHasActive(y);
    if (ax !== ay) { return ax ? -1 : 1; }   // 活跃在前
    return directoryGroupLatestUpdatedAt(y) - directoryGroupLatestUpdatedAt(x);
  });
  return arr;
}

// 机器组排序：同策略（对照上游 232-235）。
export function sortMachineGroups(machines: MachineGroup[]): MachineGroup[] {
  const arr: MachineGroup[] = machines.slice();
  arr.sort((x: MachineGroup, y: MachineGroup): number => {
    const ax: boolean = machineGroupHasActive(x);
    const ay: boolean = machineGroupHasActive(y);
    if (ax !== ay) { return ax ? -1 : 1; }
    return machineGroupLatestUpdatedAt(y) - machineGroupLatestUpdatedAt(x);
  });
  return arr;
}

// 主入口：会话列表 → 机器组（机器→目录两级分桶 + 各级排序）。
export function groupSessionsByDirectory(sessions: SessionSummary[]): MachineGroup[] {
  // 1. 机器分桶
  const machineBuckets: Map<string, SessionSummary[]> = new Map<string, SessionSummary[]>();
  for (let i = 0; i < sessions.length; i++) {
    const s: SessionSummary = sessions[i];
    const mid: string = sessionMachineId(s);
    const existing: SessionSummary[] | undefined = machineBuckets.get(mid);
    if (existing === undefined) {
      const fresh: SessionSummary[] = [];
      fresh.push(s);
      machineBuckets.set(mid, fresh);
    } else {
      existing.push(s);
    }
  }
  // 2. 逐机器建组
  const mgs: MachineGroup[] = [];
  machineBuckets.forEach((bucket: SessionSummary[], mid: string) => {
    // 2a. 目录分桶
    const dirBuckets: Map<string, SessionSummary[]> = new Map<string, SessionSummary[]>();
    for (let i = 0; i < bucket.length; i++) {
      const s: SessionSummary = bucket[i];
      const dir: string = sessionDirectory(s);
      const existing: SessionSummary[] | undefined = dirBuckets.get(dir);
      if (existing === undefined) {
        const fresh: SessionSummary[] = [];
        fresh.push(s);
        dirBuckets.set(dir, fresh);
      } else {
        existing.push(s);
      }
    }
    // 2b. 目录组
    const dgs: DirectoryGroup[] = [];
    let total: number = 0;
    dirBuckets.forEach((db: SessionSummary[], dir: string) => {
      const dg: DirectoryGroup = new DirectoryGroup();
      dg.machineId = mid;
      dg.directory = dir;
      dg.displayName = dir === OTHER_DIRECTORY ? '' : getGroupDisplayName(dir);
      dg.sessions = sortSessionsWithinGroup(db);
      dgs.push(dg);
      total += db.length;
    });
    const mg: MachineGroup = new MachineGroup();
    mg.machineId = mid;
    mg.label = shortMachineLabel(mid);
    mg.groups = sortDirectoryGroups(dgs);
    mg.totalSessions = total;
    mgs.push(mg);
  });
  return sortMachineGroups(mgs);
}

// 目录组行 key（机器+目录唯一；折叠态 override 用）。
export function directoryGroupKey(dg: DirectoryGroup): string {
  return `${dg.machineId}::${dg.directory}`;
}

// 折叠判定（纯函数，对照上游 isGroupCollapsed 732-740 语义）：
//   搜索中 → 恒展开；用户显式 override → 取 override 值；否则无活跃会话的组默认折叠。
export function isGroupCollapsed(
  key: string, hasActive: boolean, isSearching: boolean, override: Map<string, boolean>
): boolean {
  if (isSearching) { return false; }
  if (override.has(key)) { return override.get(key) as boolean; }
  return !hasActive;
}

// 展平为 RenderRow[]（按折叠态展开/收起；机器头 → [目录头 → 会话项…]…）。
export function flattenGroups(
  mgs: MachineGroup[], isSearching: boolean, override: Map<string, boolean>
): RenderRow[] {
  const rows: RenderRow[] = [];
  for (let i = 0; i < mgs.length; i++) {
    const mg: MachineGroup = mgs[i];
    const mRow: RenderRow = new RenderRow();
    mRow.kind = 'machine';
    mRow.machineGroup = mg;
    mRow.key = `m:${mg.machineId}`;
    rows.push(mRow);

    const machineCollapsed: boolean = isGroupCollapsed(mg.machineId, machineGroupHasActive(mg), isSearching, override);
    if (machineCollapsed) { continue; }

    for (let j = 0; j < mg.groups.length; j++) {
      const dg: DirectoryGroup = mg.groups[j];
      const dRow: RenderRow = new RenderRow();
      dRow.kind = 'directory';
      dRow.directoryGroup = dg;
      dRow.key = `d:${directoryGroupKey(dg)}`;
      rows.push(dRow);

      const dirKey: string = directoryGroupKey(dg);
      const dirCollapsed: boolean = isGroupCollapsed(dirKey, directoryGroupHasActive(dg), isSearching, override);
      if (dirCollapsed) { continue; }

      for (let k = 0; k < dg.sessions.length; k++) {
        const s: SessionSummary = dg.sessions[k];
        const sRow: RenderRow = new RenderRow();
        sRow.kind = 'session';
        sRow.session = s;
        sRow.key = `s:${s.id}`;
        rows.push(sRow);
      }
    }
  }
  return rows;
}
