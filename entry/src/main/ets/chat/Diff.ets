// Diff —— 对照 web/src/components/DiffView.tsx
// 上游用 jsdiff 的 diffLines；ArkTS 无该库，此处手写 LCS 行级 diff，等价产出 added/removed/unchanged 行。
// 纯逻辑，无 ArkUI 依赖。供 components/DiffView 使用。
// 算法：经典 LCS 二维 DP + 回溯，O(n*m)。Edit/Write 片段通常很小；全增/全删走快速路径（O(n)）。
// 结果缓存：components/DiffView 用 @Computed 持有，避免每帧重算（大文件重写单次可接受）。

export type DiffLineType = 'added' | 'removed' | 'unchanged';

export class DiffLine {
  type: DiffLineType = 'unchanged';
  text: string = '';
  oldLine: number = 0;   // 0 = 无旧行（added）
  newLine: number = 0;   // 0 = 无新行（removed）
}

export class DiffStats {
  additions: number = 0;
  deletions: number = 0;
  oldLines: number = 0;  // 旧行总数（最大旧行号）
  newLines: number = 0;  // 新行总数（最大新行号）
}

// 按行切分：末尾若因 '\n' 产生空串则丢掉（对照上游 splitDiffLines）
export function splitDiffLines(text: string): string[] {
  if (text.length === 0) {
    return [];
  }
  const lines: string[] = text.split('\n');
  if (lines.length > 0 && lines[lines.length - 1] === '') {
    lines.splice(lines.length - 1, 1);
  }
  return lines;
}

// 行级 diff 主入口：LCS DP + 回溯 → DiffLine[]（按原序排列 added/removed/unchanged）
export function computeDiff(oldStr: string, newStr: string): DiffLine[] {
  const a: string[] = splitDiffLines(oldStr);
  const b: string[] = splitDiffLines(newStr);
  const m: number = a.length;
  const n: number = b.length;

  // 全增 / 全删 快速路径（避免大文件 Write 的 O(n*m) 爆炸）
  if (m === 0 && n === 0) {
    return [];
  }
  if (m === 0) {
    const out: DiffLine[] = [];
    for (let j = 1; j <= n; j++) {
      const dl: DiffLine = new DiffLine();
      dl.type = 'added';
      dl.text = b[j - 1];
      dl.oldLine = 0;
      dl.newLine = j;
      out.push(dl);
    }
    return out;
  }
  if (n === 0) {
    const out: DiffLine[] = [];
    for (let i = 1; i <= m; i++) {
      const dl: DiffLine = new DiffLine();
      dl.type = 'removed';
      dl.text = a[i - 1];
      dl.oldLine = i;
      dl.newLine = 0;
      out.push(dl);
    }
    return out;
  }

  // LCS 长度表 (m+1) x (n+1)
  const dp: number[][] = createMatrix(m + 1, n + 1);
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      if (a[i - 1] === b[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        const up: number = dp[i - 1][j];
        const left: number = dp[i][j - 1];
        dp[i][j] = up >= left ? up : left;
      }
    }
  }

  // 回溯（逆序收集后翻转）。相等代价优先 removed（贴近 jsdiff「先删后增」观感）
  const out: DiffLine[] = [];
  let i: number = m;
  let j: number = n;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && a[i - 1] === b[j - 1]) {
      const dl: DiffLine = new DiffLine();
      dl.type = 'unchanged';
      dl.text = a[i - 1];
      dl.oldLine = i;
      dl.newLine = j;
      out.push(dl);
      i--;
      j--;
    } else if (j > 0 && (i === 0 || dp[i][j - 1] > dp[i - 1][j])) {
      const dl: DiffLine = new DiffLine();
      dl.type = 'added';
      dl.text = b[j - 1];
      dl.oldLine = 0;
      dl.newLine = j;
      out.push(dl);
      j--;
    } else {
      const dl: DiffLine = new DiffLine();
      dl.type = 'removed';
      dl.text = a[i - 1];
      dl.oldLine = i;
      dl.newLine = 0;
      out.push(dl);
      i--;
    }
  }
  reverseDiffLines(out);
  return out;
}

function createMatrix(rows: number, cols: number): number[][] {
  const m: number[][] = [];
  for (let i = 0; i < rows; i++) {
    const row: number[] = [];
    for (let j = 0; j < cols; j++) {
      row.push(0);
    }
    m.push(row);
  }
  return m;
}

function reverseDiffLines(arr: DiffLine[]): void {
  let l: number = 0;
  let r: number = arr.length - 1;
  while (l < r) {
    const tmp: DiffLine = arr[l];
    arr[l] = arr[r];
    arr[r] = tmp;
    l++;
    r--;
  }
}

// 统计：added/removed 行数 + 旧/新总行数（+N -M 角标 + X→Y lines 用）
export function computeDiffStats(lines: DiffLine[]): DiffStats {
  const s: DiffStats = new DiffStats();
  for (let i = 0; i < lines.length; i++) {
    const dl: DiffLine = lines[i];
    if (dl.type === 'added') {
      s.additions++;
      if (dl.newLine > s.newLines) {
        s.newLines = dl.newLine;
      }
    } else if (dl.type === 'removed') {
      s.deletions++;
      if (dl.oldLine > s.oldLines) {
        s.oldLines = dl.oldLine;
      }
    } else {
      if (dl.oldLine > s.oldLines) {
        s.oldLines = dl.oldLine;
      }
      if (dl.newLine > s.newLines) {
        s.newLines = dl.newLine;
      }
    }
  }
  return s;
}
