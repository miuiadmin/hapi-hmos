import { promptAction } from '@kit.ArkUI';

// 统一 Toast 工具——取代散落各组件的 ad-hoc
//   `this.getUIContext().getPromptAction().showToast({ message, duration })` 重复（7 处）。
// 全局 promptAction：Stage 模型下窗口存在即可用（调用点均在组件事件回调内，UI 已就绪）。
// duration 单位 ms，默认 2000（对齐既有 showHint 默认）。

export function showToast(message: string, duration: number = 2000): void {
  promptAction.showToast({ message, duration });
}
