// ChatBlockDataSource —— LazyForEach 数据源（流式渲染根治，对照 chatcube ChatMessageListDataSource）。
//
// plain ForEach 的死结：键值不变 → 复用旧子树不刷新（流式内容不增长）；键值随内容变 → 每 token 销毁重建
//   agent-text 项 → MarkdownText 原生组件(Cangjie 引擎)每 ~150ms 销毁重建 → 原生积压 → UI 线程冻结。
//   LazyForEach + 本数据源的 onDataChange(index) 对【单个项原地重渲染】：组件复用、不销毁、
//   MarkdownText/CJMarkdown 保活、仅 content 更新 → 既不依赖 @Trace（berry3 坑7 多场景不刷新）、
//   也不靠键值销毁 → 流式逐字实时增长、无冻结。
//
// setItems(next, sigFn) 按 index diff：
//   末尾追加（发消息/流式新 block，prev 是 next 前缀）→ onDataAdd 增量（仅渲染新项，余者复用，无整列闪烁）；
//   结构变化（头部插入更旧历史/删除/id 漂移/搜索过滤）→ onDataReloaded 全刷；
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
    const prev: ChatBlock[] = this.items;
    const newSigs: string[] = this.computeSigs(next, sigFn);

    // 1) 末尾追加（发消息 optimistic / 流式新 block）：prev 是 next 的前缀 → 增量 onDataAdd，
    //   不全量 reload。reload 会重建全部可见 ListItem（重新 build+measure）→ 整列闪烁/"消息填充屏"；
    //   onDataAdd 仅渲染新增项，余者复用 → 发消息平滑无闪烁（对照 web 末条 append）。
    if (next.length > prev.length) {
      let isAppend: boolean = true;
      for (let i = 0; i < prev.length; i++) {
        if (next[i].id !== prev[i].id) { isAppend = false; break; }
      }
      if (isAppend) {
        const changed: number[] = [];
        for (let i = 0; i < prev.length; i++) {
          if (newSigs[i] !== this.sigs[i]) { changed.push(i); }
        }
        this.items = next;            // 先更数据源（getData/totalCount 通知时返回新数据）
        this.sigs = newSigs;
        for (let i = 0; i < changed.length; i++) { this.notifyChange(changed[i]); }
        for (let i = prev.length; i < next.length; i++) { this.notifyDataAdd(i); }
        return;
      }
    }

    // 1b) 末尾删除（TypingIndicator 关闭：isThinking true→false，prev 末尾的 typing 占位块移除）：
    //   prev 的前 next.length 项 == next（前缀对齐）→ onDataDelete 增量，【不全量 reload】。
    //   不加本分支则落到下方 branch 2（长度不同→reload）→ 整列重建空白（与发送时同症）。从末尾倒序通知，保 index 稳定。
    if (next.length < prev.length) {
      let isTrailingRemove: boolean = true;
      for (let i = 0; i < next.length; i++) {
        if (next[i].id !== prev[i].id) { isTrailingRemove = false; break; }
      }
      if (isTrailingRemove) {
        const changed: number[] = [];
        for (let i = 0; i < next.length; i++) {
          if (newSigs[i] !== this.sigs[i]) { changed.push(i); }
        }
        this.items = next;
        this.sigs = newSigs;
        for (let i = 0; i < changed.length; i++) { this.notifyChange(changed[i]); }
        for (let i = prev.length - 1; i >= next.length; i--) { this.notifyDataDelete(i); }
        return;
      }
    }

    // 2) 长度不同且非末尾追加/删除（头部插入更旧历史 / 序列错位 / 搜索过滤）：真结构变化 → 全量 reload。
    if (next.length !== prev.length) {
      this.items = next;
      this.sigs = newSigs;
      this.notifyReload();
      return;
    }

    // 3) 长度相同（含 optimistic→真实消息替换的【同位置 id 漂移】：user-text 块 id 从 local-xxx 变后端
    //   real-msg-id）：逐 index notifyChange，【不全量 reload】。LazyForEach 按 key(b.id) 复用——id 不变
    //   的项原地刷新（签名变才刷），id 变的项【单项】重建（LazyForEach 检测 key 变销毁旧 ListItem + 建新，
    //   仅该 index，非全量）。旧实现把「同长 + 任一 id 变」当 structural→notifyReload，致发消息后 SSE 回推
    //   真实消息替换 optimistic 时整列重建空白 ~0.5s（"输入框撑大屏幕/消息填充屏"真根因，2026-08-05 修）。
    const changed: number[] = [];
    for (let i = 0; i < next.length; i++) {
      if (next[i].id !== prev[i].id || newSigs[i] !== this.sigs[i]) { changed.push(i); }
    }
    this.items = next;
    this.sigs = newSigs;
    for (let i = 0; i < changed.length; i++) { this.notifyChange(changed[i]); }
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

  private notifyDataAdd(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataAdd(index);
    }
  }

  private notifyDataDelete(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataDelete(index);
    }
  }
}
