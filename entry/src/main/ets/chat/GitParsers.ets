// Git 状态解析纯逻辑（对照 web/src/lib/gitParsers.ts）。
// 输入：hub git-status / git-diff-numstat 的 CommandResponse.stdout（git --porcelain=v2 --branch + numstat 原文）。
// 输出：结构化 GitStatusFiles（staged/unstaged + 每文件状态 + ±行数 + 分支）。
//
// 纯逻辑、无 ArkUI 依赖 → LocalUnit 可测。ArkTS 适配点：
//   1. String.replace(regexp, fn) 在 ArkTS 不稳 → normalizeNumstatPath 手写 indexOf/substring 重写。
//   2. Record<string,X> 动态键 → createDiffStatsMap 用 Map<string, DiffStat>。
//   3. 可选 number（ahead/behind/exitCode）→ -1 哨兵；可选 string（from/oldPath）→ '' 空串。

// porcelain v2 行类型，结构化中间态
export class GitFileEntryV2 {
  path: string = '';
  index: string = '';        // 暂存区状态字符（'M'/'A'/'D'/'R'/' '...）
  workingDir: string = '';   // 工作区状态字符
  from: string = '';         // rename/copy 的源路径（无则 ''）
}

export class GitBranchInfo {
  oid: string = '';
  head: string = '';         // branch.head（'(detached)'/'(initial)' 或分支名）
  upstream: string = '';
  ahead: number = -1;        // -1 哨兵 = 未知
  behind: number = -1;
}

export class GitStatusSummaryV2 {
  files: GitFileEntryV2[] = [];
  notAdded: string[] = [];   // untracked 路径
  ignored: string[] = [];
  branch: GitBranchInfo = new GitBranchInfo();
}

export class DiffFileStat {
  file: string = '';
  changes: number = 0;
  insertions: number = 0;
  deletions: number = 0;
  binary: boolean = false;
}

export class DiffSummary {
  files: DiffFileStat[] = [];
  insertions: number = 0;
  deletions: number = 0;
  changes: number = 0;
  changed: number = 0;
}

// numstat 单文件统计（createDiffStatsMap 的值）
export class DiffStat {
  added: number = 0;
  removed: number = 0;
  binary: boolean = false;
}

// —— 结果类型（UI 直接消费；与 web types/api.ts GitFileStatus 对齐）——
export type GitFileStatusType = 'modified' | 'added' | 'deleted' | 'renamed' | 'untracked' | 'conflicted';

export class GitFileStatus {
  fileName: string = '';
  filePath: string = '';       // 目录部分（不含文件名）
  fullPath: string = '';
  status: GitFileStatusType = 'modified';
  isStaged: boolean = false;
  linesAdded: number = 0;
  linesRemoved: number = 0;
  oldPath: string = '';        // rename 源（'' 表示无）
}

export class GitStatusFiles {
  stagedFiles: GitFileStatus[] = [];
  unstagedFiles: GitFileStatus[] = [];
  branch: string = '';         // '' = 未知/分离头
  totalStaged: number = 0;
  totalUnstaged: number = 0;
}

// —— porcelain v2 行正则（与上游一一对应）——
const BRANCH_OID_REGEX: RegExp = /^# branch\.oid (.+)$/;
const BRANCH_HEAD_REGEX: RegExp = /^# branch\.head (.+)$/;
const BRANCH_UPSTREAM_REGEX: RegExp = /^# branch\.upstream (.+)$/;
const BRANCH_AB_REGEX: RegExp = /^# branch\.ab \+(\d+) -(\d+)$/;
const ORDINARY_CHANGE_REGEX: RegExp = /^1 (.)(.) (.{4}) (\d{6}) (\d{6}) (\d{6}) ([0-9a-f]+) ([0-9a-f]+) (.+)$/;
const RENAME_COPY_REGEX: RegExp = /^2 (.)(.) (.{4}) (\d{6}) (\d{6}) (\d{6}) ([0-9a-f]+) ([0-9a-f]+) ([RC])(\d{1,3}) (.+)\t(.+)$/;
const UNMERGED_REGEX: RegExp = /^u (.)(.) (.{4}) (\d{6}) (\d{6}) (\d{6}) ([0-9a-f]+) ([0-9a-f]+) ([0-9a-f]+) (.+)$/;
const UNTRACKED_REGEX: RegExp = /^\? (.+)$/;
const IGNORED_REGEX: RegExp = /^! (.+)$/;
const NUMSTAT_REGEX: RegExp = /^(\d+|-)\t(\d+|-)\t(.*)$/;

// 按 \n 切行（trim 整体 + 过滤空行）；空串→空数组
function splitLines(output: string): string[] {
  const trimmed: string = output.trim();
  if (trimmed === '') { return []; }
  const raw: string[] = trimmed.split('\n');
  const out: string[] = [];
  for (let i = 0; i < raw.length; i++) {
    if (raw[i].length > 0) { out.push(raw[i]); }
  }
  return out;
}

export function parseStatusSummaryV2(statusOutput: string): GitStatusSummaryV2 {
  const lines: string[] = splitLines(statusOutput);
  const result: GitStatusSummaryV2 = new GitStatusSummaryV2();

  for (let i = 0; i < lines.length; i++) {
    const line: string = lines[i];

    if (line.startsWith('# branch.oid ')) {
      const m: RegExpExecArray | null = BRANCH_OID_REGEX.exec(line);
      if (m !== null) { result.branch.oid = m[1]; }
      continue;
    }
    if (line.startsWith('# branch.head ')) {
      const m: RegExpExecArray | null = BRANCH_HEAD_REGEX.exec(line);
      if (m !== null) { result.branch.head = m[1]; }
      continue;
    }
    if (line.startsWith('# branch.upstream ')) {
      const m: RegExpExecArray | null = BRANCH_UPSTREAM_REGEX.exec(line);
      if (m !== null) { result.branch.upstream = m[1]; }
      continue;
    }
    if (line.startsWith('# branch.ab ')) {
      const m: RegExpExecArray | null = BRANCH_AB_REGEX.exec(line);
      if (m !== null) {
        result.branch.ahead = parseInt(m[1], 10);
        result.branch.behind = parseInt(m[2], 10);
      }
      continue;
    }

    if (line.startsWith('1 ')) {
      const m: RegExpExecArray | null = ORDINARY_CHANGE_REGEX.exec(line);
      if (m !== null) {
        const entry: GitFileEntryV2 | null = parseOrdinaryChange(m);
        if (entry !== null) { result.files.push(entry); }
      }
      continue;
    }
    if (line.startsWith('2 ')) {
      const m: RegExpExecArray | null = RENAME_COPY_REGEX.exec(line);
      if (m !== null) {
        const entry: GitFileEntryV2 | null = parseRenameCopy(m);
        if (entry !== null) { result.files.push(entry); }
      }
      continue;
    }
    if (line.startsWith('u ')) {
      const m: RegExpExecArray | null = UNMERGED_REGEX.exec(line);
      if (m !== null) {
        const entry: GitFileEntryV2 | null = parseUnmerged(m);
        if (entry !== null) { result.files.push(entry); }
      }
      continue;
    }
    if (line.startsWith('? ')) {
      const m: RegExpExecArray | null = UNTRACKED_REGEX.exec(line);
      if (m !== null) { result.notAdded.push(m[1]); }
      continue;
    }
    if (line.startsWith('! ')) {
      const m: RegExpExecArray | null = IGNORED_REGEX.exec(line);
      if (m !== null) { result.ignored.push(m[1]); }
    }
  }
  return result;
}

export function parseNumStat(numStatOutput: string): DiffSummary {
  const lines: string[] = splitLines(numStatOutput);
  const result: DiffSummary = new DiffSummary();

  for (let i = 0; i < lines.length; i++) {
    const m: RegExpExecArray | null = NUMSTAT_REGEX.exec(lines[i]);
    if (m === null) { continue; }
    const insertionsStr: string = m[1];
    const deletionsStr: string = m[2];
    const file: string = m[3];

    const isBinary: boolean = insertionsStr === '-' || deletionsStr === '-';
    const insertions: number = isBinary ? 0 : parseInt(insertionsStr, 10);
    const deletions: number = isBinary ? 0 : parseInt(deletionsStr, 10);
    const changes: number = insertions + deletions;

    const stat: DiffFileStat = new DiffFileStat();
    stat.file = file;
    stat.changes = changes;
    stat.insertions = insertions;
    stat.deletions = deletions;
    stat.binary = isBinary;
    result.files.push(stat);

    result.insertions += insertions;
    result.deletions += deletions;
    result.changes += changes;
    result.changed += 1;
  }
  return result;
}

export function createDiffStatsMap(summary: DiffSummary): Map<string, DiffStat> {
  const stats: Map<string, DiffStat> = new Map();
  for (let i = 0; i < summary.files.length; i++) {
    const f: DiffFileStat = summary.files[i];
    const paths: PathPair = normalizeNumstatPath(f.file);
    const stat: DiffStat = new DiffStat();
    stat.added = f.insertions;
    stat.removed = f.deletions;
    stat.binary = f.binary;

    stats.set(f.file, stat);
    if (paths.newPath !== '' && paths.newPath !== f.file) { stats.set(paths.newPath, stat); }
    if (paths.oldPath !== '' && paths.oldPath !== f.file && paths.oldPath !== paths.newPath) {
      stats.set(paths.oldPath, stat);
    }
  }
  return stats;
}

export function getCurrentBranchV2(summary: GitStatusSummaryV2): string {
  const head: string = summary.branch.head;
  if (head === '' || head === '(detached)' || head === '(initial)') { return ''; }
  return head;
}

export function buildGitStatusFiles(
  statusOutput: string,
  unstagedDiffOutput: string,
  stagedDiffOutput: string
): GitStatusFiles {
  const statusSummary: GitStatusSummaryV2 = parseStatusSummaryV2(statusOutput);
  const branchName: string = getCurrentBranchV2(statusSummary);

  const unstagedDiff: DiffSummary = parseNumStat(unstagedDiffOutput);
  const stagedDiff: DiffSummary = parseNumStat(stagedDiffOutput);
  const unstagedStats: Map<string, DiffStat> = createDiffStatsMap(unstagedDiff);
  const stagedStats: Map<string, DiffStat> = createDiffStatsMap(stagedDiff);

  const result: GitStatusFiles = new GitStatusFiles();

  for (let i = 0; i < statusSummary.files.length; i++) {
    const file: GitFileEntryV2 = statusSummary.files[i];
    const parts: string[] = file.path.split('/');
    const fileName: string = parts[parts.length - 1].length > 0 ? parts[parts.length - 1] : file.path;
    const filePath: string = parts.slice(0, parts.length - 1).join('/');

    if (file.index !== ' ' && file.index !== '.' && file.index !== '?') {
      const status: GitFileStatusType = getFileStatus(file.index);
      const raw: DiffStat | undefined = stagedStats.get(file.path);
      const stat: DiffStat = raw !== undefined ? raw : new DiffStat();
      const fs: GitFileStatus = new GitFileStatus();
      fs.fileName = fileName;
      fs.filePath = filePath;
      fs.fullPath = file.path;
      fs.status = status;
      fs.isStaged = true;
      fs.linesAdded = stat.added;
      fs.linesRemoved = stat.removed;
      fs.oldPath = file.from;
      result.stagedFiles.push(fs);
    }

    if (file.workingDir !== ' ' && file.workingDir !== '.') {
      const status: GitFileStatusType = getFileStatus(file.workingDir);
      const raw: DiffStat | undefined = unstagedStats.get(file.path);
      const stat: DiffStat = raw !== undefined ? raw : new DiffStat();
      const fs: GitFileStatus = new GitFileStatus();
      fs.fileName = fileName;
      fs.filePath = filePath;
      fs.fullPath = file.path;
      fs.status = status;
      fs.isStaged = false;
      fs.linesAdded = stat.added;
      fs.linesRemoved = stat.removed;
      fs.oldPath = file.from;
      result.unstagedFiles.push(fs);
    }
  }

  for (let i = 0; i < statusSummary.notAdded.length; i++) {
    const untrackedPath: string = statusSummary.notAdded[i];
    if (untrackedPath.endsWith('/')) { continue; }   // 目录占位跳过
    const parts: string[] = untrackedPath.split('/');
    const fileName: string = parts[parts.length - 1].length > 0 ? parts[parts.length - 1] : untrackedPath;
    const filePath: string = parts.slice(0, parts.length - 1).join('/');
    const fs: GitFileStatus = new GitFileStatus();
    fs.fileName = fileName;
    fs.filePath = filePath;
    fs.fullPath = untrackedPath;
    fs.status = 'untracked';
    fs.isStaged = false;
    fs.linesAdded = 0;
    fs.linesRemoved = 0;
    result.unstagedFiles.push(fs);
  }

  result.branch = branchName;
  result.totalStaged = result.stagedFiles.length;
  result.totalUnstaged = result.unstagedFiles.length;
  return result;
}

function parseOrdinaryChange(matches: RegExpExecArray): GitFileEntryV2 | null {
  if (matches[1] === undefined || matches[2] === undefined || matches[9] === undefined) { return null; }
  const e: GitFileEntryV2 = new GitFileEntryV2();
  e.index = matches[1];
  e.workingDir = matches[2];
  e.path = matches[9];
  return e;
}

function parseRenameCopy(matches: RegExpExecArray): GitFileEntryV2 | null {
  if (matches[1] === undefined || matches[2] === undefined || matches[11] === undefined || matches[12] === undefined) {
    return null;
  }
  const e: GitFileEntryV2 = new GitFileEntryV2();
  e.index = matches[1];
  e.workingDir = matches[2];
  e.from = matches[11];
  e.path = matches[12];
  return e;
}

function parseUnmerged(matches: RegExpExecArray): GitFileEntryV2 | null {
  if (matches[1] === undefined || matches[2] === undefined || matches[11] === undefined) { return null; }
  const e: GitFileEntryV2 = new GitFileEntryV2();
  e.index = matches[1];
  e.workingDir = matches[2];
  e.path = matches[11];
  return e;
}

export function getFileStatus(statusChar: string): GitFileStatusType {
  if (statusChar === 'M') { return 'modified'; }
  if (statusChar === 'A') { return 'added'; }
  if (statusChar === 'D') { return 'deleted'; }
  if (statusChar === 'R' || statusChar === 'C') { return 'renamed'; }
  if (statusChar === '?') { return 'untracked'; }
  if (statusChar === 'U') { return 'conflicted'; }
  return 'modified';
}

// numstat 路径重命名归一化。两种形式：
//   1) prefix{old => new}suffix（花括号内重命名）
//   2) old => new（整段重命名，无花括号）
// ArkTS 不用 String.replace(regexp, fn) ——手写 indexOf/substring。
class PathPair {
  newPath: string = '';
  oldPath: string = '';
}

export function normalizeNumstatPath(rawPath: string): PathPair {
  const trimmed: string = rawPath.trim();
  const braceStart: number = trimmed.indexOf('{');
  const arrowIdx: number = trimmed.indexOf('=>');
  const braceEnd: number = trimmed.indexOf('}');

  // case 1: 含 {... => ...}
  if (braceStart >= 0 && arrowIdx > braceStart && braceEnd > arrowIdx) {
    const inner: string = trimmed.substring(braceStart + 1, braceEnd);
    const ai: number = inner.indexOf('=>');
    if (ai >= 0) {
      const oldPart: string = inner.substring(0, ai).trim();
      const newPart: string = inner.substring(ai + 2).trim();
      const prefix: string = trimmed.substring(0, braceStart);
      const suffix: string = trimmed.substring(braceEnd + 1);
      const pair: PathPair = new PathPair();
      pair.newPath = `${prefix}${newPart}${suffix}`;
      pair.oldPath = `${prefix}${oldPart}${suffix}`;
      return pair;
    }
  }

  // case 2: "old => new"（无花括号）
  if (arrowIdx >= 0) {
    const oldPath: string = trimmed.substring(0, arrowIdx).trim();
    const newPath: string = trimmed.substring(arrowIdx + 2).trim();
    if (newPath !== '') {
      const pair: PathPair = new PathPair();
      pair.newPath = newPath;
      pair.oldPath = oldPath;
      return pair;
    }
  }

  const plain: PathPair = new PathPair();
  plain.newPath = trimmed;
  return plain;
}
