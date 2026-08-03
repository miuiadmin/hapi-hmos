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
