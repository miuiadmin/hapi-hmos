import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

// Preferences 文件名
const PREFERENCES_NAME: string = 'hapi_preferences';

// Preferences 单例封装（对照 chatcube PreferencesService）
// 初始化必须在 loadContent 之前完成（EntryAbility.onWindowStageCreate 里 await）
export class PreferencesService {
  private static instance: PreferencesService | null = null;
  private dataPreferences: preferences.Preferences | null = null;
  private isInitialized: boolean = false;

  private constructor() {}

  static getInstance(): PreferencesService {
    if (PreferencesService.instance === null) {
      PreferencesService.instance = new PreferencesService();
    }
    return PreferencesService.instance;
  }

  async initialize(context: common.Context): Promise<void> {
    this.dataPreferences = await preferences.getPreferences(context, PREFERENCES_NAME);
    this.isInitialized = true;
  }

  private checkReady(): void {
    if (!this.isInitialized || this.dataPreferences === null) {
      throw new Error('PreferencesService not initialized; call initialize() in EntryAbility first');
    }
  }

  async getString(key: string, defaultValue: string = ''): Promise<string> {
    this.checkReady();
    const val = await this.dataPreferences!.get(key, defaultValue);
    return val as string;
  }

  async getBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
    this.checkReady();
    const val = await this.dataPreferences!.get(key, defaultValue);
    return val as boolean;
  }

  async putString(key: string, value: string): Promise<void> {
    this.checkReady();
    await this.dataPreferences!.put(key, value);
    await this.dataPreferences!.flush();
  }

  async putBoolean(key: string, value: boolean): Promise<void> {
    this.checkReady();
    await this.dataPreferences!.put(key, value);
    await this.dataPreferences!.flush();
  }

  async delete(key: string): Promise<void> {
    this.checkReady();
    await this.dataPreferences!.delete(key);
    await this.dataPreferences!.flush();
  }
}

// 全局便捷访问
export function getPreferencesService(): PreferencesService {
  return PreferencesService.getInstance();
}
