// SyncedLoader —— paseo 风格 6 点同步加载动画（@ComponentV2 叶子组件）。
//
// 移植自 参考源码/paseo/packages/app/src/components/synced-loader*.ts(x)：2×3 点阵，950ms 一周期，
//   6 个离散步进（每步 ~158ms），每步按 OPACITY_STATES 矩阵给 6 点分配不透明度 → 对角线波浪感。
//   不插值（忠实 paseo：步进式，非连续渐变）；步进由 wall-clock 派生（getSyncedLoaderStep(Date.now())）→
//   多实例天然同相（同一时刻读同一 now → 同一 step），无需全局共享时钟。
// 独立叶子组件 + @Local step 自持：setInterval 仅重建本组件（6 点），不波及父列表
//   （避页面级 @Local 周期翻转 → 整页重建坑，见记忆 arkui-page-local-periodic-update-rebuild；同 StatusDot 范式）。
//   running↔idle 切换由父级条件渲染（running 才挂载本组件）→ 自然启停；aboutToDisappear 清 timer 防泄漏。
// ⚠️ @Param 命名 boxSize（非 size）：size 与 CustomComponent 通用属性 .size() 撞名编译报错。

const SYNCED_LOADER_DURATION_MS: number = 950;
const SYNCED_LOADER_DOT_COUNT: number = 6;

// 6 步 × 6 点不透明度矩阵（逐字移植 synced-loader-state.ts）。行=步进(0..5)，列=点(0..5)。
const OPACITY_STATES: number[][] = [
  [1, 0, 0.78, 0, 0.56, 0.34],
  [0.78, 1, 0.56, 0, 0.34, 0],
  [0.56, 0.78, 0.34, 1, 0, 0],
  [0.34, 0.56, 0, 0.78, 0, 1],
  [0, 0.34, 0, 0.56, 1, 0.78],
  [0, 0, 1, 0.34, 0.78, 0.56],
];

// 由 wall-clock 求当前步进（0..5）：elapsed = now % 950；step = floor(elapsed * 6 / 950)。
export function getSyncedLoaderStep(nowMs: number): number {
  const elapsedMs: number = nowMs % SYNCED_LOADER_DURATION_MS;
  return Math.floor((elapsedMs * SYNCED_LOADER_DOT_COUNT) / SYNCED_LOADER_DURATION_MS);
}

// 取某步进下某点的不透明度（越界兜底 0）。
export function getSyncedLoaderDotOpacity(step: number, dot: number): number {
  if (step < 0 || step >= OPACITY_STATES.length) {
    return 0;
  }
  const row: number[] = OPACITY_STATES[step];
  if (dot < 0 || dot >= row.length) {
    return 0;
  }
  return row[dot];
}

@ComponentV2
export struct SyncedLoader {
  @Param color: string = '';
  @Param boxSize: number = 14;   // 点阵尺度（vp）：点间距 gap=round(boxSize*0.12)，点径=floor((boxSize-gap*2)/3)
  @Local private step: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    // 首帧即取当前步进（避挂载首帧全点满亮一闪）；80ms tick 足以捕获每个 ~158ms 步进窗（含抖动裕量）。
    this.step = getSyncedLoaderStep(Date.now());
    this.timer = setInterval(() => {
      const next: number = getSyncedLoaderStep(Date.now());
      if (next !== this.step) {
        this.step = next;   // 仅步进翻转时写 @Local → 约 6 次/秒真重建，余为 no-op
      }
    }, 80);
  }

  aboutToDisappear(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  // 点间距（vp）：boxSize*0.12，下限 1（移植 synced-loader.tsx:100）。
  private gap(): number {
    return Math.max(1, Math.round(this.boxSize * 0.12));
  }

  // 单点直径（vp）：(boxSize - gap*2) / 3，下限 2（3 行 + 2 间隙约填满 boxSize 高，移植 synced-loader.tsx:101）。
  private dotPx(): number {
    return Math.max(2, Math.floor((this.boxSize - this.gap() * 2) / 3));
  }

  @Builder
  Dot(i: number) {
    Column()
      .width(this.dotPx())
      .height(this.dotPx())
      .borderRadius(this.dotPx() / 2)
      .backgroundColor(this.color)
      .opacity(getSyncedLoaderDotOpacity(this.step, i))
  }

  build() {
    // 3 行 × 2 列点阵（行间/列间各 gap）；build 直接以单根 Column 起，无前置语句避「多根节点」误判。
    Column({ space: this.gap() }) {
      Row({ space: this.gap() }) {
        this.Dot(0);
        this.Dot(1);
      }
      Row({ space: this.gap() }) {
        this.Dot(2);
        this.Dot(3);
      }
      Row({ space: this.gap() }) {
        this.Dot(4);
        this.Dot(5);
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
