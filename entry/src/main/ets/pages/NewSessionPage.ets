import { getHubClient } from '../api/HubClient';
import { t } from '../i18n/I18nService';
import { Machine, DirEntry, SessionSummary, AGENT_FLAVORS, agentDisplayName, modelOptionsForAgent, modelDisplayName, ModelOption, MODEL_AUTO, EFFORT_OPTIONS, effortDisplayName, SESSION_TYPES, sessionTypeDisplayName, reasoningEffortsForFlavor, reasoningEffortDisplayName } from '../models/Types';
import { formatMachineSpawnError } from '../chat/SpawnError';
import { buildDirectorySuggestions } from '../chat/DirectorySuggestions';
import { ChatPageRouteParams } from './ChatPage';
import { getPreferencesService } from '../services/PreferencesService';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { showToast } from '../utils/Toast';
import { SettingCard } from '../components/settings/SettingCard';
import { SheetDialog } from '../components/settings/SheetDialog';
import { SettingSectionTitle } from '../components/settings/SettingSectionTitle';
import { SettingActionButton } from '../components/settings/SettingActionButton';
import { buildSheetOptions, SheetOverrides } from '../components/settings/SheetOptionsFactory';
import { rowPos, resolveRowRadius } from '../components/settings/RowRadiusUtil';

// 新建会话页（NavDestination）—— 选 machine + 工作目录 + agent → spawn 产生新会话
// 协议对照 hapi web /sessions/new：spawn 流程（非 POST /api/sessions）
//   GET /api/machines（列机器）+ POST /api/machines/:id/list-directory（浏览目录）+ POST /api/machines/:id/spawn（核心新建）
// spawn 第一版只传 directory + agent；model/effort/yolo/sessionType 用上游默认（'auto'）
// 通过 router_map.json 注册（NewSessionPageBuilder），由 Index 的 NavPathStack.pushPath('NewSessionPage') 触发
// 颜色经统一主题（theme/ThemeService）—— 读 getThemeState().isDark 取调色板，切换/跟随系统即时响应
//
// 视觉对齐设置页 berry3 卡片风：List{ListItemGroup{SettingCard}} 分组白卡 r20 + 连续圆角咬合；
//   6 个选择字段（machine/agent/model/effort/reasoning/sessionType）收敛为单 picker sheet——主表单
//   SettingCard(textAndArrow) → 点击开 picker sheet。picker 内容照齐对话页模型弹窗（SessionConfigOverlay）：
//   半屏 [MEDIUM,LARGE] + 原生把手/关闭 + 胶囊选项行（左 radio 圆点 + 文字，非卡片形）；yolo=switch 行；
//   工作目录=点行开 DirectoryBrowser sheet（sheet 内保留手输）；创建按钮=SettingActionButton。

// 持久化 key：上次所选机器 / 偏好 agent / 偏好 yolo / 各机器最近路径（JSON 数组）
const KEY_LAST_MACHINE: string = 'last_machine_id';
const KEY_PREFERRED_AGENT: string = 'preferred_agent';
const KEY_PREFERRED_YOLO: string = 'preferred_yolo';
const KEY_RECENT_PREFIX: string = 'recent_paths_';   // + machineId
const RECENT_MAX: number = 8;

// picker 选项条目（label=显示 / value=回写值）
interface PickerEntry {
  label: string;
  value: string;
}
// picker 模式（单 sheet 复用 6 个选择字段）
type PickerMode = 'machine' | 'agent' | 'model' | 'effort' | 'reasoning' | 'sessionType';

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

  // 通用 picker sheet（6 个选择字段共用）
  @Local pickerOpen: boolean = false;
  @Local pickerMode: PickerMode = 'machine';

  // 目录树浏览弹层（bindSheet，内部 @Builder，不上独立路由——避免 NavPathStack pop 回值复杂）
  @Local browserVisible: boolean = false;
  @Local browserPath: string = '/';
  @Local browserPathInput: string = '';           // 手输/粘贴路径 draft（保留手输能力：主表单纯点选，sheet 内可手输）
  @Local browserEntries: DirEntry[] = [];
  @Local browserLoading: boolean = false;
  @Local browserError: string = '';

  // 路由预填（会话列表「本目录新建」+ 按钮透传 machine + directory；对照 ChatPage routeParamsSeed）。
  //   空值（普通 + 入口）→ null，aboutToAppear 走默认选机 + 最近路径。
  @Param routeParamsSeed: NewSessionPageRouteParams | null = null;

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }
  private get isDark(): boolean { return getThemeState().isDark; }
  // 半透明色（#RRGGBB → #AA{{RRGGBB}}，八位色 alpha 在前）—— picker 选中胶囊底用。
  private withAlpha(color: string, alphaHex: string): string {
    if (color.startsWith('#') && color.length === 7) {
      return `#${alphaHex}${color.substring(1)}`;
    }
    return color;
  }
  // picker 选中胶囊底（primary 半透明：暗 '28'/亮 '14'，对照 SessionConfigOverlay.selectedBg）。
  private selectedBg(): string { return this.withAlpha(this.c.primary, this.isDark ? '28' : '14'); }

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

  // 目录建议（对照上游 useDirectorySuggestions）：recent 在前 + 同机会话的 path/worktree basePath
  //   合并去重 + 其余按 localeCompare。machineId 过滤在纯函数内部（null→全部）。
  get directorySuggestions(): string[] {
    return buildDirectorySuggestions(this.selectedMachineId, this.allSessions, this.recentPaths);
  }

  // 统一目录赋值入口：切目录时若 agent=opencode 重拉 model 列表（opencode 的可用模型随 cwd 变）。
  //   codex/cursor 的模型列表只随 machine 变（machine/agent 切换时 refreshModels 已覆盖），此处不重复拉。
  //   注：browser sheet 内手输路径 onSubmit → loadBrowserDir；pickCurrentDir 走此入口赋值。
  private applyDirectory(v: string): void {
    this.directory = v;
    if (this.selectedAgent === 'opencode') { this.refreshModels(); }
  }

  // 当前所选机器显示名（按 selectedMachineId 直查；loading 时「加载中」）
  private machineValueDisplay(): string {
    for (let i = 0; i < this.machines.length; i++) {
      if (this.machines[i].id === this.selectedMachineId) {
        const m: Machine = this.machines[i];
        return m.displayName !== '' ? m.displayName : m.id;
      }
    }
    return this.loadingMachines ? t('common.loading') : t('newSession.selectMachine');
  }
  // 当前所选机器的上次 spawn 错误诊断文案（对照上游 formatRunnerSpawnError；message 空 → ''）。
  //   红字提示，不阻止创建（仅诊断；用户仍可重试）。
  private machineSpawnErrorText(): string {
    for (let i = 0; i < this.machines.length; i++) {
      if (this.machines[i].id === this.selectedMachineId) {
        return formatMachineSpawnError(this.machines[i].lastSpawnErrorMessage, this.machines[i].lastSpawnErrorAt);
      }
    }
    return '';
  }

  // —— Model 列表（「默认」=auto + claude/gemini 静态预设 + codex/cursor/opencode 动态拉取，按 id 去重）——
  //   codex/cursor/opencode 的 live model 列表经 refreshModels() 从 Hub 拉；claude/gemini/kimi 走静态预设。
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
  // model 行右侧显示文本：按 selectedModel 在 modelEntries() 查 label；未命中回落「默认」。
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
  //   opencode：依赖 cwd，directory 空 → 跳过；非空 → getMachineOpencodeModels(machineId, cwd)。
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

  // 推理努力可选域（仅 codex/opencode；''=默认省略）：首项 ''（默认）+ reasoningEffortsForFlavor(agent)。
  private reasoningEffortValues(): string[] {
    const base: string[] = reasoningEffortsForFlavor(this.selectedAgent);
    const out: string[] = [''];
    for (let i = 0; i < base.length; i++) { out.push(base[i]); }
    return out;
  }

  // —— 通用 picker sheet（6 个选择字段共用）——
  //   openPicker 先设 mode 后开（bindSheet builder 首帧读到正确 mode）。
  private openPicker(mode: PickerMode): void {
    this.pickerMode = mode;
    this.pickerOpen = true;
  }
  private pickerTitle(): string {
    if (this.pickerMode === 'machine') { return t('newSession.machine'); }
    if (this.pickerMode === 'agent') { return t('newSession.agent'); }
    if (this.pickerMode === 'model') { return t('newSession.model'); }
    if (this.pickerMode === 'effort') { return t('newSession.effort'); }
    if (this.pickerMode === 'reasoning') { return t('sessionConfig.reasoningEffort'); }
    return t('newSession.type');   // sessionType
  }
  // 按 pickerMode 产选项（label+value）。⚠️ ArkTS 严格：每项用 const:PickerEntry 承接，禁裸字面量 push。
  private pickerEntries(): PickerEntry[] {
    const out: PickerEntry[] = [];
    if (this.pickerMode === 'machine') {
      for (let i = 0; i < this.machines.length; i++) {
        const m: Machine = this.machines[i];
        const e: PickerEntry = { label: m.displayName !== '' ? m.displayName : m.id, value: m.id };
        out.push(e);
      }
    } else if (this.pickerMode === 'agent') {
      for (let i = 0; i < AGENT_FLAVORS.length; i++) {
        const f: string = AGENT_FLAVORS[i];
        const e: PickerEntry = { label: agentDisplayName(f), value: f };
        out.push(e);
      }
    } else if (this.pickerMode === 'model') {
      const entries: ModelOption[] = this.modelEntries();
      for (let i = 0; i < entries.length; i++) {
        const e: PickerEntry = { label: entries[i].label, value: entries[i].id };
        out.push(e);
      }
    } else if (this.pickerMode === 'effort') {
      for (let i = 0; i < EFFORT_OPTIONS.length; i++) {
        const v: string = EFFORT_OPTIONS[i];
        const e: PickerEntry = { label: effortDisplayName(v), value: v };
        out.push(e);
      }
    } else if (this.pickerMode === 'reasoning') {
      const vals: string[] = this.reasoningEffortValues();
      for (let i = 0; i < vals.length; i++) {
        const v: string = vals[i];
        const e: PickerEntry = { label: v === '' ? t('newSession.model.default') : reasoningEffortDisplayName(v), value: v };
        out.push(e);
      }
    } else {   // sessionType
      for (let i = 0; i < SESSION_TYPES.length; i++) {
        const v: string = SESSION_TYPES[i];
        const e: PickerEntry = { label: sessionTypeDisplayName(v), value: v };
        out.push(e);
      }
    }
    return out;
  }
  private pickerSelectedValue(): string {
    if (this.pickerMode === 'machine') { return this.selectedMachineId; }
    if (this.pickerMode === 'agent') { return this.selectedAgent; }
    if (this.pickerMode === 'model') { return this.selectedModel; }
    if (this.pickerMode === 'effort') { return this.selectedEffort; }
    if (this.pickerMode === 'reasoning') { return this.selectedReasoningEffort; }
    return this.selectedSessionType;
  }
  // picker 选中分发 → apply*（by-value 唯一入口，杜绝逻辑分叉），末尾关 sheet（onDisappear 亦兜底）。
  private onPickerPick(value: string): void {
    if (this.pickerMode === 'machine') { this.applyMachineId(value); }
    else if (this.pickerMode === 'agent') { this.applyAgent(value); }
    else if (this.pickerMode === 'model') { this.applyModel(value); }
    else if (this.pickerMode === 'effort') { this.applyEffort(value); }
    else if (this.pickerMode === 'reasoning') { this.applyReasoning(value); }
    else { this.applySessionType(value); }
    this.pickerOpen = false;
  }

  // —— apply*（by-value：值域校验替 index 越界守卫，更鲁棒；保留原联动序）——
  private applyMachineId(id: string): void {
    let found: boolean = false;
    for (let i = 0; i < this.machines.length; i++) {
      if (this.machines[i].id === id) { found = true; break; }
    }
    if (!found) { return; }                        // 防 picker 给过期 id（machines 刷新过）
    this.selectedMachineId = id;
    this.directory = '';                           // 切 machine 清目录（不同机器路径不通用）
    this.recentPaths = [];
    this.loadRecentFor(id);                        // 预填目录（空时）+ opencode 另由 applyDirectory 再 refreshModels
    this.refreshModels();                          // machine 变 → 重拉 codex/cursor/opencode 模型列表
  }
  private applyAgent(flavor: string): void {
    let found: boolean = false;
    for (let i = 0; i < AGENT_FLAVORS.length; i++) {
      if (AGENT_FLAVORS[i] === flavor) { found = true; break; }
    }
    if (!found) { return; }
    this.selectedAgent = flavor;
    // 切 agent 重置 model/effort/reasoning（对照上游 index.tsx:73-77，不同 agent 的模型/努力域不同）
    this.selectedModel = 'auto';
    this.selectedEffort = 'auto';
    this.selectedReasoningEffort = '';
    this.refreshModels();                          // 先 set agent 再 refresh（refreshModels 读 selectedAgent）
  }
  private applyModel(value: string): void {
    this.selectedModel = value;                    // 原亦无副作用；'auto' 必在列表
  }
  private applyEffort(value: string): void {
    for (let i = 0; i < EFFORT_OPTIONS.length; i++) {
      if (EFFORT_OPTIONS[i] === value) { this.selectedEffort = value; return; }
    }
  }
  private applyReasoning(value: string): void {
    const vals: string[] = this.reasoningEffortValues();   // 含首项 ''
    for (let i = 0; i < vals.length; i++) {
      if (vals[i] === value) { this.selectedReasoningEffort = value; return; }
    }
  }
  private applySessionType(value: string): void {
    if (value !== 'simple' && value !== 'worktree') { return; }
    this.selectedSessionType = value;
    if (value !== 'worktree') { this.worktreeName = ''; }   // 非 worktree 清名
  }

  // picker sheet 视觉配置：半屏起 [MEDIUM,LARGE] + 白身(c.bg) + 毛玻璃 + 无把手/无系统关闭
  //   （关闭走 SheetDialog 标题栏 ✕）。复用 buildSheetOptions，与设置页/目录浏览器同款 chrome。
  private get pickerSheetOpts(): SheetOptions {
    const ov: SheetOverrides = {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      onDisappear: () => { this.pickerOpen = false; }
    };
    return buildSheetOptions(this.c.bg, ov);
  }
  // 目录浏览器 sheet 视觉配置：MEDIUM/LARGE 双档。
  private get browserSheetOpts(): SheetOptions {
    const ov: SheetOverrides = {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      onDisappear: () => { this.browserVisible = false; }
    };
    return buildSheetOptions(this.c.bg, ov);
  }

  // —— 目录树浏览 ——
  private openBrowser(): void {
    if (this.selectedMachineId === '') {
      showToast(t('newSession.pleaseSelectMachineFirst'));
      return;
    }
    const startPath: string = this.directory.trim() !== '' ? this.directory.trim() : '/';
    this.browserPathInput = startPath;             // 同步手输 draft
    this.browserVisible = true;
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
      this.browserPathInput = path;                // 导航后 draft 跟随
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
    const p: string = this.browserPathInput.trim();   // 用 draft（含手输未加载的路径），保留手输即用
    if (p !== '') { this.applyDirectory(p); }         // 走统一入口：opencode 随新 cwd 重拉 model 列表
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

  // 目录树行（folder/doc 图标 + git 徽章；目录树专属，不用 SettingCard）
  @Builder
  private BrowserEntryRow(entry: DirEntry) {
    Row({ space: 10 }) {
      SymbolGlyph(entry.type === 'directory' ? $r('sys.symbol.folder') : $r('sys.symbol.doc'))
        .fontSize(fs(16))
        .fontColor([entry.type === 'directory' ? this.c.textPrimary : this.c.textTertiary])
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

  // 通用 picker sheet（6 选择字段共用）：SheetDialog 固定标题栏（白头 + ✕，不随滚动消失，留出顶部高度）
  //   + 白身滚动区 + 胶囊选项行（左 radio 圆点 + 文字，r12/h48，选中 primary 半透明底）。半屏 [MEDIUM,LARGE]。
  //   ⚠️ 第二轮反馈修复：先前误删 SheetDialog 致顶部只剩原生细把手 → 顶栏过窄；恢复固定标题栏。
  @Builder
  private PickerSheet() {
    Column() {
      SheetDialog({
        title: this.pickerTitle(),
        showCloseButton: true,
        onClose: () => { this.pickerOpen = false; }
      })
      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.pickerEntries(), (e: PickerEntry) => {
            this.PickerOptionRow(e.label, e.value, this.pickerSelectedValue())
          }, (e: PickerEntry) => e.value)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }
  // 胶囊选项行（对照 SessionConfigOverlay.optionRow：左 circle/circle_fill + 文字。
  //   选中→primary 半透明底 + primary 字 + Medium + 实心圆；未选→灰底(surface) 浮白身 + 主文字 + 空心圆。
  //   ⚠️ 行底用 c.surface 而非 c.bg：sheet 白身已是 c.bg，灰胶囊才看得见（对照 SessionConfigOverlay 灰胶囊浮白身的镜像）。
  @Builder
  private PickerOptionRow(label: string, value: string, current: string) {
    Row({ space: 10 }) {
      SymbolGlyph(value === current ? $r('sys.symbol.circle_fill') : $r('sys.symbol.circle'))
        .fontSize(fs(15))
        .fontColor([value === current ? this.c.primary : this.c.textTertiary])
        .width(20)
      Text(label)
        .fontSize(fs(15))
        .fontWeight(value === current ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(value === current ? this.c.primary : this.c.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height(48)
    .padding({ left: 14, right: 14 })
    .borderRadius(12)
    .backgroundColor(value === current ? this.selectedBg() : this.c.surface)
    .onClick(() => { this.onPickerPick(value); })
  }

  // 目录浏览半模态弹层（SheetDialog 标题栏 + 路径行 + 手输框 + 列表 + 选择此目录）
  @Builder
  private DirectoryBrowser() {
    Column() {
      SheetDialog({
        title: t('newSession.chooseFolderTitle'),
        showCloseButton: true,
        onClose: () => { this.browserVisible = false; }
      })

      // 当前路径 + 回上级
      Row() {
        Button(t('newSession.parentDir'))
          .fontSize(fs(13))
          .height(32)
          .backgroundColor(this.c.surfaceSelected)
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

      // 手输/粘贴路径（保留手输能力；onSubmit 加载该路径）
      TextInput({ text: this.browserPathInput, placeholder: t('newSession.manualPathPlaceholder') })
        .fontSize(fs(13))
        .backgroundColor(this.c.surface)
        .borderRadius(10)
        .height(40)
        .margin({ left: 16, right: 16, bottom: 4 })
        .onChange((value: string) => { this.browserPathInput = value; })
        .onSubmit((enterKey: EnterKeyType) => { this.loadBrowserDir(this.browserPathInput.trim()); })

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
  }

  build() {
    NavDestination() {
      Stack() {
      // 机器拉取失败兜底（无机器则无法继续）—— berry3 卡片风：单张 danger 白卡 + 重试胶囊，与主表单同款 List 结构。
      if (this.loadError !== '' && this.machines.length === 0) {
        List({ space: 12 }) {
          ListItemGroup() {
            ListItem() {
              SettingCard({
                primaryText: t('newSession.loadFailed'),
                secondaryText: this.loadError,
                suffixType: 'none', isDanger: true, clickable: false, rowPosition: 'single'
              })
            }
          }
          .backgroundColor(this.c.bg)
          .borderRadius($r('app.float.setting_card_radius'))
          .clip(true)

          ListItem() {
            SettingActionButton({
              label: t('common.retry'),
              style: 'primary',
              onPress: () => { this.loadMachines(); }
            })
          }.selectable(false)

          ListItem() { Row().height(24) }.selectable(false)
        }
        .scrollBar(BarState.Off)
        .padding({
          top: 12, bottom: 0,
          left: $r('sys.float.padding_level8'), right: $r('sys.float.padding_level8')
        })
      } else {
        List({ space: 12 }) {
          // —— 分组 1：环境（机器 + Agent）——
          ListItem() {
            SettingSectionTitle({ text: t('newSession.sectionEnvironment') })
          }.selectable(false)
          ListItemGroup() {
            ListItem() {
              SettingCard({
                primaryText: t('newSession.machine'),
                suffixText: this.machineValueDisplay(),
                suffixType: 'textAndArrow',
                rowPosition: 'first',
                isEnabled: this.machines.length > 0,
                onItemClick: () => { this.openPicker('machine'); }
              })
            }
            ListItem() {
              SettingCard({
                primaryText: t('newSession.agent'),
                suffixText: agentDisplayName(this.selectedAgent),
                suffixType: 'textAndArrow',
                rowPosition: 'last',
                onItemClick: () => { this.openPicker('agent'); }
              })
            }
          }
          .divider({
            strokeWidth: $r('app.float.setting_divider_width'), color: this.c.border,
            startMargin: $r('app.float.setting_card_padding_h'), endMargin: $r('app.float.setting_card_padding_h')
          })
          .backgroundColor(this.c.bg)
          .borderRadius($r('app.float.setting_card_radius'))
          .clip(true)

          // 该机器上次 spawn 错误诊断（Hub runnerState.lastSpawnError；非空才显示，独立 danger 只读卡）
          if (this.machineSpawnErrorText() !== '') {
            ListItem() {
              SettingCard({
                primaryText: t('newSession.machine'),
                secondaryText: this.machineSpawnErrorText(),
                suffixType: 'none', isDanger: true, clickable: false, rowPosition: 'single'
              })
            }
          }

          // —— 分组 2：工作目录（当前目录行 + 建议列表）——
          ListItem() {
            SettingSectionTitle({ text: t('newSession.directory') })
          }.selectable(false)
          ListItemGroup() {
            ListItem() {
              SettingCard({
                primaryText: this.directory !== '' ? this.directory : t('newSession.chooseFolder'),
                suffixType: 'arrow',
                rowPosition: this.directorySuggestions.length === 0 ? 'single' : 'first',
                onItemClick: () => { this.openBrowser(); }
              })
            }
            ForEach(this.directorySuggestions, (path: string, idx: number) => {
              ListItem() {
                SettingCard({
                  primaryText: path,
                  suffixType: 'check',
                  isChecked: path === this.directory,
                  rowPosition: rowPos(idx + 1, this.directorySuggestions.length + 1),
                  onItemClick: () => { this.applyDirectory(path); }
                })
              }
            }, (path: string) => path)
          }
          .divider({
            strokeWidth: $r('app.float.setting_divider_width'), color: this.c.border,
            startMargin: $r('app.float.setting_card_padding_h'), endMargin: $r('app.float.setting_card_padding_h')
          })
          .backgroundColor(this.c.bg)
          .borderRadius($r('app.float.setting_card_radius'))
          .clip(true)

          // —— 分组 3：模型（model + 条件 effort[claude] / reasoning[codex·opencode]）——
          ListItem() {
            SettingSectionTitle({ text: t('newSession.model') })
          }.selectable(false)
          ListItemGroup() {
            ListItem() {
              SettingCard({
                primaryText: t('newSession.model'),
                suffixText: this.modelValueDisplay(),
                suffixType: 'textAndArrow',
                rowPosition: (this.selectedAgent === 'claude' || this.selectedAgent === 'codex' || this.selectedAgent === 'opencode') ? 'first' : 'single',
                onItemClick: () => { this.openPicker('model'); }
              })
            }
            if (this.selectedAgent === 'claude') {
              ListItem() {
                SettingCard({
                  primaryText: t('newSession.effort'),
                  suffixText: effortDisplayName(this.selectedEffort),
                  suffixType: 'textAndArrow',
                  rowPosition: 'last',
                  onItemClick: () => { this.openPicker('effort'); }
                })
              }
            }
            if (this.selectedAgent === 'codex' || this.selectedAgent === 'opencode') {
              ListItem() {
                SettingCard({
                  primaryText: t('sessionConfig.reasoningEffort'),
                  suffixText: this.selectedReasoningEffort === '' ? t('newSession.model.default') : reasoningEffortDisplayName(this.selectedReasoningEffort),
                  suffixType: 'textAndArrow',
                  rowPosition: 'last',
                  onItemClick: () => { this.openPicker('reasoning'); }
                })
              }
            }
          }
          .divider({
            strokeWidth: $r('app.float.setting_divider_width'), color: this.c.border,
            startMargin: $r('app.float.setting_card_padding_h'), endMargin: $r('app.float.setting_card_padding_h')
          })
          .backgroundColor(this.c.bg)
          .borderRadius($r('app.float.setting_card_radius'))
          .clip(true)

          // —— 分组 4：会话选项（会话类型 + worktree 名 + Yolo）——
          ListItem() {
            SettingSectionTitle({ text: t('newSession.options') })
          }.selectable(false)
          ListItemGroup() {
            ListItem() {
              SettingCard({
                primaryText: t('newSession.type'),
                suffixText: sessionTypeDisplayName(this.selectedSessionType),
                suffixType: 'textAndArrow',
                rowPosition: 'first',
                onItemClick: () => { this.openPicker('sessionType'); }
              })
            }
            // 工作树自定义名（worktree 时显示；留空则服务端自动生成）
            if (this.selectedSessionType === 'worktree') {
              ListItem() {
                Row() {
                  TextInput({ text: this.worktreeName, placeholder: t('newSession.worktreeNamePlaceholder') })
                    .fontSize(fs(14))
                    .backgroundColor(this.c.surface)
                    .borderRadius(10)
                    .height(44)
                    .onChange((value: string) => { this.worktreeName = value; })
                }
                .width('100%')
                .padding({
                  left: $r('app.float.setting_card_padding_h'), right: $r('app.float.setting_card_padding_h'),
                  top: $r('app.float.setting_card_padding_v'), bottom: $r('app.float.setting_card_padding_v')
                })
                .borderRadius(resolveRowRadius('middle'))
              }
            }
            ListItem() {
              SettingCard({
                primaryText: t('newSession.yolo'),
                secondaryText: t('newSession.yoloDesc'),
                suffixType: 'switch',
                switchIsOn: this.yolo,
                onSwitchChange: (on: boolean) => { this.yolo = on; },
                rowPosition: 'last'
              })
            }
          }
          .divider({
            strokeWidth: $r('app.float.setting_divider_width'), color: this.c.border,
            startMargin: $r('app.float.setting_card_padding_h'), endMargin: $r('app.float.setting_card_padding_h')
          })
          .backgroundColor(this.c.bg)
          .borderRadius($r('app.float.setting_card_radius'))
          .clip(true)

          // 错误提示（spawn 校验/spawn 失败）
          if (this.spawnError !== '') {
            ListItem() {
              Text(this.spawnError)
                .fontSize(fs(12))
                .fontColor(this.c.error)
                .width('100%')
                .padding({ left: $r('app.float.setting_card_padding_h'), top: 4, bottom: 4 })
            }.selectable(false)
          }

          // 创建按钮
          ListItem() {
            SettingActionButton({
              label: this.isSpawning ? t('newSession.creating') : t('newSession.create'),
              style: 'primary',
              isEnabled: !this.isSpawning && this.machines.length > 0,
              onPress: () => { this.createSession(); }
            })
          }.selectable(false)

          ListItem() { Row().height(24) }.selectable(false)
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .padding({
          top: 12, bottom: 0,
          left: $r('sys.float.padding_level8'), right: $r('sys.float.padding_level8')
        })
      }
      // picker / 目录浏览器 sheet 各挂独立 0×0 锚点节点（同节点叠多 bindSheet 仅一个生效 → 必须分流，对照 memory「bindSheet 两坑」）
      Column() {}.width(0).height(0)
        .bindSheet(this.pickerOpen!!, this.PickerSheet(), this.pickerSheetOpts)
      Column() {}.width(0).height(0)
        .bindSheet(this.browserVisible!!, this.DirectoryBrowser(), this.browserSheetOpts)
      }
      .width('100%')
      .height('100%')
    }
    .title(t('newSession.title'))
    .backgroundColor(this.c.surface)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack;
    })
  }
}

// 系统路由表 buildFunction（router_map.json 引用）
@Builder
export function NewSessionPageBuilder(name: string, param: Object) {
  NewSessionPage({ routeParamsSeed: param as NewSessionPageRouteParams })
}
