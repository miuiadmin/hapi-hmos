// ToolActionState —— 工具审批的 UI 编排态（loading/decided/error）。
// 原为 ToolCard @Local；动态键值（ChatPage.blockKey）致 ToolCard 重建后 @Local 丢失 → 双提交风险，
// 故上提到 ChatPage 按 block.id 持久（toolActionStates Record），ToolCard 经 @Param 只读、@Event onAction 回调执行。
// 纯数据类（chat 层，无 ArkUI 依赖）；ChatPage.setToolAction 每次整体替换 Record 触发 blockKey 重算 → 重建刷新。
// （不走 @ObservedV2+@Trace 原地刷新：避 berry3 坑7「@Trace 经 @Param/@Consumer 不触发 build」风险。）

export class ToolActionState {
  actionLoading: string = '';   // ''|'allow'|'session'|'alledits'|'deny'|'abort'（PermissionFooter 据此显 spinner）
  decided: boolean = false;       // 任一审批成功后置位：防 SSE 翻转前重复点击（对齐答题 footer 的 done）
  actionError: string = '';
}
