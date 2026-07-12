import { getHubClient } from '../api/HubClient';
import { Machine, DirEntry, AGENT_FLAVORS, agentDisplayName, modelOptionsForAgent, modelDisplayName, EFFORT_OPTIONS, effortDisplayName, SESSION_TYPES, sessionTypeDisplayName } from '../models/Types';
import { ChatPageRouteParams } from './ChatPage';
import { getPreferencesService } from '../services/PreferencesService';
import { paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';

// 新建会话页（NavDestination）—— 选 machine + 工作目录 + agent → spawn 产生新会话
// 协议对照 hapi web /sessions/new：spawn 流程（非 POST /api/sessions）
//   GET /api/machines（列机器）+ POST /api/machines/:id/list-directory（浏览目录）+ POST /api/machines/:id/spawn（核心新建）
// spawn 第一版只传 directory + agent；model/effort/yolo/sessionType 用上游默认（'auto'）
// 通过 router_map.json 注册（NewSessionPageBuilder），由 Index 的 NavPathStack.pushPath('NewSessionPage') 触发
// 颜色经统一主题（theme/ThemeService）—— 读 getThemeState().isDark 取调色板，切换/跟随系统即时响应

// 持久化 key：上次所选机器 / 偏好 agent / 偏好 yolo / 各机器最近路径（JSON 数组）
const KEY_LAST_MACHINE: string = 'last_machine_id';
const KEY_PREFERRED_AGENT: string = 'preferred_agent';
const KEY_PREFERRED_YOLO: string = 'preferred_yolo';
const KEY_RECENT_PREFIX: string = 'recent_paths_';   // + machineId
const RECENT_MAX: number = 8;

@ComponentV2
struct NewSessionPage {
  @Local machines: Machine[] = [];
  @Local loadingMachines: boolean = false;
  @Local loadError: string = '';

  @Local selectedMachineId: string = '';
  @Local directory: string = '';
  @Local recentPaths: string[] = [];
  @Local selectedAgent: string = 'claude';

  // spawn 高级选项（对照上游 web NewSession 表单）
  @Local selectedModel: string = 'auto';          // 'auto'=默认（省略，agent 用自身默认）
  @Local selectedEffort: string = 'auto';          // 仅 claude；'auto'=省略
  @Local yolo: boolean = false;                    // --yolo（持久化 preferred_yolo）
  @Local selectedSessionType: string = 'simple';   // 'simple' | 'worktree'
  @Local worktreeName: string = '';                // sessionType==='worktree' 时填

  @Local isSpawning: boolean = false;
  @Local spawnError: string = '';

  // 目录树浏览弹层（bindSheet，内部 @Builder，不上独立路由——避免 NavPathStack pop 回值复杂）
  @Local browserVisible: boolean = false;
  @Local browserPath: string = '/';
  @Local browserEntries: DirEntry[] = [];
  @Local browserLoading: boolean = false;
  @Local browserError: string = '';

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  private navPathStack: NavPathStack | null = null;

  aboutToAppear(): void {
    this.loadMachines();
  }

  // 拉机器列表 → 选默认（持久化 last_machine_id 命中 → 否则 machines[0]）→ 读偏好 agent + 最近路径
  private async loadMachines(): Promise<void> {
    this.loadingMachines = true;
    this.loadError = '';
    try {
      const list: Machine[] = await getHubClient().getMachines();
      this.machines = list;
      if (list.length === 0) {
        this.loadError = '没有可用的机器，请先在终端启动 hapi';
        return;
      }
      const lastId: string = await getPreferencesService().getString(KEY_LAST_MACHINE, '');
      let chosenId: string = '';
      if (lastId !== '') {
        for (let i = 0; i < list.length; i++) {
          if (list[i].id === lastId) { chosenId = lastId; break; }
        }
      }
      if (chosenId === '') { chosenId = list[0].id; }
      this.selectedMachineId = chosenId;

      const prefAgent: string = await getPreferencesService().getString(KEY_PREFERRED_AGENT, '');
      if (prefAgent !== '') { this.selectedAgent = prefAgent; }

      const prefYolo: boolean = await getPreferencesService().getBoolean(KEY_PREFERRED_YOLO, false);
      this.yolo = prefYolo;

      await this.loadRecentFor(chosenId);
    } catch (e) {
      this.loadError = e instanceof Error ? e.message : '加载机器失败';
    } finally {
      this.loadingMachines = false;
    }
  }

  // 读某机器最近路径，预填 directory（仅当前为空时）
  private async loadRecentFor(machineId: string): Promise<void> {
    const recent: string[] = await this.readRecent(machineId);
    this.recentPaths = recent;
    if (this.directory === '' && recent.length > 0) {
      this.directory = recent[0];
    }
  }

  private onMachineSelected(index: number): void {
    if (index < 0 || index >= this.machines.length) { return; }
    this.selectedMachineId = this.machines[index].id;
    this.directory = '';        // 切 machine 清空目录（不同机器路径不通用）
    this.recentPaths = [];
    this.loadRecentFor(this.selectedMachineId);
  }

  private onAgentSelected(index: number): void {
    if (index < 0 || index >= AGENT_FLAVORS.length) { return; }
    this.selectedAgent = AGENT_FLAVORS[index];
    // 切 agent 重置 model/effort（对照上游 index.tsx:73-77，不同 agent 的模型/努力域不同）
    this.selectedModel = 'auto';
    this.selectedEffort = 'auto';
  }

  private useRecentPath(path: string): void {
    this.directory = path;
  }

  // —— Machine / Agent 下拉选项与索引（Select 需 options + selected idx + value 文本三件套）——
  private machineIndex(): number {
    for (let i = 0; i < this.machines.length; i++) {
      if (this.machines[i].id === this.selectedMachineId) { return i; }
    }
    return -1;
  }
  private machineOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    for (let i = 0; i < this.machines.length; i++) {
      const m: Machine = this.machines[i];
      opts.push({ value: m.displayName !== '' ? m.displayName : m.id });
    }
    return opts;
  }
  private machineValueDisplay(): string {
    const idx: number = this.machineIndex();
    if (idx < 0) { return this.loadingMachines ? '加载中…' : '请选择机器'; }
    const m: Machine = this.machines[idx];
    return m.displayName !== '' ? m.displayName : m.id;
  }
  private agentIndex(): number {
    for (let i = 0; i < AGENT_FLAVORS.length; i++) {
      if (AGENT_FLAVORS[i] === this.selectedAgent) { return i; }
    }
    return 0;
  }
  private agentOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    for (let i = 0; i < AGENT_FLAVORS.length; i++) {
      opts.push({ value: agentDisplayName(AGENT_FLAVORS[i]) });
    }
    return opts;
  }

  // —— Model 下拉（claude/gemini 静态预设 + 「默认」=auto；codex/cursor/opencode/kimi 仅「默认」）——
  //   options 首项恒为「默认」(auto)，其后接 modelOptionsForAgent(agent) 的预设。codex/cursor/opencode 的
  //   live model 列表未接（需 codex-models/cursor-models/opencode-models 端点），'auto' 即 agent 默认。
  private modelPresets(): string[] {
    return modelOptionsForAgent(this.selectedAgent);
  }
  private modelIndex(): number {
    if (this.selectedModel === 'auto' || this.selectedModel === '') { return 0; }
    const presets: string[] = this.modelPresets();
    for (let i = 0; i < presets.length; i++) {
      if (presets[i] === this.selectedModel) { return i + 1; }
    }
    return 0;   // 选中的不在预设列表 → 回退「默认」
  }
  private modelOptions(): SelectOption[] {
    const opts: SelectOption[] = [{ value: '默认' }];
    const presets: string[] = this.modelPresets();
    for (let i = 0; i < presets.length; i++) {
      opts.push({ value: modelDisplayName(this.selectedAgent, presets[i]) });
    }
    return opts;
  }
  private onModelSelected(index: number): void {
    if (index === 0) { this.selectedModel = 'auto'; return; }
    const presets: string[] = this.modelPresets();
    const i: number = index - 1;
    if (i >= 0 && i < presets.length) { this.selectedModel = presets[i]; }
  }

  // —— Effort 下拉（仅 claude；'auto'=省略）——
  private effortIndex(): number {
    for (let i = 0; i < EFFORT_OPTIONS.length; i++) {
      if (EFFORT_OPTIONS[i] === this.selectedEffort) { return i; }
    }
    return 0;
  }
  private effortOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    for (let i = 0; i < EFFORT_OPTIONS.length; i++) {
      opts.push({ value: effortDisplayName(EFFORT_OPTIONS[i]) });
    }
    return opts;
  }
  private onEffortSelected(index: number): void {
    if (index >= 0 && index < EFFORT_OPTIONS.length) { this.selectedEffort = EFFORT_OPTIONS[index]; }
  }

  // —— SessionType 下拉（simple 普通 / worktree 工作树）——
  private sessionTypeIndex(): number {
    for (let i = 0; i < SESSION_TYPES.length; i++) {
      if (SESSION_TYPES[i] === this.selectedSessionType) { return i; }
    }
    return 0;
  }
  private sessionTypeOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    for (let i = 0; i < SESSION_TYPES.length; i++) {
      opts.push({ value: sessionTypeDisplayName(SESSION_TYPES[i]) });
    }
    return opts;
  }
  private onSessionTypeSelected(index: number): void {
    if (index >= 0 && index < SESSION_TYPES.length) {
      this.selectedSessionType = SESSION_TYPES[index];
      if (this.selectedSessionType !== 'worktree') { this.worktreeName = ''; }
    }
  }

  private toggleYolo(): void {
    this.yolo = !this.yolo;
  }

  // —— 目录树浏览（bindSheet 内）——
  private openBrowser(): void {
    if (this.selectedMachineId === '') {
      this.toast('请先选择机器');
      return;
    }
    this.browserVisible = true;
    const startPath: string = this.directory.trim() !== '' ? this.directory.trim() : '/';
    this.loadBrowserDir(startPath);
  }
  private async loadBrowserDir(path: string): Promise<void> {
    if (this.selectedMachineId === '') { return; }
    this.browserLoading = true;
    this.browserError = '';
    try {
      const entries: DirEntry[] = await getHubClient().listMachineDirectory(this.selectedMachineId, path);
      this.browserEntries = entries;
      this.browserPath = path;
    } catch (e) {
      this.browserError = e instanceof Error ? e.message : '浏览目录失败';
    } finally {
      this.browserLoading = false;
    }
  }
  // DirEntry 无绝对 path（只有 name），UI 拼 currentPath + '/' + name 进子目录
  private joinChildPath(parent: string, name: string): string {
    if (parent === '/') { return `/${name}`; }
    return `${parent}/${name}`;
  }
  private parentPath(p: string): string {
    const i: number = p.lastIndexOf('/');
    if (i <= 0) { return '/'; }
    return p.substring(0, i);
  }
  private enterDir(entry: DirEntry): void {
    if (entry.type !== 'directory') { return; }
    this.loadBrowserDir(this.joinChildPath(this.browserPath, entry.name));
  }
  private goParent(): void {
    const p: string = this.parentPath(this.browserPath);
    if (p !== this.browserPath) { this.loadBrowserDir(p); }
  }
  private pickCurrentDir(): void {
    this.directory = this.browserPath;
    this.browserVisible = false;
  }
  // 目录排序：文件夹在前，再按名升序
  private sortedBrowserEntries(): DirEntry[] {
    const arr: DirEntry[] = this.browserEntries.slice();
    arr.sort((a: DirEntry, b: DirEntry) => {
      const ad: boolean = a.type === 'directory';
      const bd: boolean = b.type === 'directory';
      if (ad !== bd) { return ad ? -1 : 1; }
      if (a.name < b.name) { return -1; }
      if (a.name > b.name) { return 1; }
      return 0;
    });
    return arr;
  }

  // —— 创建会话（spawn）——
  private async createSession(): Promise<void> {
    this.spawnError = '';
    if (this.selectedMachineId === '') { this.spawnError = '请选择机器'; return; }
    const dir: string = this.directory.trim();
    if (dir === '') { this.spawnError = '请填写工作目录'; return; }
    this.isSpawning = true;
    try {
      // worktree 自定义名：trim 后透传（空则服务端自动生成，上游 worktreeName 非必填）
      const wt: string = this.selectedSessionType === 'worktree' ? this.worktreeName.trim() : '';
      const sid: string = await getHubClient().spawnSession(
        this.selectedMachineId, dir, this.selectedAgent,
        this.selectedModel, this.selectedEffort, this.yolo, this.selectedSessionType, wt
      );
      // 持久化（last_machine_id / preferred_agent / preferred_yolo / 最近路径）
      await getPreferencesService().putString(KEY_LAST_MACHINE, this.selectedMachineId);
      await getPreferencesService().putString(KEY_PREFERRED_AGENT, this.selectedAgent);
      await getPreferencesService().putBoolean(KEY_PREFERRED_YOLO, this.yolo);
      await this.saveRecent(this.selectedMachineId, dir);
      // 进新会话：pop 本页 + pushPath ChatPage（栈回到 Index → ChatPage）
      if (this.navPathStack !== null) {
        this.navPathStack.pop();
        const params: ChatPageRouteParams = new ChatPageRouteParams();
        params.sessionId = sid;
        params.title = this.baseName(dir);
        this.navPathStack.pushPath({ name: 'ChatPage', param: params });
      }
    } catch (e) {
      this.spawnError = this.errMsg(e);
    } finally {
      this.isSpawning = false;
    }
  }

  private baseName(p: string): string {
    const i: number = p.lastIndexOf('/');
    return i >= 0 ? p.substring(i + 1) : p;
  }

  private errMsg(e: Object): string {
    if (e instanceof Error) { return e.message; }
    try { return JSON.stringify(e); } catch (x) { return '启动会话失败'; }
  }

  private async readRecent(machineId: string): Promise<string[]> {
    const key: string = `${KEY_RECENT_PREFIX}${machineId}`;
    const raw: string = await getPreferencesService().getString(key, '');
    if (raw === '') { return []; }
    try {
      const parsed: Object = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        const arr: Object[] = parsed as Object[];
        const out: string[] = [];
        for (let i = 0; i < arr.length; i++) {
          if (typeof arr[i] === 'string') { out.push(arr[i] as string); }
        }
        return out;
      }
    } catch (e) {
      return [];
    }
    return [];
  }

  // 最近路径：unshift 当前，去重，限 RECENT_MAX，JSON.stringify 存
  private async saveRecent(machineId: string, path: string): Promise<void> {
    const key: string = `${KEY_RECENT_PREFIX}${machineId}`;
    const current: string[] = await this.readRecent(machineId);
    const next: string[] = [path];
    for (let i = 0; i < current.length; i++) {
      if (current[i] !== path && next.length < RECENT_MAX) {
        next.push(current[i]);
      }
    }
    await getPreferencesService().putString(key, JSON.stringify(next));
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
  }

  @Builder
  private FieldLabel(text: string) {
    Text(text)
      .fontSize(13)
      .fontColor(this.c.textTertiary)
      .width('100%')
      .padding({ left: 16, top: 18, bottom: 6 })
  }

  @Builder
  private RecentPathRow(path: string) {
    Row({ space: 8 }) {
      Text('📁').fontSize(14)
      Text(path)
        .fontSize(13)
        .fontColor(this.c.textSecondary)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(40)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.useRecentPath(path); })
  }

  @Builder
  private BrowserEntryRow(entry: DirEntry) {
    Row({ space: 10 }) {
      Text(entry.type === 'directory' ? '📁' : '📄').fontSize(16)
      Text(entry.name)
        .fontSize(14)
        .fontColor(entry.type === 'directory' ? this.c.textPrimary : this.c.textTertiary)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (entry.isGitRepo) {
        Text('git')
          .fontSize(10)
          .fontColor(this.c.bubbleUserText)
          .backgroundColor(this.c.primary)
          .borderRadius(4)
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .opacity(entry.type === 'directory' ? 1 : 0.6)
    .onClick(() => { this.enterDir(entry); })
  }

  // 目录浏览半模态弹层（bindSheet 内容）
  @Builder
  private DirectoryBrowser() {
    Column() {
      // 当前路径 + 回上级
      Row() {
        Button('回上级')
          .fontSize(13)
          .height(32)
          .backgroundColor(this.c.surface)
          .fontColor(this.c.textSecondary)
          .borderRadius(8)
          .onClick(() => { this.goParent(); })
        Text(this.browserPath)
          .fontSize(12)
          .fontColor(this.c.textTertiary)
          .layoutWeight(1)
          .margin({ left: 10 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      if (this.browserLoading) {
        Column() {
          LoadingProgress().width(32).height(32).color(this.c.primary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.browserError !== '') {
        Column({ space: 8 }) {
          Text('加载失败').fontSize(14).fontColor(this.c.error)
          Text(this.browserError).fontSize(12).fontColor(this.c.textTertiary).textAlign(TextAlign.Center)
          Button('重试')
            .fontSize(13).height(32)
            .backgroundColor(this.c.primary).fontColor(this.c.bubbleUserText)
            .onClick(() => { this.loadBrowserDir(this.browserPath); })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.browserEntries.length === 0) {
        Column() {
          Text('空目录').fontSize(13).fontColor(this.c.textTertiary)
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.sortedBrowserEntries(), (entry: DirEntry) => {
            ListItem() {
              this.BrowserEntryRow(entry)
            }
          }, (entry: DirEntry) => `${entry.name}:${entry.type}`)
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: this.c.border, startMargin: 40, endMargin: 16 })
      }

      // 选择当前目录
      Button('选择此目录')
        .width('100%')
        .height(48)
        .margin({ top: 8, bottom: 12 })
        .backgroundColor(this.c.primary)
        .fontColor(this.c.bubbleUserText)
        .borderRadius(12)
        .onClick(() => { this.pickCurrentDir(); })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.c.bg)
  }

  build() {
    NavDestination() {
      Column() {
        // 机器拉取失败兜底（无机器则无法继续）
        if (this.loadError !== '' && this.machines.length === 0) {
          Column({ space: 12 }) {
            Text('加载失败').fontSize(16).fontColor(this.c.error)
            Text(this.loadError).fontSize(13).fontColor(this.c.textTertiary).textAlign(TextAlign.Center)
            Button('重试')
              .backgroundColor(this.c.primary)
              .fontColor(this.c.bubbleUserText)
              .onClick(() => { this.loadMachines(); })
          }
          .width('100%').height('100%').justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              // 机器
              this.FieldLabel('机器')
              Column() {
                Select(this.machineOptions())
                  .selected(this.machineIndex())
                  .value(this.machineValueDisplay())
                  .onSelect((index: number, text: string) => { this.onMachineSelected(index); })
                  .width('100%')
                  .height(50)
              }
              .width('100%')
              .padding({ left: 16, right: 16 })
              .backgroundColor(this.c.bg)

              // 工作目录
              this.FieldLabel('工作目录')
              Column({ space: 0 }) {
                TextInput({ text: this.directory, placeholder: '如 /home/user/project' })
                  .height(48)
                  .fontSize(14)
                  .backgroundColor(this.c.surface)
                  .borderRadius(10)
                  .onChange((value: string) => { this.directory = value; })

                Button('选择文件夹…')
                  .width('100%')
                  .height(40)
                  .margin({ top: 8 })
                  .backgroundColor(this.c.surface)
                  .fontColor(this.c.textSecondary)
                  .borderRadius(8)
                  .onClick(() => { this.openBrowser(); })

                // 最近路径联想
                if (this.recentPaths.length > 0) {
                  Text('最近')
                    .fontSize(12)
                    .fontColor(this.c.textTertiary)
                    .width('100%')
                    .margin({ top: 10, bottom: 2 })
                  Column() {
                    ForEach(this.recentPaths, (path: string) => {
                      this.RecentPathRow(path)
                    }, (path: string) => path)
                  }
                  .width('100%')
                  .backgroundColor(this.c.bg)
                  .borderRadius(10)
                  .margin({ top: 2 })
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16 })

              // Agent
              this.FieldLabel('Agent')
              Column() {
                Select(this.agentOptions())
                  .selected(this.agentIndex())
                  .value(agentDisplayName(this.selectedAgent))
                  .onSelect((index: number, text: string) => { this.onAgentSelected(index); })
                  .width('100%')
                  .height(50)
              }
              .width('100%')
              .padding({ left: 16, right: 16 })
              .backgroundColor(this.c.bg)

              // 模型（claude/gemini 静态预设 + 「默认」=auto；其余 agent 仅「默认」）
              this.FieldLabel('模型')
              Column() {
                Select(this.modelOptions())
                  .selected(this.modelIndex())
                  .value(modelDisplayName(this.selectedAgent, this.selectedModel))
                  .onSelect((index: number, text: string) => { this.onModelSelected(index); })
                  .width('100%')
                  .height(50)
              }
              .width('100%')
              .padding({ left: 16, right: 16 })
              .backgroundColor(this.c.bg)

              // 努力程度（仅 claude；对照 web ClaudeEffort，'auto'=省略）
              if (this.selectedAgent === 'claude') {
                this.FieldLabel('努力程度')
                Column() {
                  Select(this.effortOptions())
                    .selected(this.effortIndex())
                    .value(effortDisplayName(this.selectedEffort))
                    .onSelect((index: number, text: string) => { this.onEffortSelected(index); })
                    .width('100%')
                    .height(50)
                }
                .width('100%')
                .padding({ left: 16, right: 16 })
                .backgroundColor(this.c.bg)
              }

              // 会话类型（simple 普通 / worktree 工作树）
              this.FieldLabel('会话类型')
              Column({ space: 8 }) {
                Select(this.sessionTypeOptions())
                  .selected(this.sessionTypeIndex())
                  .value(sessionTypeDisplayName(this.selectedSessionType))
                  .onSelect((index: number, text: string) => { this.onSessionTypeSelected(index); })
                  .width('100%')
                  .height(50)

                // 工作树自定义名（worktree 时显示；留空则服务端自动生成）
                if (this.selectedSessionType === 'worktree') {
                  TextInput({ text: this.worktreeName, placeholder: '工作树名（可选，留空自动生成）' })
                    .height(44)
                    .fontSize(14)
                    .backgroundColor(this.c.surface)
                    .borderRadius(10)
                    .onChange((value: string) => { this.worktreeName = value; })
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16 })
              .backgroundColor(this.c.bg)

              // Yolo（跳过权限确认 = --yolo；持久化 preferred_yolo）—— 行内可点切换
              this.FieldLabel('选项')
              Column() {
                Row() {
                  Column({ space: 2 }) {
                    Text('Yolo 模式').fontSize(14).fontColor(this.c.textPrimary)
                    Text('跳过权限确认（--yolo）').fontSize(11).fontColor(this.c.textTertiary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Text(this.yolo ? '✓' : '○')
                    .fontSize(18)
                    .fontColor(this.yolo ? this.c.primary : this.c.textTertiary)
                }
                .width('100%')
                .height(56)
                .padding({ left: 16, right: 16 })
                .alignItems(VerticalAlign.Center)
                .onClick(() => { this.toggleYolo(); })
              }
              .width('100%')
              .backgroundColor(this.c.bg)

              // 错误提示
              if (this.spawnError !== '') {
                Text(this.spawnError)
                  .fontSize(12)
                  .fontColor(this.c.error)
                  .width('100%')
                  .padding({ left: 16, top: 12 })
              }

              // 创建按钮
              Button(this.isSpawning ? '创建中…' : '创建会话')
                .width('100%')
                .height(50)
                .margin({ top: 24, left: 16, right: 16, bottom: 24 })
                .backgroundColor(this.c.primary)
                .fontColor(this.c.bubbleUserText)
                .borderRadius(12)
                .enabled(!this.isSpawning && this.machines.length > 0)
                .onClick(() => { this.createSession(); })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.c.surface)
    }
    .title('新建会话')
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack;
    })
    .bindSheet(this.browserVisible!!, this.DirectoryBrowser(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      blurStyle: BlurStyle.Thick,
      title: { title: '选择文件夹' }
    })
  }
}

// 系统路由表 buildFunction（router_map.json 引用）
@Builder
export function NewSessionPageBuilder(name: string, param: Object) {
  NewSessionPage()
}
