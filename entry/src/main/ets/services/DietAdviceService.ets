import { common } from '@kit.AbilityKit';
import { NetworkClient } from 'network';
import { DeepSeekClient, DeepSeekConfig, DeepSeekMessage } from 'deepseek';
import { EmbeddingManager } from 'embedding';
import { VectorDatabase } from 'vector';
import { getLogger } from 'logger';

const WIKI_API_PREFIX: string =
  'https://zh.wikipedia.org/w/api.php?action=query&prop=extracts&explaintext=1&format=json&redirects=1&titles=';
const SUMMARY_MAX_LEN: number = 300;
const SOURCE_TAG: string = 'web_diet_advice';
const LOG = getLogger('DietAdviceService');

export class DietAdviceService {
  /**
   * 查询指定病症的饮食注意事项（维基百科）并写入本地向量库。
   * 返回用于展示的文本；失败返回空字符串。
   */
  static async queryDietAdviceAndStore(context: common.Context, disease: string): Promise<string> {
    const name: string = disease.trim();
    if (name === '' || name === '无') {
      return '';
    }
    try {
      await VectorDatabase.init(context);
      const url: string = WIKI_API_PREFIX + encodeURIComponent(name);
      const json: string = await NetworkClient.get(url);
      const extract: string = DietAdviceService.parseExtract(json);
      if (extract === '') {
        LOG.warn('no extract for disease=%{public}s', name);
        return '';
      }
      const advice: string = await DietAdviceService.summarize(context, name, extract);
      const vector: Array<number> = await EmbeddingManager.embed(advice);
      const metadata: string = JSON.stringify({
        'source': SOURCE_TAG,
        'disease': name,
        'url': url
      });
      await VectorDatabase.add(advice, vector, metadata);
      LOG.info('diet advice stored, disease=%{public}s, len=%{public}d', name, advice.length);
      return advice;
    } catch (e) {
      LOG.warn('query diet advice failed: %{public}s', (e as Error).message);
      return '';
    }
  }

  private static async summarize(context: common.Context, disease: string, extract: string): Promise<string> {
    const apiKey: string = await DeepSeekConfig.getApiKey(context);
    if (apiKey === '') {
      return DietAdviceService.truncate(extract);
    }
    try {
      const messages: Array<DeepSeekMessage> = [
        {
          role: 'system',
          content: '你是健康饮食顾问。根据提供的资料，总结该病症在饮食上需要注意什么，100-200字，直接输出内容，不要客套。'
        },
        {
          role: 'user',
          content: '病症：' + disease + '\n资料：\n' + DietAdviceService.truncate(extract)
        }
      ];
      const summary: string = await DeepSeekClient.chat(apiKey, messages);
      const trimmed: string = summary.trim();
      return trimmed === '' ? DietAdviceService.truncate(extract) : trimmed;
    } catch (e) {
      LOG.warn('summarize failed, use raw extract: %{public}s', (e as Error).message);
      return DietAdviceService.truncate(extract);
    }
  }

  private static parseExtract(json: string): string {
    const root: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
    const query: Record<string, Object> = root['query'] as Record<string, Object>;
    if (query === undefined) {
      return '';
    }
    const pages: Record<string, Object> = query['pages'] as Record<string, Object>;
    if (pages === undefined) {
      return '';
    }
    const keys: Array<string> = Object.keys(pages);
    for (const key of keys) {
      const page: Record<string, Object> = pages[key] as Record<string, Object>;
      const extract: string = page['extract'] as string;
      if (extract !== undefined && extract !== '') {
        return extract;
      }
    }
    return '';
  }

  private static truncate(text: string): string {
    const cleaned: string = text.replace(/==.*?==/g, '').trim();
    return cleaned.length > SUMMARY_MAX_LEN ? cleaned.substring(0, SUMMARY_MAX_LEN) + '…' : cleaned;
  }
}