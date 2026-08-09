// AudioPlayerBar —— 生成音频的内联播放条（AVPlayer 从零建，项目内 0 先例）。
//   对照上游 #1405：generatedInlineMedia audio 分支。AVPlayer 状态机驱动。
//   ⚠️ Hub 在线机器=[] → 无法实测真音频播放，结构 + 编译先过，待真机验（url scheme/time 单位可能需调）。
//
//   范式照搬 berry3 AvPlayer.ets（已验证的 AVPlayer 用法）：
//     import { media } from '@kit.MediaKit'；createAVPlayer → set url → 'initialized' → prepare()
//     → 'prepared' → play()/pause()。进度用 setInterval 轮询 currentTime/duration（非 on('timeUpdate')）。
//   状态机：idle → initialized → prepared → playing ⇄ paused → completed → stopped → released。
import { media } from '@kit.MediaKit';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';

@ComponentV2
export struct AudioPlayerBar {
  @Param src: string = '';                 // 沙箱裸路径（来自 GeneratedImageCache）
  @Local isReady: boolean = false;
  @Local isPlaying: boolean = false;
  @Local durationMs: number = 0;
  @Local currentMs: number = 0;
  @Local loadError: string = '';
  private player: media.AVPlayer | null = null;
  private progressTimer: number | null = null;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  aboutToAppear(): void {
    this.setup();
  }

  aboutToDisappear(): void {
    this.stopProgress();
    this.release();
  }

  private async setup(): Promise<void> {
    if (this.src === '') { return; }
    try {
      const p: media.AVPlayer = await media.createAVPlayer();
      this.player = p;
      p.on('error', (err) => {
        this.loadError = t('genImage.audioError');
        this.stopProgress();
      });
      // 状态机驱动（对照 berry3 AvPlayer.ets:426 setAVPlayerCallback）
      p.on('stateChange', (state: string, reason: media.StateChangeReason) => {
        if (state === 'initialized') {
          p.prepare();
        } else if (state === 'prepared') {
          this.isReady = true;
        } else if (state === 'playing') {
          this.isPlaying = true;
          this.startProgress();
        } else if (state === 'paused') {
          this.isPlaying = false;
          this.stopProgress();
        } else if (state === 'completed') {
          this.isPlaying = false;
          this.stopProgress();
          this.currentMs = 0;
        } else if (state === 'error') {
          this.loadError = t('genImage.audioError');
          this.stopProgress();
        }
      });
      // 本地沙箱文件：file:// + 裸路径；set url 触发 → 'initialized'。
      p.url = `file://${this.src}`;
    } catch (e) {
      this.loadError = t('genImage.audioError');
    }
  }

  private toggle(): void {
    const p: media.AVPlayer | null = this.player;
    if (p === null) { return; }
    if (this.isPlaying) {
      p.pause();
    } else {
      p.play();
    }
  }

  private onSeek(value: number): void {
    const p: media.AVPlayer | null = this.player;
    if (p !== null) { p.seek(value); }
  }

  // 进度轮询（对照 berry3 startProgressTask：每 500ms 读 currentTime/duration）
  private startProgress(): void {
    this.stopProgress();
    this.progressTimer = setInterval((): void => {
      const p: media.AVPlayer | null = this.player;
      if (p === null) { return; }
      this.currentMs = p.currentTime ?? 0;
      if (this.durationMs === 0 && p.duration > 0) {
        this.durationMs = p.duration;
      }
    }, 500);
  }

  private stopProgress(): void {
    if (this.progressTimer !== null) {
      clearInterval(this.progressTimer);
      this.progressTimer = null;
    }
  }

  private release(): void {
    const p: media.AVPlayer | null = this.player;
    if (p !== null) {
      try { p.release(); } catch (e) { /* fire-and-forget */ }
      this.player = null;
    }
  }

  // ms → m:ss
  private fmt(ms: number): string {
    if (ms <= 0 || !Number.isFinite(ms)) { return '0:00'; }
    const totalSec: number = Math.floor(ms / 1000);
    const m: number = Math.floor(totalSec / 60);
    const s: number = totalSec % 60;
    return `${m}:${s < 10 ? '0' : ''}${s}`;
  }

  build() {
    Column() {
      if (this.loadError !== '') {
        Text(this.loadError)
          .fontSize(fs(13)).fontColor(this.c.textTertiary)
          .padding({ top: 16, bottom: 16 }).width('100%').textAlign(TextAlign.Center)
      } else {
        Row() {
          // 播放/暂停
          SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
            .fontSize(22)
            .fontColor([this.c.bubbleUserText])
            .onClick(() => { this.toggle(); })
          // 进度
          Slider({
            value: this.currentMs,
            min: 0,
            max: this.durationMs > 0 ? this.durationMs : 1,
            step: 1,
            style: SliderStyle.OutSet
          })
            .layoutWeight(1)
            .blockColor(this.c.primary)
            .selectedColor(this.c.primary)
            .trackColor(this.c.border)
            .enabled(this.isReady)
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.onSeek(Math.floor(value));
              }
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row() {
          Text(this.fmt(this.currentMs))
            .fontSize(fs(11)).fontColor(this.c.textTertiary)
          Text(this.durationMs > 0 ? this.fmt(this.durationMs) : '--:--')
            .fontSize(fs(11)).fontColor(this.c.textTertiary)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ top: 4 })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 14, bottom: 14 })
    .borderRadius(10)
    .backgroundColor(this.c.surfaceSelected)
  }
}
