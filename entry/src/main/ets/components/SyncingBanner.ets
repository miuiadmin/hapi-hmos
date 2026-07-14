import { getSyncState } from '../services/SyncStateService';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';

// 同步中横幅：前台返回超过 30s 时由 EntryAbility.onForeground 触发 beginSync（对照上游 SyncingBanner）。
// 直接读 getSyncState().syncing（@Trace 应用级单例，变更即触发本组件重渲染，无需自注册监听者）。
// SyncStateService.arm 10s 自动清除；页面 reload 完成后也会 endSync。常态（syncing=false）用 Visibility.None 收起。
@ComponentV2
export struct SyncingBanner {
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  build() {
    Row({ space: 8 }) {
      LoadingProgress().width(14).height(14).color(this.c.textSecondary)
      Text(t('sync.syncing'))
        .fontSize(fs(12))
        .fontColor(this.c.textSecondary)
    }
    .width('100%')
    .height(32)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.c.surface)
    .visibility(getSyncState().syncing ? Visibility.Visible : Visibility.None)
  }
}
