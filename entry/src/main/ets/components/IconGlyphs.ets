// IconGlyphs —— 消息内容图标 token → sys.symbol Resource 的渲染侧映射（对齐 chatcube 禁 emoji）。
// Presentation / EventPresentation 是纯逻辑层（零 @kit、无 ArkUI 依赖），只产语义 token
//   （'edit'/'bash'/'read'/…/'warning'/'wait'/'package'），不持 $r。本文件是 UI 层：把 token
//   映射成 $r('sys.symbol.X') 字面量。$r 须字符串字面量（不能拼串），故用 switch 逐 token 返回字面量。
// 字形名校验：编译器是唯一可靠判据（resources.txt 不全，但其中列出的复合字形必可编译）。
//   命名规律：HMOS sys.symbol 多用下划线连字符（square_and_pencil / exclamationmark_triangle / globe_and_keyboard），
//   与 SF Symbols 的点号命名对应（square.and.pencil → square_and_pencil）。

// 工具调用图标 token → Resource（对照 Presentation.getToolPresentation 的 icon 字段）。
export function toolGlyph(name: string): Resource {
  switch (name) {
    case 'edit': return $r('sys.symbol.square_and_pencil');        // Edit/Write/MultiEdit/CodexDiff/CodexPatch/NotebookEdit
    case 'bash': return $r('sys.symbol.keyboard');                 // Bash/shell_command/CodexBash（HMOS 无 terminal 字形，用键盘）
    case 'read': return $r('sys.symbol.eye');                      // Read/Grep/NotebookRead/CodexBash(read)
    case 'search': return $r('sys.symbol.magnifyingglass');        // Glob/LS
    case 'todo': return $r('sys.symbol.lightbulb');                // TodoWrite/CodexReasoning
    case 'plan': return $r('sys.symbol.list_bullet');              // update_plan/ExitPlanMode（HMOS 无 clipboard，用清单）
    case 'web': return $r('sys.symbol.globe_and_keyboard');        // WebFetch/WebSearch（globe+keyboard=浏览）
    case 'agent': return $r('sys.symbol.paperplane');              // Task/Agent/CodexAgent/spawn/resume/wait/close
    case 'skill': return $r('sys.symbol.puzzle');                  // MCP__*/Skill
    case 'team': return $r('sys.symbol.person_2');                 // TeamCreate/TeamDelete
    case 'ask': return $r('sys.symbol.questionmark_circle');       // AskUserQuestion/CodexPermission
    case 'message': return $r('sys.symbol.message');               // SendMessage/send_input
    case 'wrench': return $r('sys.symbol.wrench_and_screwdriver'); // 未知工具兜底
    default: return $r('sys.symbol.wrench_and_screwdriver');
  }
}

// 系统消息图标 token → Resource（对照 EventPresentation.getEventPresentation 的 icon 字段）。
//   '' = 无图标（caller 先判空再调本函数；本函数 default 仅兜底防漏）。
export function eventGlyph(name: string): Resource {
  switch (name) {
    case 'warning': return $r('sys.symbol.exclamationmark_triangle');  // api-error / limit-warning
    case 'wait': return $r('sys.symbol.hourglass');                    // retrying / limit-reached
    case 'package': return $r('sys.symbol.archivebox');                // compact / microcompact
    default: return $r('sys.symbol.exclamationmark_triangle');
  }
}

// 工具/子代理状态符号 token → Resource（ToolCard.statusGlyph / ToolGroupCard.stateGlyph /
//   TraceSection.childStateGlyph 产 token，渲染侧调本函数）。对照原 emoji：
//   🔒 pending → lock / ✓ completed → checkmark / ✕ error/denied → xmark /
//   ● running/dot → circle_fill / ⊘ aborted/canceled → nosign。
export function stateGlyph(name: string): Resource {
  switch (name) {
    case 'pending': return $r('sys.symbol.lock');
    case 'completed': return $r('sys.symbol.checkmark');
    case 'error': return $r('sys.symbol.xmark');
    case 'denied': return $r('sys.symbol.xmark');
    case 'running': return $r('sys.symbol.circle_fill');
    case 'dot': return $r('sys.symbol.circle_fill');
    case 'aborted': return $r('sys.symbol.nosign');
    case 'canceled': return $r('sys.symbol.nosign');
    default: return $r('sys.symbol.circle_fill');
  }
}

// 选项选择标记 token → Resource（AskUserQuestionFooter.optionGlyph 产 token）。
//   多选 ☑/☐ → checkmark_square/square；单选 ●/○ → circle_fill/circle。
export function selectGlyph(name: string): Resource {
  switch (name) {
    case 'checkbox_on': return $r('sys.symbol.checkmark_square');
    case 'checkbox_off': return $r('sys.symbol.square');
    case 'radio_on': return $r('sys.symbol.circle_fill');
    case 'radio_off': return $r('sys.symbol.circle');
    default: return $r('sys.symbol.circle');
  }
}

// 清单项状态 → Resource（ChecklistList）。☑ completed → checkmark_square /
//   ◉ in_progress → circle_fill / ☐ pending → square。
export function checklistGlyph(status: string): Resource {
  switch (status) {
    case 'completed': return $r('sys.symbol.checkmark_square');
    case 'in_progress': return $r('sys.symbol.circle_fill');
    default: return $r('sys.symbol.square');
  }
}

// 文件项 token → Resource（FilesPage.fileEmoji 产 token；folder/image/code/doc）。
//   📁 folder / 🖼️ image → picture / 📜 code → doc_plaintext / 📄 doc → doc。
export function fileGlyph(token: string): Resource {
  switch (token) {
    case 'folder': return $r('sys.symbol.folder');
    case 'image': return $r('sys.symbol.picture');
    case 'code': return $r('sys.symbol.doc_plaintext');
    case 'doc': return $r('sys.symbol.doc');
    default: return $r('sys.symbol.doc');
  }
}

// 团队任务状态 → Resource（TeamPanel.taskIcon）。☑ completed → checkmark_square /
//   ▶ in_progress → play_fill / ⚠ blocked → exclamationmark_triangle / ☐ pending → square。
export function taskGlyph(status: string): Resource {
  switch (status) {
    case 'completed': return $r('sys.symbol.checkmark_square');
    case 'in_progress': return $r('sys.symbol.play_fill');
    case 'blocked': return $r('sys.symbol.exclamationmark_triangle');
    default: return $r('sys.symbol.square');
  }
}
