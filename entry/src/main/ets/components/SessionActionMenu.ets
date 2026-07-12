import { getHubClient } from '../api/HubClient';
import { paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';

// 会话动作菜单（重命名 / 归档 / 删除）——列表长按（Index）与对话页标题栏 ⋯（ChatPage）复用，去重。
// 组件自持两 sheet（动作面板 + 重命名面板）+ 全部生命周期逻辑（确认弹窗 / API 调用 / 防重入）。
// 父只需：传目标快照（sessionId/title/active）+ open 信号（@Param 布尔）+ 成功回调（@Event）。
//   - open=true 开动作面板；面板被滑掉/点蒙层/选了某项 → onDisappear → onClose() 回写父（父置 open=false）。
//   - 重命名成功 → onRenamed(name)；归档成功 → onArchived()；删除成功 → onDeleted()。父决定后续：
//     列表 loadSessions / 对话页 设本地态 / pop 导航。
//   - 注：@Event 改父值立刻生效，同步回 @Param 在「渲染之前」完成（@Event 文档），故 onClose 后动作面板与
//     后续弹窗/重命名面板同帧切换，无可见闪烁。
// 上游行为逐字对照 hub 源码 + web SessionActionMenu/RenameSessionDialog/ConfirmDialog（无臆测）。
// 菜单按 active 二选一：活跃→归档，非活跃→删除，永不并存（Session 无 archived 字段：
//   归档=杀活跃 CLI + active=false；删除=硬删除不可恢复）。

@ComponentV2
export struct SessionActionMenu {
  // 目标会话快照（父持有；@Param 单向，随父态刷新）
  @Param sessionId: string = '';
  @Param title: string = '';
  @Param active: boolean = true;
  // 动作面板显隐（父控制开；onClose 回写关）
  @Param open: boolean = false;

  // 成功回调（父决定后续动作）
  @Event onRenamed: (newName: string) => void = (newName: string) => {};
  @Event onArchived: () => void = () => {};
  @Event onDeleted: () => void = () => {};
  // 动作面板关闭回写（滑掉/蒙层/选了重命名/归档/删除）
  @Event onClose: () => void = () => {};

  // 重命名面板（组件内部态；从动作面板内 transitions 进出，不暴露父）
  @Local showRename: boolean = false;
  @Local renameText: string = '';
  @Local isActing: boolean = false;                 // 请求进行中（防重入 + 保存按钮置灰）
  private renameInputController: TextInputController = new TextInputController();

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg });
  }

  // 动作面板被滑掉/点蒙层 → 回写父关闭
  private onActionDisappear(): void {
    this.onClose();
  }

  // 第二项文案：active→归档；非活跃→删除（永不并存，对照上游 SessionActionMenu）
  private destructiveLabel(): string {
    return this.active ? '归档' : '删除';
  }

  private onDestructiveTap(): void {
    if (this.active) {
      this.confirmArchive();
    } else {
      this.confirmDelete();
    }
  }

  // 重命名：关动作面板，预填当前标题，开重命名面板
  private startRename(): void {
    this.onClose();
    this.renameText = this.title;
    this.showRename = true;
  }

  private closeRename(): void {
    this.showRename = false;
    this.renameText = '';
  }

  // 确认重命名：空或未改不请求；成功 onRenamed(name) + 关面板；失败保留面板（toast 提示）
  private async confirmRename(): Promise<void> {
    if (this.isActing || this.sessionId === '') {
      return;
    }
    const name = this.renameText.trim();
    if (name.length === 0 || name === this.title) {
      this.closeRename();
      return;
    }
    this.isActing = true;
    try {
      const ok = await getHubClient().renameSession(this.sessionId, name);
      if (ok) {
        this.onRenamed(name);
        this.toast('已重命名');
        this.closeRename();
      } else {
        this.toast('重命名失败，请重试');
      }
    } catch (e) {
      this.toast('重命名失败，请重试');
    } finally {
      this.isActing = false;
    }
  }

  // 归档二次确认（危险操作，confirm 红字）
  private confirmArchive(): void {
    this.onClose();
    this.getUIContext().showAlertDialog({
      title: '归档会话',
      message: `确定要归档「${this.title}」吗？这将断开活跃会话。`,
      autoCancel: true,
      confirm: {
        value: '归档',
        fontColor: this.c.error,
        action: () => { this.doArchive(); }
      }
    });
  }

  // 删除二次确认（硬删除不可恢复，confirm 红字）
  private confirmDelete(): void {
    this.onClose();
    this.getUIContext().showAlertDialog({
      title: '删除会话',
      message: `确定要删除「${this.title}」吗？此操作不可恢复。`,
      autoCancel: true,
      confirm: {
        value: '删除',
        fontColor: this.c.error,
        action: () => { this.doDelete(); }
      }
    });
  }

  // 执行归档：成功 onArchived()（父决定后续）；失败 toast
  private async doArchive(): Promise<void> {
    if (this.isActing || this.sessionId === '') {
      return;
    }
    this.isActing = true;
    try {
      const ok = await getHubClient().archiveSession(this.sessionId);
      if (ok) {
        this.onArchived();
        this.toast('已归档');
      } else {
        this.toast('归档失败，请重试');
      }
    } catch (e) {
      this.toast('归档失败，请重试');
    } finally {
      this.isActing = false;
    }
  }

  // 执行删除：成功 onDeleted()（父决定后续：列表 loadSessions / 对话页 pop）；失败 toast
  private async doDelete(): Promise<void> {
    if (this.isActing || this.sessionId === '') {
      return;
    }
    this.isActing = true;
    try {
      const ok = await getHubClient().deleteSession(this.sessionId);
      if (ok) {
        this.onDeleted();
        this.toast('已删除');
      } else {
        this.toast('删除失败，请重试');
      }
    } catch (e) {
      this.toast('删除失败，请重试');
    } finally {
      this.isActing = false;
    }
  }

  // 动作面板（重命名 / 归档或删除，对照上游 SessionActionMenu）
  @Builder
  private ActionMenuSheet() {
    Column() {
      Text(this.title)
        .fontSize(13)
        .fontColor(this.c.textTertiary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 8 })

      Row() {
        Text('重命名').fontSize(16).fontColor(this.c.textPrimary).layoutWeight(1)
      }
      .width('100%')
      .height(52)
      .padding({ left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => { this.startRename(); })

      Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 20, right: 20 })

      Row() {
        Text(this.destructiveLabel()).fontSize(16).fontColor(this.c.error).layoutWeight(1)
      }
      .width('100%')
      .height(52)
      .padding({ left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => { this.onDestructiveTap(); })
    }
    .width('100%')
    .backgroundColor(this.c.bg)
    .padding({ bottom: 20 })
  }

  // 重命名面板：TextInput 预填 + 保存/取消；空或未改不请求，回车提交，失败保留面板（对照上游 RenameSessionDialog）
  @Builder
  private RenameSheet() {
    Column() {
      TextInput({ text: this.renameText, placeholder: '会话名称', controller: this.renameInputController })
        .fontSize(16)
        .fontColor(this.c.textPrimary)
        .placeholderColor(this.c.textTertiary)
        .backgroundColor(this.c.surface)
        .borderRadius(12)
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .maxLength(255)
        .defaultFocus(true)
        .onChange((v: string) => { this.renameText = v; })
        .onSubmit(() => { this.confirmRename(); })

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.c.surface)
          .fontColor(this.c.textPrimary)
          .borderRadius(12)
          .onClick(() => { this.closeRename(); })
        Button(this.isActing ? '保存中…' : '保存')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.c.primary)
          .fontColor(this.c.bubbleUserText)
          .borderRadius(12)
          .enabled(!this.isActing && this.renameText.trim().length > 0)
          .onClick(() => { this.confirmRename(); })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 20 })
    .backgroundColor(this.c.bg)
  }

  build() {
    // 零尺寸常驻容器：仅承载两 sheet。动作面板挂外层 Column / 重命名面板挂内层 Column，
    // 双节点规避同节点 bindSheet 叠加疑问（延续 Index 两节点模式）。bindSheet 为模态覆盖，锚点尺寸无关。
    Column() {
      Column() {}
        .bindSheet(this.showRename, this.RenameSheet(), {
          detents: [SheetSize.FIT_CONTENT],
          dragBar: true,
          showClose: true,
          title: { title: '重命名会话' },
          onDisappear: (): void => { this.closeRename(); }
        })
    }
    .width(0)
    .height(0)
    .bindSheet(this.open, this.ActionMenuSheet(), {
      detents: [SheetSize.FIT_CONTENT],
      dragBar: true,
      showClose: false,
      onDisappear: (): void => { this.onActionDisappear(); }
    })
  }
}
