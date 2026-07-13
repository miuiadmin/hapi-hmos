import { getHubClient } from '../api/HubClient';
import { FileSearchItem, SessionDirEntry } from '../models/Types';
import { GitStatusFiles, GitFileStatus, GitFileStatusType, buildGitStatusFiles } from '../chat/GitParsers';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { FileViewerRouteParams } from './FileViewerPage';

// 会话文件浏览页（NavDestination）—— 对照 hapi web /sessions/$sessionId/files（全量：git 变更 + 目录树 + 搜索）
//   3 Tab：① 改动（getGitStatus porcelain v2 + git-diff-numstat ×2 → buildGitStatusFiles）
//         ② 文件（listSessionDirectory 逐级浏览，面包屑回上）
//         ③ 搜索（searchSessionFiles by 文件名）
//   tap 任意文件 → pushPath FileViewerPage（readSessionFile 内容 / getGitDiffFile diff）
// 协议不变；行为对齐 web。颜色经统一主题。

// 路由参数
export class FilesRouteParams {
  sessionId: string = '';
}

// Tab 标识
type FilesTab = 'changes' | 'files' | 'search';

@ComponentV2
struct FilesPage {
  @Local sessionId: string = '';
  @Local activeTab: FilesTab = 'changes';

  // 改动 Tab
  @Local gitLoading: boolean = false;
  @Local gitError: string = '';
  @Local gitStatus: GitStatusFiles | null = null;

  // 文件 Tab（目录浏览）
  @Local dirPath: string = '';          // 当前路径（''=会话工作区根）
  @Local dirEntries: SessionDirEntry[] = [];
  @Local dirLoading: boolean = false;
  @Local dirError: string = '';

  // 搜索 Tab
  @Local searchQuery: string = '';
  @Local searchResults: FileSearchItem[] = [];
  @Local searchLoading: boolean = false;
  @Local searchError: string = '';
  @Local hasSearched: boolean = false;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }
  private navPathStack: NavPathStack | null = null;

  // sessionId 在 onReady 从路由 param 取；aboutToAppear 时未就绪，加载统一在 onReady 触发（早期 return 守卫防空载）。

  // —— 改动 Tab：git status + 双 numstat → buildGitStatusFiles ——
  private async loadGitStatus(): Promise<void> {
    if (this.sessionId === '') { return; }
    this.gitLoading = true;
    this.gitError = '';
    try {
      const status = await getHubClient().getGitStatus(this.sessionId);
      if (!status.success) {
        this.gitStatus = null;
        this.gitError = status.error !== '' ? status.error : (status.stderr !== '' ? status.stderr : '暂无 git 信息');
        return;
      }
      const [unstaged, staged] = await Promise.all([
        getHubClient().getGitDiffNumstat(this.sessionId, false),
        getHubClient().getGitDiffNumstat(this.sessionId, true)
      ]);
      this.gitStatus = buildGitStatusFiles(
        status.stdout,
        unstaged.success ? unstaged.stdout : '',
        staged.success ? staged.stdout : ''
      );
    } catch (e) {
      this.gitStatus = null;
      this.gitError = e instanceof Error ? e.message : '加载改动失败';
    } finally {
      this.gitLoading = false;
    }
  }

  // —— 文件 Tab：目录浏览 ——
  private async loadDirectory(path: string): Promise<void> {
    if (this.sessionId === '') { return; }
    this.dirPath = path;
    this.dirLoading = true;
    this.dirError = '';
    try {
      const list: SessionDirEntry[] = path === ''
        ? await getHubClient().listSessionDirectory(this.sessionId)
        : await getHubClient().listSessionDirectory(this.sessionId, path);
      // 目录在前，文件在后；同类按名排序
      list.sort((a: SessionDirEntry, b: SessionDirEntry) => {
        const ad: boolean = a.type === 'directory';
        const bd: boolean = b.type === 'directory';
        if (ad !== bd) { return ad ? -1 : 1; }
        return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0);
      });
      this.dirEntries = list;
    } catch (e) {
      this.dirEntries = [];
      this.dirError = e instanceof Error ? e.message : '浏览目录失败';
    } finally {
      this.dirLoading = false;
    }
  }

  // —— 搜索 Tab ——
  private async doSearch(): Promise<void> {
    if (this.sessionId === '' || this.searchQuery.trim() === '') { return; }
    this.searchLoading = true;
    this.searchError = '';
    this.hasSearched = true;
    try {
      this.searchResults = await getHubClient().searchSessionFiles(this.sessionId, this.searchQuery.trim());
    } catch (e) {
      this.searchResults = [];
      this.searchError = e instanceof Error ? e.message : '搜索失败';
    } finally {
      this.searchLoading = false;
    }
  }

  // 进文件查看页
  //   showDiff：从「改动」Tab 的已跟踪文件进入时 true（FileViewerPage 渲染 diff 段）；
  //             untracked 无 diff 意义，按 false 只看内容
  private openFile(fullPath: string, showDiff: boolean = false, staged: boolean = false): void {
    if (this.navPathStack === null) { return; }
    const p: FileViewerRouteParams = new FileViewerRouteParams();
    p.sessionId = this.sessionId;
    p.path = fullPath;
    p.showDiff = showDiff;
    p.staged = staged;
    this.navPathStack.pushPath({ name: 'FileViewerPage', param: p });
  }

  // 状态 → 显示字
  private statusChar(s: GitFileStatusType): string {
    if (s === 'modified') { return 'M'; }
    if (s === 'added') { return 'A'; }
    if (s === 'deleted') { return 'D'; }
    if (s === 'renamed') { return 'R'; }
    if (s === 'untracked') { return '?'; }
    return '!';   // conflicted
  }
  // 状态 → 色
  private statusColor(s: GitFileStatusType): string {
    if (s === 'modified') { return this.c.warning; }
    if (s === 'added') { return this.c.success; }
    if (s === 'deleted') { return this.c.error; }
    if (s === 'renamed') { return this.c.primary; }
    if (s === 'untracked') { return this.c.textTertiary; }
    return this.c.error;   // conflicted
  }

  // 路径 → 文件名
  private baseName(p: string): string {
    const idx: number = p.lastIndexOf('/');
    return idx >= 0 ? p.substring(idx + 1) : p;
  }
  // 路径 → 父目录链段（面包屑用）
  private pathSegments(): string[] {
    if (this.dirPath === '') { return []; }
    return this.dirPath.split('/').filter((s: string) => s.length > 0);
  }
  // 面包屑跳到第 i 段（-1 = 根）
  private goToSegment(i: number): void {
    if (i < 0) { this.loadDirectory(''); return; }
    const segs: string[] = this.pathSegments();
    this.loadDirectory(segs.slice(0, i + 1).join('/'));
  }

  @Builder
  private HeaderBar() {
    if (this.gitStatus !== null && this.gitStatus.branch !== '') {
      Row({ space: 6 }) {
        Text('⎇').fontSize(fs(13)).fontColor(this.c.primary)
        Text(this.gitStatus.branch)
          .fontSize(fs(13))
          .fontColor(this.c.primary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 4 })
    }
  }

  @Builder
  private Segmented() {
    Row({ space: 0 }) {
      this.TabButton('改动', 'changes', this.gitStatus !== null ? this.gitStatus.totalStaged + this.gitStatus.totalUnstaged : 0)
      this.TabButton('文件', 'files', 0)
      this.TabButton('搜索', 'search', 0)
    }
    .width('100%')
    .backgroundColor(this.c.surface)
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
  }

  @Builder
  private TabButton(label: string, tab: FilesTab, badge: number) {
    Text(badge > 0 ? `${label} ${badge}` : label)
      .fontSize(fs(14))
      .fontWeight(this.activeTab === tab ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.activeTab === tab ? this.c.primary : this.c.textSecondary)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .padding({ top: 8, bottom: 8 })
      .borderRadius(8)
      .backgroundColor(this.activeTab === tab ? this.c.surfaceSelected : this.c.surface)
      .onClick(() => { this.activeTab = tab; })
  }

  // —— 改动 Tab ——
  @Builder
  private ChangesView() {
    if (this.gitLoading) {
      this.LoadingRow('加载改动…')
    } else if (this.gitError !== '') {
      this.EmptyOrError(this.gitError)
    } else if (this.gitStatus === null || (this.gitStatus.totalStaged === 0 && this.gitStatus.totalUnstaged === 0)) {
      this.EmptyOrError('工作区干净，没有改动')
    } else {
      Column({ space: 0 }) {
        if (this.gitStatus.stagedFiles.length > 0) {
          this.SectionHeader('已暂存', this.gitStatus.stagedFiles.length)
          ForEach(this.gitStatus.stagedFiles, (f: GitFileStatus) => {
            this.GitFileRow(f)
          }, (f: GitFileStatus) => `${f.isStaged}-${f.fullPath}-${f.status}`)
        }
        if (this.gitStatus.unstagedFiles.length > 0) {
          this.SectionHeader('未暂存', this.gitStatus.unstagedFiles.length)
          ForEach(this.gitStatus.unstagedFiles, (f: GitFileStatus) => {
            this.GitFileRow(f)
          }, (f: GitFileStatus) => `${f.isStaged}-${f.fullPath}-${f.status}`)
        }
      }
      .width('100%')
      .padding({ bottom: 24 })
    }
  }

  @Builder
  private GitFileRow(f: GitFileStatus) {
    Row({ space: 10 }) {
      Text(this.statusChar(f.status))
        .fontSize(fs(13))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.statusColor(f.status))
        .width(18)
        .textAlign(TextAlign.Center)
      Column({ space: 2 }) {
        Text(f.fileName)
          .fontSize(fs(15))
          .fontColor(this.c.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (f.filePath !== '') {
          Text(f.filePath)
            .fontSize(fs(11))
            .fontColor(this.c.textTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // ±行数（untracked 无）
      if (f.status !== 'untracked' && (f.linesAdded > 0 || f.linesRemoved > 0)) {
        Row({ space: 4 }) {
          if (f.linesAdded > 0) {
            Text(`+${f.linesAdded}`).fontSize(fs(12)).fontColor(this.c.diffAdd)
          }
          if (f.linesRemoved > 0) {
            Text(`-${f.linesRemoved}`).fontSize(fs(12)).fontColor(this.c.diffDelete)
          }
        }
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .onClick(() => { this.openFile(f.fullPath, f.status !== 'untracked', f.isStaged); })
  }

  // —— 文件 Tab（目录浏览）——
  @Builder
  private FilesView() {
    Column({ space: 0 }) {
      // 面包屑
      Row() {
        Text('工作区')
          .fontSize(fs(13))
          .fontColor(this.dirPath === '' ? this.c.textPrimary : this.c.primary)
          .onClick(() => { this.goToSegment(-1); })
        ForEach(this.pathSegments(), (seg: string, i: number) => {
          Text(` / ${seg}`)
            .fontSize(fs(13))
            .fontColor(i === this.pathSegments().length - 1 ? this.c.textPrimary : this.c.primary)
            .maxLines(1)
            .onClick(() => { this.goToSegment(i); })
        }, (seg: string, i: number) => `${i}-${seg}`)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)

      if (this.dirLoading) {
        this.LoadingRow('加载目录…')
      } else if (this.dirError !== '') {
        this.EmptyOrError(this.dirError)
      } else if (this.dirEntries.length === 0) {
        this.EmptyOrError('空目录')
      } else {
        ForEach(this.dirEntries, (e: SessionDirEntry) => {
          this.DirRow(e)
        }, (e: SessionDirEntry) => `${e.name}-${e.type}`)
      }
    }
    .width('100%')
  }

  @Builder
  private DirRow(e: SessionDirEntry) {
    Row({ space: 10 }) {
      Text(e.type === 'directory' ? '📁' : this.fileEmoji(e.name))
        .fontSize(fs(16))
        .width(20)
      Text(e.name)
        .fontSize(fs(15))
        .fontColor(this.c.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (e.type === 'directory') {
        Text('›').fontSize(fs(16)).fontColor(this.c.textTertiary)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 11, bottom: 11 })
    .onClick(() => {
      if (e.type === 'directory') {
        this.loadDirectory(this.dirPath === '' ? e.name : `${this.dirPath}/${e.name}`);
      } else {
        this.openFile(this.dirPath === '' ? e.name : `${this.dirPath}/${e.name}`);
      }
    })
  }

  // —— 搜索 Tab ——
  @Builder
  private SearchView() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.searchQuery, placeholder: '搜索文件名…' })
          .fontSize(fs(15))
          .layoutWeight(1)
          .backgroundColor(this.c.surface)
          .borderRadius(8)
          .onChange((v: string) => { this.searchQuery = v; })
          .onSubmit(() => { this.doSearch(); })
        Button('搜索')
          .fontSize(fs(14))
          .backgroundColor(this.c.primary)
          .fontColor(this.c.bubbleUserText)
          .height(40)
          .onClick(() => { this.doSearch(); })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      if (this.searchLoading) {
        this.LoadingRow('搜索中…')
      } else if (this.searchError !== '') {
        this.EmptyOrError(this.searchError)
      } else if (!this.hasSearched) {
        this.EmptyOrError('输入文件名搜索会话工作区')
      } else if (this.searchResults.length === 0) {
        this.EmptyOrError('没有匹配的文件')
      } else {
        ForEach(this.searchResults, (f: FileSearchItem) => {
          this.SearchRow(f)
        }, (f: FileSearchItem) => f.fullPath)
      }
    }
    .width('100%')
  }

  @Builder
  private SearchRow(f: FileSearchItem) {
    Row({ space: 10 }) {
      Text(f.fileType === 'folder' ? '📁' : this.fileEmoji(f.fileName))
        .fontSize(fs(16))
        .width(20)
      Column({ space: 2 }) {
        Text(f.fileName)
          .fontSize(fs(15))
          .fontColor(this.c.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (f.filePath !== '') {
          Text(f.filePath)
            .fontSize(fs(11))
            .fontColor(this.c.textTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 11, bottom: 11 })
    .onClick(() => {
      if (f.fileType !== 'folder') { this.openFile(f.fullPath); }
    })
  }

  // —— 公共 @Builder ——
  @Builder
  private SectionHeader(title: string, count: number) {
    Text(`${title}（${count}）`)
      .fontSize(fs(12))
      .fontColor(this.c.textTertiary)
      .width('100%')
      .padding({ left: 16, top: 14, bottom: 4 })
      .backgroundColor(this.c.bg)
  }

  @Builder
  private LoadingRow(msg: string) {
    Column({ space: 8 }) {
      LoadingProgress().width(28).height(28).color(this.c.primary)
      Text(msg).fontSize(fs(13)).fontColor(this.c.textTertiary)
    }
    .width('100%')
    .padding({ top: 48 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private EmptyOrError(msg: string) {
    Text(msg)
      .fontSize(fs(14))
      .fontColor(this.c.textTertiary)
      .width('100%')
      .textAlign(TextAlign.Center)
      .padding({ top: 48, bottom: 48, left: 24, right: 24 })
  }

  // 文件名 → emoji（简单后缀判断，与项目 📁/📄 风格一致）
  private fileEmoji(name: string): string {
    const lower: string = name.toLowerCase();
    const dot: number = lower.lastIndexOf('.');
    if (dot < 0) { return '📄'; }
    const ext: string = lower.substring(dot + 1);
    if (ext === 'png' || ext === 'jpg' || ext === 'jpeg' || ext === 'gif' || ext === 'webp' || ext === 'svg' || ext === 'bmp') {
      return '🖼️';
    }
    if (ext === 'ts' || ext === 'ets' || ext === 'js' || ext === 'json' || ext === 'md' || ext === 'py' || ext === 'go' || ext === 'rs' || ext === 'java' || ext === 'sh') {
      return '📜';
    }
    return '📄';
  }

  @Builder
  private RefreshMenu() {
    Text('↻').fontSize(fs(20)).fontColor(this.c.textPrimary)
      .onClick(() => {
        if (this.activeTab === 'changes') { this.loadGitStatus(); }
        else if (this.activeTab === 'files') { this.loadDirectory(this.dirPath); }
        else { this.doSearch(); }
      })
  }

  build() {
    NavDestination() {
      Column() {
        this.HeaderBar()
        this.Segmented()
        Scroll() {
          Column() {
            if (this.activeTab === 'changes') {
              this.ChangesView()
            } else if (this.activeTab === 'files') {
              this.FilesView()
            } else {
              this.SearchView()
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .backgroundColor(this.c.bg)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.c.bg)
    }
    .title('文件')
    .menus(this.RefreshMenu)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack;
      const param = context.pathInfo.param as FilesRouteParams;
      if (param !== null && param !== undefined) {
        this.sessionId = param.sessionId;
        // 拿到 sessionId 后真正加载（aboutToAppear 时 sessionId 可能尚未就绪）
        this.loadGitStatus();
        this.loadDirectory('');
      }
    })
  }
}

// 系统路由表 buildFunction（router_map.json 引用）
@Builder
export function FilesPageBuilder(name: string, param: Object) {
  FilesPage()
}
