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
  //
  // ★ typing 占位块（id='__typing__'，恒在末尾、内容不变）须从 prev/next 的前缀比对中【剥离】：
  //   流式期间新 agent 块到达时 next=[..blocks, newBlock, __typing__]、prev=[..blocks, __typing__]——
  //   若把 typing 当普通项参与前缀检查，prev 末位 __typing__ vs next 同位 newBlock → 前缀错位 →
  //   落到 lenDiff 分支 ★notifyReload★ → 整列 ListItem 销毁重建 → c.bg 空白一闪（灰板闪烁根因）。
  //   剥离后真实块走 append/insert（onDataAdd），typing 由 LazyForEach 按复用自动顺移，不触发 reload。
  setItems(next: ChatBlock[], sigFn: (b: ChatBlock) => string): void {
    const prev: ChatBlock[] = this.items;
    const oldSigs: string[] = this.sigs;
    const newSigs: string[] = this.computeSigs(next, sigFn);

    // 剥离末尾 typing 占位块（仅判态翻转，内容恒定不参与签名比对）
    const TID: string = '__typing__';
    const prevTyping: boolean = prev.length > 0 && prev[prev.length - 1].id === TID;
    const nextTyping: boolean = next.length > 0 && next[next.length - 1].id === TID;
    const prevRealLen: number = prevTyping ? prev.length - 1 : prev.length;
    const nextRealLen: number = nextTyping ? next.length - 1 : next.length;

    this.items = next;              // 先更数据源（notify 时 getData/totalCount 返回新数据）
    this.sigs = newSigs;

    // 1) 真实块末尾追加（发消息 optimistic / 流式新 agent 块）：prev 真实块是 next 真实块前缀 → onDataAdd。
    //   不全量 reload——reload 会重建全部可见 ListItem（重新 build+measure）→ 整列闪烁/c.bg 灰板一闪。
    //   onDataAdd 仅渲染新增项，余者复用；尾部 typing 由 LazyForEach 复用顺移，无需单独通知。
    if (nextRealLen > prevRealLen) {
      let isAppend: boolean = true;
      for (let i = 0; i < prevRealLen; i++) {
        if (next[i].id !== prev[i].id) { isAppend = false; break; }
      }
      if (isAppend) {
        for (let i = 0; i < prevRealLen; i++) {
          if (newSigs[i] !== oldSigs[i]) { this.notifyChange(i); }
        }
        for (let i = prevRealLen; i < nextRealLen; i++) { this.notifyDataAdd(i); }
        // typing 仅在态翻转时补通知（真实块 append 已让 typing 顺移）
        if (nextTyping && !prevTyping) { this.notifyDataAdd(nextRealLen); }
        return;
      }
    }

    // 1b) 真实块末尾删除：prev 真实块的前 nextRealLen 项 == next 前缀 → 倒序 onDataDelete，不全量 reload。
    //   从高 index 往低删保 index 稳定；typing 若被删（态翻转）先于真实块删（typing index 更高）。
    if (nextRealLen < prevRealLen) {
      let isTrailingRemove: boolean = true;
      for (let i = 0; i < nextRealLen; i++) {
        if (next[i].id !== prev[i].id) { isTrailingRemove = false; break; }
      }
      if (isTrailingRemove) {
        for (let i = 0; i < nextRealLen; i++) {
          if (newSigs[i] !== oldSigs[i]) { this.notifyChange(i); }
        }
        if (prevTyping && !nextTyping) { this.notifyDataDelete(prevRealLen); }
        for (let i = prevRealLen - 1; i >= nextRealLen; i--) { this.notifyDataDelete(i); }
        return;
      }
    }

    // 2) 真实块结构变（长度不同且非末尾追加/删除：头部插入更旧历史 / 序列错位 / 搜索过滤）→ 全量 reload
    //   （typing 随 reload 一起重灌，无需单独通知）。
    if (prevRealLen !== nextRealLen) {
      this.notifyReload();
      return;
    }

    // 3) 真实块同长（含 optimistic→真实消息替换的【同位 id 漂移】：user-text 块 id 从 local-xxx 变后端 real-id）：
    //   逐 index notifyChange，不全量 reload。LazyForEach 按 key(b.id) 复用——id 不变的项原地刷新（签名变才刷），
    //   id 变的项单项重建（LazyForEach 检测 key 变销毁旧 ListItem + 建新，仅该 index，非全量）。再处理 typing 态翻转。
    for (let i = 0; i < nextRealLen; i++) {
      if (next[i].id !== prev[i].id || newSigs[i] !== oldSigs[i]) { this.notifyChange(i); }
    }
    if (nextTyping && !prevTyping) {
      this.notifyDataAdd(nextRealLen);
    } else if (!nextTyping && prevTyping) {
      this.notifyDataDelete(nextRealLen);
    }
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
