// ChatBlockDataSource —— LazyForEach 数据源（流式渲染根治，对照 chatcube ChatMessageListDataSource）。
//
// plain ForEach 的死结：键值不变 → 复用旧子树不刷新（流式内容不增长）；键值随内容变 → 每 token 销毁重建
//   agent-text 项 → MarkdownText 原生组件(Cangjie 引擎)每 ~150ms 销毁重建 → 原生积压 → UI 线程冻结。
//   LazyForEach + 本数据源的 onDataChange(index) 对【单个项原地重渲染】：组件复用、不销毁、
//   MarkdownText/CJMarkdown 保活、仅 content 更新 → 既不依赖 @Trace（berry3 坑7 多场景不刷新）、
//   也不靠键值销毁 → 流式逐字实时增长、无冻结。
//
// setItems(next, sigFn) 按 index diff：
//   结构变化（长度变 / 任一 index 的 id 漂移，如新消息/加载更旧/搜索过滤）→ onDataReloaded 全刷；
//   同结构 → 逐 index 比签名 sigFn(b)，仅对变化 index 调 onDataChange → 单项原地刷新。
//   流式只改末块 text → 仅 onDataChange(末块) → 一次单项刷新。
//
// 签名 sigFn 由 ChatPage 注入（含 toolActionStates/detailOpenSigs 等实例态）→ 本类自持 ChatBlock[],
//   不持 ChatPage 状态，保持纯数据源。IDataSource / DataChangeListener 为 ArkUI 全局类型（无需 import）。

import { ChatBlock } from './ChatBlock';

export class ChatBlockDataSource implements IDataSource {
  private items: ChatBlock[] = [];
  private sigs: string[] = [];                 // 与 items 对齐的签名缓存（上次 setItems 时由 sigFn 算得）
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ChatBlock {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    // 手写过滤（避 ArkTS strict 数组回调限制；同本仓 Record 替换范式）
    const next: DataChangeListener[] = [];
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] !== listener) {
        next.push(this.listeners[i]);
      }
    }
    this.listeners = next;
  }

  // 整体替换展示集并按 index 增量通知。sigFn(b) 由调用方提供（反映 ChatPage 实例态的变更指纹）。
  setItems(next: ChatBlock[], sigFn: (b: ChatBlock) => string): void {
    const structural: boolean = this.items.length !== next.length || this.idsMismatch(this.items, next);
    if (structural) {
      this.items = next;
      this.sigs = this.computeSigs(next, sigFn);
      this.notifyReload();
      return;
    }
    // 同结构：逐 index 比签名，仅变者通知（流式恒命中末块，单项原地刷新）
    const newSigs: string[] = this.computeSigs(next, sigFn);
    const changed: number[] = [];
    for (let i = 0; i < next.length; i++) {
      if (newSigs[i] !== this.sigs[i]) {
        changed.push(i);
      }
    }
    this.items = next;
    this.sigs = newSigs;
    for (let i = 0; i < changed.length; i++) {
      this.notifyChange(changed[i]);
    }
  }

  private idsMismatch(a: ChatBlock[], b: ChatBlock[]): boolean {
    for (let i = 0; i < a.length; i++) {
      if (a[i].id !== b[i].id) {
        return true;
      }
    }
    return false;
  }

  private computeSigs(arr: ChatBlock[], sigFn: (b: ChatBlock) => string): string[] {
    const out: string[] = [];
    for (let i = 0; i < arr.length; i++) {
      out.push(sigFn(arr[i]));
    }
    return out;
  }

  private notifyReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  private notifyChange(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(index);
    }
  }
}
