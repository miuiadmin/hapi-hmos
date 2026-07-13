// 对照 web ImagePreview.tsx：MIN_SCALE=0.25 / MAX_SCALE=8。
const MIN_SCALE: number = 0.25;
const MAX_SCALE: number = 8;

// ImagePreviewSheet —— 统一「markdown 图片 + 生成图片」两处的全屏预览（对照 web ImagePreview.tsx）。
// 受控组件：父持有 open/src 状态，本组件自带 bindSheet（统一 LARGE + 纯黑 + BlurStyle.NONE）。
//   内含双指缩放：PinchGesture（MIN 0.25 / MAX 8，对照上游）→ Image().scale({x,y})；
//   放大后单指拖动：PanGesture → .translate({x,y})（scale ≤ 1 时禁用拖动并强制居中）；
//   点按关闭（onClick 与手势并存：纯净单击触发 onClick，拖动/双指不触发）。
//   宿主为 0 尺寸 Column，仅承载 bindSheet（sheet 为模态浮层，不依赖宿主尺寸）。
//   每次关闭在 onDisappear 重置变换，下次打开回到 1x/居中。
@ComponentV2
export struct ImagePreviewSheet {
  @Param src: string = '';
  @Param open: boolean = false;
  @Event onClose: () => void = (): void => {};

  @Local private scale: number = 1;
  @Local private offsetX: number = 0;
  @Local private offsetY: number = 0;
  // 手势起点快照（非响应式，仅回调内读写）
  private pinchStartScale: number = 1;
  private panStartX: number = 0;
  private panStartY: number = 0;

  private resetTransform(): void {
    this.scale = 1;
    this.offsetX = 0;
    this.offsetY = 0;
    this.pinchStartScale = 1;
    this.panStartX = 0;
    this.panStartY = 0;
  }

  @Builder
  private SheetBody() {
    Stack() {
      Image(this.src)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .draggable(false)
        .scale({ x: this.scale, y: this.scale, z: 1 })
        .translate({ x: this.offsetX, y: this.offsetY })
        .onClick((): void => { this.onClose(); })
        .gesture(
          GestureGroup(GestureMode.Parallel,
            // 双指捏合缩放：event.scale 相对手势起点；onActionStart 快照当前 scale 作乘子。
            PinchGesture({ fingers: 2 })
              .onActionStart((e: GestureEvent): void => { this.pinchStartScale = this.scale; })
              .onActionUpdate((e: GestureEvent): void => {
                const next: number = this.pinchStartScale * e.scale;
                if (next < MIN_SCALE) {
                  this.scale = MIN_SCALE;
                } else if (next > MAX_SCALE) {
                  this.scale = MAX_SCALE;
                } else {
                  this.scale = next;
                }
                // 回到 ≤ 1x：强制居中（缩小到整图内无平移意义）
                if (this.scale <= 1) {
                  this.offsetX = 0;
                  this.offsetY = 0;
                }
              }),
            // 单指拖动：仅放大后生效（scale > 1）；event.offsetX/Y 相对手势起点累计。
            PanGesture()
              .onActionStart((e: GestureEvent): void => { this.panStartX = this.offsetX; this.panStartY = this.offsetY; })
              .onActionUpdate((e: GestureEvent): void => {
                if (this.scale > 1) {
                  this.offsetX = this.panStartX + e.offsetX;
                  this.offsetY = this.panStartY + e.offsetY;
                }
              })
          )
        )
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }

  build() {
    Column() {}
      .width(0)
      .height(0)
      .bindSheet(this.open, this.SheetBody(), {
        height: SheetSize.LARGE,
        detents: [SheetSize.LARGE],
        dragBar: true,
        showClose: true,
        // 纯黑背板：backgroundColor 须配 backgroundBlurStyle.NONE（默认模糊会使纯色发灰）
        backgroundColor: Color.Black,
        backgroundBlurStyle: BlurStyle.NONE,
        onDisappear: (): void => {
          this.resetTransform();   // 关闭后重置，下次打开回到 1x/居中
          this.onClose();          // 兜底：dragBar/showClose/下滑关闭时同步父状态
        }
      })
  }
}
