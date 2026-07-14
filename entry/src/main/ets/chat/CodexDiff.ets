// CodexDiff 工具的统一 diff 解析（对照 web CodexDiffView.tsx:5-55 parseUnifiedDiff）。
//   零 @kit 纯层：手写行扫描器（ArkTS 禁 regex/replace-fn → startsWith + substring）。
//   把 input.unified_diff 拆成 {oldText,newText,fileName}，喂共享 DiffView（与 Edit/MultiEdit/Write 同套）。

export class CodexDiffParsed {
  oldText: string = '';
  newText: string = '';
  fileName: string = '';   // '' = 未取到（+++ 行缺失）
}

// 从 '+++ b/path' / '+++ path' 提文件名（对照上游 line.replace(/^\+\+\+ (b\/)?/, '')）。
//   '+++ b/' 优先于 '+++ '（前者是后者前缀，须先判）。
function extractFileName(line: string): string {
  if (line.startsWith('+++ b/')) {
    return line.substring(6);
  }
  if (line.startsWith('+++ ')) {
    return line.substring(4);
  }
  return '';
}

// 解析 unified diff 串：逐行扫描，@@ hunk 头内按 +/-/空 行分到 old/new；文件头/元信息/+++ 行跳过或取文件名。
//   空行（hunk 内）→ 双侧各 push 空串（保行对齐）；'\ No newline at end of file' → 跳过。
export function parseUnifiedDiff(unifiedDiff: string): CodexDiffParsed {
  const parsed: CodexDiffParsed = new CodexDiffParsed();
  const oldLines: string[] = [];
  const newLines: string[] = [];
  let inHunk: boolean = false;

  const lines: string[] = unifiedDiff.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line: string = lines[i];

    // +++ 行：取文件名（+++ b/ 优先于 +++ ）
    if (line.startsWith('+++ b/') || line.startsWith('+++ ')) {
      parsed.fileName = extractFileName(line);
      continue;
    }

    // 文件头/元信息行：跳过（--- 须在 hunk 体 +/- 判定前，避免误把 --- 行当删除行）
    if (line.startsWith('diff --git')
      || line.startsWith('index ')
      || line.startsWith('---')
      || line.startsWith('new file mode')
      || line.startsWith('deleted file mode')) {
      continue;
    }

    // hunk 头 @@：进入 hunk
    if (line.startsWith('@@')) {
      inHunk = true;
      continue;
    }

    if (!inHunk) {
      continue;
    }

    // hunk 体行分类
    if (line.startsWith('+')) {
      newLines.push(line.substring(1));
    } else if (line.startsWith('-')) {
      oldLines.push(line.substring(1));
    } else if (line.startsWith(' ')) {
      oldLines.push(line.substring(1));
      newLines.push(line.substring(1));
    } else if (line === '\\ No newline at end of file') {
      continue;
    } else if (line === '') {
      oldLines.push('');
      newLines.push('');
    }
  }

  parsed.oldText = oldLines.join('\n');
  parsed.newText = newLines.join('\n');
  return parsed;
}
