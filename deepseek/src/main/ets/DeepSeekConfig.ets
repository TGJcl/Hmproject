import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { getLogger } from 'logger';

const STORE_NAME: string = 'deepseek_config';
const KEY_API_KEY: string = 'api_key';
const LOG = getLogger('DeepSeekConfig');

export class DeepSeekConfig {
  static async getApiKey(context: common.Context): Promise<string> {
    const store = await preferences.getPreferences(context, STORE_NAME);
    const value = store.getSync(KEY_API_KEY, '') as string;
    return value;
  }

  static async hasApiKey(context: common.Context): Promise<boolean> {
    const key: string = await DeepSeekConfig.getApiKey(context);
    return key !== '';
  }

  static async setApiKey(context: common.Context, apiKey: string): Promise<void> {
    const store = await preferences.getPreferences(context, STORE_NAME);
    await store.put(KEY_API_KEY, apiKey);
    await store.flush();
    LOG.info('api key saved');
  }
}
