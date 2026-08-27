import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { EmbeddingManager } from 'embedding';
import { VectorDatabase } from 'vector';
import { DeepSeekClient, DeepSeekConfig, DeepSeekMessage } from 'deepseek';
import { getLogger } from 'logger';

const RAG_TOP_K: number = 3;
const NO_MEMORY: string = '（暂无相关记忆）';
const PROMPT_RAW_PATH: string = 'prompts/system_prompt.md';
const SYSTEM_PROMPT: string =
  '你是“健康助手”，一个运行在用户本机（鸿蒙应用）里的 AI 助手。' +
  '请基于下面提供的“记忆片段”（来自用户健康档案的向量检索结果）回答用户问题；' +
  '如果记忆片段中没有相关信息，就如实说明，不要编造。回答简洁、口语化。';
const LOG = getLogger('AiChatService');

export class AiChatService {
  private static systemPrompt: string = SYSTEM_PROMPT;
  private static promptLoaded: boolean = false;

  static async chat(context: common.Context, question: string): Promise<string> {
    await AiChatService.ensurePrompt(context);
    const apiKey: string = await DeepSeekConfig.getApiKey(context);
    if (apiKey === '') {
      throw new Error('DeepSeek API key not configured');
    }
    await VectorDatabase.init(context);

    // RAG：把问题向量化，从记忆库检索最相关的片段
    const queryVector: Array<number> = await EmbeddingManager.embed(question);
    const records = await VectorDatabase.search(queryVector, RAG_TOP_K);
    let memoryText: string = NO_MEMORY;
    if (records.length > 0) {
      memoryText = records.map((record) => '- ' + record.content).join('\n');
    }
    LOG.info('rag hits=%{public}d, question=%{public}s', records.length, question);

    const messages: Array<DeepSeekMessage> = [
      { role: 'system', content: AiChatService.systemPrompt },
      { role: 'user', content: '记忆片段：\n' + memoryText + '\n\n用户问题：' + question }
    ];
    return DeepSeekClient.chat(apiKey, messages);
  }

  private static async ensurePrompt(context: common.Context): Promise<void> {
    if (AiChatService.promptLoaded) {
      return;
    }
    try {
      const raw: Uint8Array = await context.resourceManager.getRawFileContent(PROMPT_RAW_PATH);
      const text: string = util.TextDecoder.create('utf-8').decodeToString(raw);
      if (text.trim().length > 0) {
        AiChatService.systemPrompt = text.trim();
        LOG.info('system prompt loaded from rawfile');
      }
    } catch (e) {
      LOG.warn('load system prompt failed, use built-in: %{public}s', (e as Error).message);
    }
    AiChatService.promptLoaded = true;
  }
}
