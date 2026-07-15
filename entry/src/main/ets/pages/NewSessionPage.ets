import { getHubClient } from '../api/HubClient';
import { t } from '../i18n/I18nService';
import { Machine, DirEntry, SessionSummary, AGENT_FLAVORS, agentDisplayName, modelOptionsForAgent, modelDisplayName, ModelOption, MODEL_AUTO, EFFORT_OPTIONS, effortDisplayName, SESSION_TYPES, sessionTypeDisplayName, reasoningEffortsForFlavor, reasoningEffortDisplayName } from '../models/Types';
import { formatMachineSpawnError } from '../chat/SpawnError';
import { buildDirectorySuggestions } from '../chat/DirectorySuggestions';
import { ChatPageRouteParams } from './ChatPage';
import { getPreferencesService } from '../services/PreferencesService';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { showToast } from '../utils/Toast';

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

// 路由参数（对照 ChatPageRouteParams）：会话列表「本目录新建」+ 按钮预填 machine + directory。
//   Index pushPath({name:'NewSessionPage', param}) 透传；NewSessionPageBuilder 转 @Param routeParamsSeed。
export class NewSessionPageRouteParams {
  machineId: string = '';
  directory: string = '';
}

@ComponentV2
struct NewSessionPage {
  @Local machines: Machine[] = [];
  @Local loadingMachines: boolean = false;
  @Local loadError: string = '';

  @Local selectedMachineId: string = '';
  @Local directory: string = '';
  @Local recentPaths: string[] = [];
  // 全量会话（fetchSessions 一次；DirectorySuggestions 按选中 machine 内部过滤派生 path/worktree 建议）
  @Local allSessions: SessionSummary[] = [];
  @Local selectedAgent: string = 'claude';

  // spawn 高级选项（对照上游 web NewSession 表单）
  @Local selectedModel: string = 'auto';          // 'auto'=默认（省略，agent 用自身默认）
  @Local dynamicModels: ModelOption[] = [];        // codex/cursor/opencode 拉取的 live model 列表（claude/gemini/kimi 留空走静态）
  @Local selectedEffort: string = 'auto';          // 仅 claude；'auto'=省略
  @Local yolo: boolean = false;                    // --yolo（持久化 preferred_yolo）
  @Local selectedSessionType: string = 'simple';   // 'simple' | 'worktree'
  @Local worktreeName: string = '';                // sessionType==='worktree' 时填
  @Local selectedReasoningEffort: string = '';     // codex/opencode 推理努力；''=默认（省略，对照上游 spawn optional）

  @Local isSpawning: boolean = false;
  @Local spawnError: string = '';

  // 目录树浏览弹层（bindSheet，内部 @Builder，不上独立路由——避免 NavPathStack pop 回值复杂）
  @Local browserVisible: boolean = false;
  @Local browserPath: string = '/';
  @Local browserEntries: DirEntry[] = [];
  @Local browserLoading: boolean = false;
  @Local browserError: string = '';

  // 路由预填（会话列表「本目录新建」+ 按钮透传 machine + directory；对照 ChatPage routeParamsSeed）。
  //   空值（普通 + 入口）→ null，aboutToAppear 走默认选机 + 最近路径。
  @Param routeParamsSeed: NewSessionPageRouteParams | null = null;

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  private navPathStack: NavPathStack | null = null;

  aboutToAppear(): void {
    // 路由预填（「本目录新建」）：directory 直播种（loadRecentFor 见非空不再覆盖）；
    //   machineId 作为优先候选传 loadMachines（命中即选，覆盖 last_machine_id）。
    const seed: NewSessionPageRouteParams | null = this.routeParamsSeed;
    const preMachine: string = (seed !== null && seed !== undefined) ? seed.machineId : '';
    const preDirectory: string = (seed !== null && seed !== undefined) ? seed.directory : '';
    if (preDirectory !== '') { this.directory = preDirectory; }
    this.loadMachines(preMachine);
  }

  // 拉机器列表 → 选默认（路由预填机器命中 → 否则 last_machine_id → 否则 machines[0]）→ 读偏好 agent + 最近路径。
  //   preferredMachineId 来自路由预填（「本目录新建」）；非空且命中列表时优先于持久化 last_machine_id。
  private async loadMachines(preferredMachineId: string = ''): Promise<void> {
    this.loadingMachines = true;
    this.loadError = '';
    try {
      const list: Machine[] = await getHubClient().getMachines();
      this.machines = list;
      if (list.length === 0) {
        this.loadError = t('newSession.noMachinesHint');
        return;
      }
      let chosenId: string = '';
      // 1. 路由预填机器优先（「本目录新建」明确指定了 machine）
      if (preferredMachineId !== '') {
        for (let i = 0; i < list.length; i++) {
          if (list[i].id === preferredMachineId) { chosenId = preferredMachineId; break; }
        }
      }
      // 2. 持久化 last_machine_id
      if (chosenId === '') {
        const lastId: string = await getPreferencesService().getString(KEY_LAST_MACHINE, '');
        if (lastId !== '') {
          for (let i = 0; i < list.length; i++) {
            if (list[i].id === lastId) { chosenId = lastId; break; }
          }
        }
      }
      // 3. 首台兜底
      if (chosenId === '') { chosenId = list[0].id; }
      this.selectedMachineId = chosenId;

      const prefAgent: string = await getPreferencesService().getString(KEY_PREFERRED_AGENT, '');
      if (prefAgent !== '') { this.selectedAgent = prefAgent; }

      const prefYolo: boolean = await getPreferencesService().getBoolean(KEY_PREFERRED_YOLO, false);
      this.yolo = prefYolo;

      await this.loadRecentFor(chosenId);
      await this.refreshModels();   // 初始：按 agent + machine(+预填目录 for opencode) 拉一次 model 列表
      // 拉全量会话供 DirectorySuggestions 派生（path/worktree 建议）；best-effort，失败不阻塞页面
      try { this.allSessions = await getHubClient().fetchSessions(); } catch (e) {}
    } catch (e) {
      this.loadError = e instanceof Error ? e.message : t('newSession.loadMachinesFailed');
    } finally {
      this.loadingMachines = false;
    }
  }

  // 读某机器最近路径，预填 directory（仅当前为空时）
  private async loadRecentFor(machineId: string): Promise<void> {
    const recent: string[] = await this.readRecent(machineId);
    this.recentPaths = recent;
    if (this.directory === '' && recent.length > 0) {
      this.applyDirectory(recent[0]);
    }
  }

  private onMachineSelected(index: number): void {
    if (index < 0 || index >= this.machines.length) { return; }
    this.selectedMachineId = this.machines[index].id;
    this.directory = '';        // 切 machine 清空目录（不同机器路径不通用）
    this.recentPaths = [];
    this.loadRecentFor(this.selectedMachineId);
    this.refreshModels();       // machine 变 → 重拉 codex/cursor/opencode 模型列表（loadRecentFor 预填目录后 opencode 另由 applyDirectory 再拉一次）
  }

  private onAgentSelected(index: number): void {
    if (index < 0 || index >= AGENT_FLAVORS.length) { return; }
    this.selectedAgent = AGENT_FLAVORS[index];
    // 切 agent 重置 model/effort/reasoning（对照上游 index.tsx:73-77，不同 agent 的模型/努力域不同）
    this.selectedModel = 'auto';
    this.selectedEffort = 'auto';
    this.selectedReasoningEffort = '';
    this.refreshModels();       // agent 变 → 按 新 agent 决定拉 codex/cursor/opencode 还是清空（claude/gemini/kimi）
  }

  private useRecentPath(path: string): void {
    this.applyDirectory(path);
  }

  // 目录建议（对照上游 useDirectorySuggestions）：recent 在前 + 同机会话的 path/worktree basePath
  //   合并去重 + 其余按 localeCompare。machineId 过滤在纯函数内部（null→全部）。
  get directorySuggestions(): string[] {
    return buildDirectorySuggestions(this.selectedMachineId, this.allSessions, this.recentPaths);
  }

  // 统一目录赋值入口：切目录时若 agent=opencode 重拉 model 列表（opencode 的可用模型随 cwd 变）。
  //   codex/cursor 的模型列表只随 machine 变（machine/agent 切换时 refreshModels 已覆盖），此处不重复拉。
  //   注：TextInput 手输路径不走此入口（避免逐键请求）；opencode 手输新路径时 model 列表保持现状，「默认」始终可用。
  private applyDirectory(v: string): void {
    this.directory = v;
    if (this.selectedAgent === 'opencode') { this.refreshModels(); }
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
    if (idx < 0) { return this.loadingMachines ? t('common.loading') : t('newSession.selectMachine'); }
    const m: Machine = this.machines[idx];
    return m.displayName !== '' ? m.displayName : m.id;
  }
  // 当前所选机器的上次 spawn 错误诊断文案（对照上游 formatRunnerSpawnError；message 空 → ''）。
  //   红字提示，不阻止创建（仅诊断；用户仍可重试）。
  private machineSpawnErrorText(): string {
    const idx: number = this.machineIndex();
    if (idx < 0) { return ''; }
    const m: Machine = this.machines[idx];
    return formatMachineSpawnError(m.lastSpawnErrorMessage, m.lastSpawnErrorAt);
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

  // —— Model 下拉（「默认」=auto + claude/gemini 静态预设 + codex/cursor/opencode 动态拉取，按 id 去重）——
  //   codex/cursor/opencode 的 live model 列表经 refreshModels() 从 Hub 拉（对应上游 codex-models /
  //   cursor-models / opencode-models 端点）；claude/gemini/kimi 走静态预设，dynamicModels 留空。
  //   条目顺序：[auto 默认] + modelOptionsForAgent(agent) 静态预设 + dynamicModels 动态，id 去重（auto/静态优先）。
  private appendUnique(list: ModelOption[], id: string, label: string): void {
    for (let i = 0; i < list.length; i++) { if (list[i].id === id) { return; } }
    const o: ModelOption = new ModelOption();
    o.id = id;
    o.label = label;
    list.push(o);
  }
  private modelEntries(): ModelOption[] {
    const out: ModelOption[] = [];
    this.appendUnique(out, MODEL_AUTO, t('newSession.model.default'));
    const presets: string[] = modelOptionsForAgent(this.selectedAgent);
    for (let i = 0; i < presets.length; i++) {
      this.appendUnique(out, presets[i], modelDisplayName(this.selectedAgent, presets[i]));
    }
    for (let i = 0; i < this.dynamicModels.length; i++) {
      this.appendUnique(out, this.dynamicModels[i].id, this.dynamicModels[i].label);
    }
    return out;
  }
  private modelIndex(): number {
    const entries: ModelOption[] = this.modelEntries();
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].id === this.selectedModel) { return i; }
    }
    return 0;   // 选中的不在列表 → 回退「默认」(auto)
  }
  private modelOptions(): SelectOption[] {
    const entries: ModelOption[] = this.modelEntries();
    const opts: SelectOption[] = [];
    for (let i = 0; i < entries.length; i++) { opts.push({ value: entries[i].label }); }
    return opts;
  }
  private onModelSelected(index: number): void {
    const entries: ModelOption[] = this.modelEntries();
    if (index >= 0 && index < entries.length) { this.selectedModel = entries[index].id; }
  }
  // Select 折叠态显示文本：按 selectedModel 在 modelEntries() 查 label（与下拉列表项一致；动态模型的 Hub label
  //   如 'GPT-5' 而非 id 'gpt-5'）；未命中（理论上不会，auto 必在）回落「默认」。
  private modelValueDisplay(): string {
    const entries: ModelOption[] = this.modelEntries();
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].id === this.selectedModel) { return entries[i].label; }
    }
    return t('newSession.model.default');
  }

  // 按 agent + machine（opencode 另带 cwd）拉 live model 列表 → 写 @Local dynamicModels。
  //   claude/gemini/kimi：纯静态预设，无需拉取 → 清空。
  //   codex：getMachineCodexModels(machineId)；cursor：getMachineCursorModels(machineId)。
  //   opencode：依赖 cwd，directory 空 → 跳过（上游对空 cwd 不探测，避免误报）；非空 → getMachineOpencodeModels(machineId, cwd)。
  //   失败静默 → 清空（回落「默认」=auto 单选，不阻塞建会话）。防竞态：await 后若 agent/machine 已变则丢弃过期结果。
  private async refreshModels(): Promise<void> {
    const agent: string = this.selectedAgent;
    const machineId: string = this.selectedMachineId;
    if (agent !== 'codex' && agent !== 'cursor' && agent !== 'opencode') {
      this.dynamicModels = [];
      return;
    }
    if (machineId === '') { this.dynamicModels = []; return; }
    try {
      let models: ModelOption[] = [];
      if (agent === 'codex') {
        models = await getHubClient().getMachineCodexModels(machineId);
      } else if (agent === 'cursor') {
        models = await getHubClient().getMachineCursorModels(machineId);
      } else {   // opencode
        const cwd: string = this.directory.trim();
        if (cwd === '') { this.dynamicModels = []; return; }
        models = await getHubClient().getMachineOpencodeModels(machineId, cwd);
      }
      if (this.selectedAgent !== agent || this.selectedMachineId !== machineId) { return; }   // 过期结果丢弃
      this.dynamicModels = models;
    } catch (e) {
      this.dynamicModels = [];   // 静默回落
    }
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

  // —— 推理努力下拉（仅 codex/opencode；''=默认省略，对照上游 spawn modelReasoningEffort optional）——
  //   首项 ''（默认）+ reasoningEffortsForFlavor(agent)；agent 决定 codex(low..xhigh) 或 opencode(low..max)。
  private reasoningEffortValues(): string[] {
    const base: string[] = reasoningEffortsForFlavor(this.selectedAgent);
    const out: string[] = [''];
    for (let i = 0; i < base.length; i++) { out.push(base[i]); }
    return out;
  }
  private reasoningEffortIndex(): number {
    const vals: string[] = this.reasoningEffortValues();
    for (let i = 0; i < vals.length; i++) {
      if (vals[i] === this.selectedReasoningEffort) { return i; }
    }
    return 0;
  }
  private reasoningEffortOptions(): SelectOption[] {
    const vals: string[] = this.reasoningEffortValues();
    const opts: SelectOption[] = [];
    opts.push({ value: t('newSession.model.default') });
    for (let i = 1; i < vals.length; i++) {
      opts.push({ value: reasoningEffortDisplayName(vals[i]) });
    }
    return opts;
  }
  private onReasoningEffortSelected(index: number): void {
    const vals: string[] = this.reasoningEffortValues();
    if (index >= 0 && index < vals.length) { this.selectedReasoningEffort = vals[index]; }
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
      showToast(t('newSession.pleaseSelectMachineFirst'));
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
      this.browserError = e instanceof Error ? e.message : t('newSession.browseFailed');
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
    this.applyDirectory(this.browserPath);   // 走统一入口：opencode 随新 cwd 重拉 model 列表
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
    if (this.selectedMachineId === '') { this.spawnError = t('newSession.selectMachine'); return; }
    const dir: string = this.directory.trim();
    if (dir === '') { this.spawnError = t('newSession.directoryRequired'); return; }
    // 路径存在性校验（对照上游 POST /api/machines/:id/paths/exists）：目录不存在即拦（用户选「统一拦截」）。
    //   探测本身抛错（网络/解析）放行，交 spawn 兜底——避免瞬态网络抖动误拦合法路径。
    try {
      const exists: boolean = await getHubClient().checkMachinePathExists(this.selectedMachineId, dir);
      if (!exists) { this.spawnError = t('newSession.directoryNotFound'); return; }
    } catch (_e) { /* 探测失败放行，spawn 兜底 */ }
    this.isSpawning = true;
    try {
      // worktree 自定义名：trim 后透传（空则服务端自动生成，上游 worktreeName 非必填）
      const wt: string = this.selectedSessionType === 'worktree' ? this.worktreeName.trim() : '';
      const sid: string = await getHubClient().spawnSession(
        this.selectedMachineId, dir, this.selectedAgent,
        this.selectedModel, this.selectedEffort, this.yolo, this.selectedSessionType, wt, this.selectedReasoningEffort
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
    try { return JSON.stringify(e); } catch (x) { return t('newSession.spawnFailed'); }
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

  @Builder
  private FieldLabel(text: string) {
    Text(text)
      .fontSize(fs(13))
      .fontColor(this.c.textTertiary)
      .width('100%')
      .padding({ left: 16, top: 18, bottom: 6 })
  }

  @Builder
  private RecentPathRow(path: string) {
    Row({ space: 8 }) {
      Text('📁').fontSize(fs(14))
      Text(path)
        .fontSize(fs(13))
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
      Text(entry.type === 'directory' ? '📁' : '📄').fontSize(fs(16))
      Text(entry.name)
        .fontSize(fs(14))
        .fontColor(entry.type === 'directory' ? this.c.textPrimary : this.c.textTertiary)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (entry.isGitRepo) {
        Text('git')
          .fontSize(fs(10))
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
        Button(t('newSession.parentDir'))
          .fontSize(fs(13))
          .height(32)
          .backgroundColor(this.c.surface)
          .fontColor(this.c.textSecondary)
          .borderRadius(8)
          .onClick(() => { this.goParent(); })
        Text(this.browserPath)
          .fontSize(fs(12))
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
          Text(t('newSession.loadFailed')).fontSize(fs(14)).fontColor(this.c.error)
          Text(this.browserError).fontSize(fs(12)).fontColor(this.c.textTertiary).textAlign(TextAlign.Center)
          Button(t('common.retry'))
            .fontSize(fs(13)).height(32)
            .backgroundColor(this.c.primary).fontColor(this.c.bubbleUserText)
            .onClick(() => { this.loadBrowserDir(this.browserPath); })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.browserEntries.length === 0) {
        Column() {
          Text(t('newSession.emptyDirectory')).fontSize(fs(13)).fontColor(this.c.textTertiary)
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
      Button(t('newSession.selectDirectory'))
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
            Text(t('newSession.loadFailed')).fontSize(fs(16)).fontColor(this.c.error)
            Text(this.loadError).fontSize(fs(13)).fontColor(this.c.textTertiary).textAlign(TextAlign.Center)
            Button(t('common.retry'))
              .backgroundColor(this.c.primary)
              .fontColor(this.c.bubbleUserText)
              .onClick(() => { this.loadMachines(); })
          }
          .width('100%').height('100%').justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              // 机器
              this.FieldLabel(t('newSession.machine'))
              Column() {
                Select(this.machineOptions())
                  .selected(this.machineIndex())
                  .value(this.machineValueDisplay())
                  .onSelect((index: number, text: string) => { this.onMachineSelected(index); })
                  .width('100%')
                  .height(50)

                // 该机器上次 spawn 错误诊断（Hub runnerState.lastSpawnError；非空才显示）
                if (this.machineSpawnErrorText() !== '') {
                  Text('⚠ ' + this.machineSpawnErrorText())
                    .fontSize(fs(12))
                    .fontColor(this.c.error)
                    .width('100%')
                    .margin({ top: 8 })
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16 })
              .backgroundColor(this.c.bg)

              // 工作目录
              this.FieldLabel(t('newSession.directory'))
              Column({ space: 0 }) {
                TextInput({ text: this.directory, placeholder: t('newSession.directoryPlaceholder') })
                  .height(48)
                  .fontSize(fs(14))
                  .backgroundColor(this.c.surface)
                  .borderRadius(10)
                  .onChange((value: string) => { this.directory = value; })

                Button(t('newSession.chooseFolder'))
                  .width('100%')
                  .height(40)
                  .margin({ top: 8 })
                  .backgroundColor(this.c.surface)
                  .fontColor(this.c.textSecondary)
                  .borderRadius(8)
                  .onClick(() => { this.openBrowser(); })

                // 目录建议（recent 在前 + 同机会话 path/worktree；对照上游 useDirectorySuggestions）
                if (this.directorySuggestions.length > 0) {
                  Text(t('newSession.recent'))
                    .fontSize(fs(12))
                    .fontColor(this.c.textTertiary)
                    .width('100%')
                    .margin({ top: 10, bottom: 2 })
                  Column() {
                    ForEach(this.directorySuggestions, (path: string) => {
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

              // 模型（「默认」=auto + claude/gemini 静态预设 + codex/cursor/opencode 动态拉取）
              this.FieldLabel(t('newSession.model'))
              Column() {
                Select(this.modelOptions())
                  .selected(this.modelIndex())
                  .value(this.modelValueDisplay())
                  .onSelect((index: number, text: string) => { this.onModelSelected(index); })
                  .width('100%')
                  .height(50)
              }
              .width('100%')
              .padding({ left: 16, right: 16 })
              .backgroundColor(this.c.bg)

              // 努力程度（仅 claude；对照 web ClaudeEffort，'auto'=省略）
              if (this.selectedAgent === 'claude') {
                this.FieldLabel(t('newSession.effort'))
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

              // 推理努力（仅 codex/opencode；对照 web ReasoningEffort，''=默认省略）
              if (this.selectedAgent === 'codex' || this.selectedAgent === 'opencode') {
                this.FieldLabel(t('sessionConfig.reasoningEffort'))
                Column() {
                  Select(this.reasoningEffortOptions())
                    .selected(this.reasoningEffortIndex())
                    .value(this.selectedReasoningEffort === '' ? t('newSession.model.default') : reasoningEffortDisplayName(this.selectedReasoningEffort))
                    .onSelect((index: number, text: string) => { this.onReasoningEffortSelected(index); })
                    .width('100%')
                    .height(50)
                }
                .width('100%')
                .padding({ left: 16, right: 16 })
                .backgroundColor(this.c.bg)
              }

              // 会话类型（simple 普通 / worktree 工作树）
              this.FieldLabel(t('newSession.type'))
              Column({ space: 8 }) {
                Select(this.sessionTypeOptions())
                  .selected(this.sessionTypeIndex())
                  .value(sessionTypeDisplayName(this.selectedSessionType))
                  .onSelect((index: number, text: string) => { this.onSessionTypeSelected(index); })
                  .width('100%')
                  .height(50)

                // 工作树自定义名（worktree 时显示；留空则服务端自动生成）
                if (this.selectedSessionType === 'worktree') {
                  TextInput({ text: this.worktreeName, placeholder: t('newSession.worktreeNamePlaceholder') })
                    .height(44)
                    .fontSize(fs(14))
                    .backgroundColor(this.c.surface)
                    .borderRadius(10)
                    .onChange((value: string) => { this.worktreeName = value; })
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16 })
              .backgroundColor(this.c.bg)

              // Yolo（跳过权限确认 = --yolo；持久化 preferred_yolo）—— 行内可点切换
              this.FieldLabel(t('newSession.options'))
              Column() {
                Row() {
                  Column({ space: 2 }) {
                    Text(t('newSession.yolo')).fontSize(fs(14)).fontColor(this.c.textPrimary)
                    Text(t('newSession.yoloDesc')).fontSize(fs(11)).fontColor(this.c.textTertiary)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Text(this.yolo ? '✓' : '○')
                    .fontSize(fs(18))
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
                  .fontSize(fs(12))
                  .fontColor(this.c.error)
                  .width('100%')
                  .padding({ left: 16, top: 12 })
              }

              // 创建按钮
              Button(this.isSpawning ? t('newSession.creating') : t('newSession.create'))
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
    .title(t('newSession.title'))
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack;
    })
    .bindSheet(this.browserVisible!!, this.DirectoryBrowser(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      blurStyle: BlurStyle.Thick,
      title: { title: t('newSession.chooseFolderTitle') }
    })
  }
}

// 系统路由表 buildFunction（router_map.json 引用）
@Builder
export function NewSessionPageBuilder(name: string, param: Object) {
  NewSessionPage({ routeParamsSeed: param as NewSessionPageRouteParams })
}
