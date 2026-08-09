// 存储用量甜甜圈饼图组件（net-new，ArkUI 无现成饼图——用 Path.commands 画扇形弧）。
//   对照上游 web/src/components/settings/StorageUsagePie.tsx：database/wal/shm 三段扇形 + 中心读数 +
//   可点图例（点选高亮某段，中心切换显示该段；默认中心显示总量）。空态（全 0）显 empty + 总量 + 路径。
//
// 纯层 chat/StoragePie.ets 提供 buildStorageSlices/describeDonutArc/formatStorageBytes/formatStoragePercent。
// 颜色：database=primary，wal=primary@0.55（同色弱化，呼应「同一 DB 的不同部分」），shm=textTertiary。
import { paletteOf, PaletteColors, getThemeState } from '../../theme/ThemeService';
import { t } from '../../i18n/I18nService';
import {
  StorageSliceKey, StorageUsageBytes, StorageSlice,
  buildStorageSlices, describeDonutArc, formatStorageBytes, formatStoragePercent
} from '../../chat/StoragePie';

const SIZE: number = 180;
const CX: number = SIZE / 2;
const CY: number = SIZE / 2;
const INNER_R: number = 50;
const OUTER_R: number = 78;
const ACTIVE_OUTER_R: number = 86;

@ComponentV2
export struct StorageUsagePie {
  @Param databaseBytes: number = 0;
  @Param walBytes: number = 0;
  @Param shmBytes: number = 0;
  @Param totalBytes: number = 0;
  @Param path: string = '';
  @Local activeKey: StorageSliceKey | null = null;   // 点选高亮段；null=中心显总量

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  private get usage(): StorageUsageBytes {
    const u: StorageUsageBytes = {
      databaseBytes: this.databaseBytes,
      walBytes: this.walBytes,
      shmBytes: this.shmBytes
    };
    return u;
  }

  private get slices(): StorageSlice[] { return buildStorageSlices(this.usage); }

  private labelForKey(key: StorageSliceKey): string {
    if (key === 'database') { return t('settings.storage.database'); }
    if (key === 'wal') { return t('settings.storage.wal'); }
    return t('settings.storage.shm');
  }

  private fillColor(key: StorageSliceKey): string {
    return key === 'shm' ? this.c.textTertiary : this.c.primary;
  }
  private fillOpacity(key: StorageSliceKey, isActive: boolean): number {
    const base: number = key === 'database' ? 1.0 : (key === 'wal' ? 0.55 : 1.0);
    return isActive ? base : base * 0.78;
  }

  build() {
    Column() {
      // 标题
      Text(t('settings.storage.chartTitle'))
        .fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.c.textPrimary)
        .width('100%').margin({ bottom: 12 })

      if (this.slices.length === 0) {
        // 空态：无数据
        Text(t('settings.storage.chartEmpty'))
          .fontSize(14).fontColor(this.c.textTertiary)
          .width('100%').padding({ top: 24, bottom: 24 }).textAlign(TextAlign.Center)
      } else {
        // 饼图 + 图例
        Row({ space: 16 }) {
          // 甜甜圈
          Stack() {
            ForEach(this.slices, (s: StorageSlice) => {
              Path({ width: SIZE, height: SIZE })
                .commands(describeDonutArc(CX, CY, INNER_R,
                  this.activeKey === s.key ? ACTIVE_OUTER_R : OUTER_R, s.startAngle, s.endAngle))
                .fill(this.fillColor(s.key))
                .fillOpacity(this.fillOpacity(s.key, this.activeKey === null || this.activeKey === s.key))
                .onClick(() => { this.activeKey = this.activeKey === s.key ? null : s.key; })
            }, (s: StorageSlice) => `${s.key}-${s.startAngle}`)
            // 中心读数
            Column() {
              if (this.activeKey !== null) {
                Text(this.centerLabel())
                  .fontSize(11).fontColor(this.c.textTertiary).maxLines(1)
                Text(this.centerBytes())
                  .fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.c.textPrimary).margin({ top: 2 })
                Text(this.centerPercent())
                  .fontSize(11).fontColor(this.c.textTertiary).margin({ top: 1 })
              } else {
                Text(t('settings.storage.total'))
                  .fontSize(11).fontColor(this.c.textTertiary).maxLines(1)
                Text(formatStorageBytes(this.totalBytes))
                  .fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.c.textPrimary).margin({ top: 2 })
              }
            }
            .width(SIZE).height(SIZE)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .hitTestBehavior(HitTestMode.Transparent)
          }
          .width(SIZE).height(SIZE)

          // 图例
          Column({ space: 2 }) {
            ForEach(this.slices, (s: StorageSlice) => {
              Row() {
                Circle({ width: 8, height: 8 })
                  .fill(this.fillColor(s.key))
                  .fillOpacity(this.fillOpacity(s.key, true))
                  .margin({ right: 8 })
                Text(this.labelForKey(s.key))
                  .fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.c.textPrimary)
                  .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(formatStorageBytes(s.bytes))
                  .fontSize(13).fontColor(this.c.textSecondary).margin({ right: 8 })
                Text(formatStoragePercent(s.percent))
                  .fontSize(13).fontColor(this.c.textSecondary).width(44).textAlign(TextAlign.End)
              }
              .width('100%')
              .padding({ left: 8, right: 8, top: 8, bottom: 8 })
              .borderRadius(10)
              .backgroundColor(this.activeKey === s.key ? this.c.surfaceSelected : Color.Transparent)
              .onClick(() => { this.activeKey = this.activeKey === s.key ? null : s.key; })
            }, (s: StorageSlice) => s.key)
          }
          .layoutWeight(1)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }

      // 总量页脚
      Row() {
        Text(t('settings.storage.total')).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.c.textPrimary)
        Text(formatStorageBytes(this.totalBytes)).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.c.textPrimary)
      }
      .width('100%').justifyContent(FlexAlign.SpaceBetween)
      .padding({ left: 8, right: 8, top: 10, bottom: 6 })
      .margin({ top: 8 })
      .border({ width: { top: 1 }, color: this.c.border })

      // 路径页脚
      Column() {
        Text(t('settings.storage.path')).fontSize(11).fontColor(this.c.textTertiary)
        Text(this.path)
          .fontSize(11).fontColor(this.c.textTertiary)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%').margin({ top: 2 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 8 })
      .border({ width: { top: 1 }, color: this.c.border })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(this.c.bg)
    .borderRadius($r('app.float.setting_card_radius'))
    .border({ width: 1, color: this.c.border })
  }

  private centerLabel(): string {
    if (this.activeKey !== null) { return this.labelForKey(this.activeKey); }
    return t('settings.storage.total');
  }
  private centerBytes(): string {
    if (this.activeKey !== null) {
      for (let i = 0; i < this.slices.length; i++) {
        if (this.slices[i].key === this.activeKey) { return formatStorageBytes(this.slices[i].bytes); }
      }
    }
    return formatStorageBytes(this.totalBytes);
  }
  private centerPercent(): string {
    if (this.activeKey !== null) {
      for (let i = 0; i < this.slices.length; i++) {
        if (this.slices[i].key === this.activeKey) { return formatStoragePercent(this.slices[i].percent); }
      }
    }
    return '';
  }
}
