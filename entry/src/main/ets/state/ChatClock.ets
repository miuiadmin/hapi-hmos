// 全局秒级时钟（running 工具卡 elapsed 实时刷新用）。
//
// 为什么不放在 ChatPage 作 @Local nowTick：@Local 被 build() 读到（如旧 LazyForEach 生成器里
//   `nowTick: this.isRunningBlock(b)?this.nowTick:0`）→ ticker 每秒 bump → 【整页重建】（List+InputBar
//   全重算）→ 发送/流式期间输入卡重布局闪一下（[[arkui-page-local-periodic-update-rebuild]] 同类坑）。
//   下沉为 @ObservedV2/@Trace 单例后：只有【读 clock.nowTick 的叶子】（running 中的 ToolCard）按秒重渲，
//   ChatPage build 不再引用 nowTick → 不再整页重建。非 running 卡 elapsedText 提前 return 不读时钟 → 不刷。
//
// 仅 ChatPage ticker 驱动 bump；ToolCard.elapsedText 直接读 getChatClock().nowTick 建立细粒度刷新依赖。

@ObservedV2
export class ChatClock {
  /** 秒级单调计数（running 工具卡 elapsed 驱动值；值本身无意义，仅作刷新触发） */
  @Trace nowTick: number = 0;
}

// 模块级单例（nowTick 为运行时瞬时态，无需跨 Ability 持久化，故不用 AppStorageV2）
let _clock: ChatClock | null = null;
export function getChatClock(): ChatClock {
  if (_clock === null) {
    _clock = new ChatClock();
  }
  return _clock;
}
