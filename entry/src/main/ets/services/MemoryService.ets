import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { EmbeddingManager, NativeEmbedding } from 'embedding';
import { VectorDatabase } from 'vector';
import { getLogger } from 'logger';
import { HealthProfile } from '../model/HealthProfile';
import { KnowledgeService } from './KnowledgeService';

const MEMORY_TYPE: string = 'health_profile';
const TOP_K: number = 3;
const MODEL_FILE_NAME: string = 'jina-embeddings-v2-base-zh-static.ms';
const TOKENIZER_FILE_NAME: string = 'tokenizer.json';
const LOG = getLogger('MemoryService');

export class MemoryService {
  static async init(context: common.Context): Promise<void> {
    await VectorDatabase.init(context);
    MemoryService.tryEnableNativeEmbedding(context);
    await KnowledgeService.importGuidelines(context);
    LOG.info('init end');
  }

  static async saveHealthProfile(profile: HealthProfile): Promise<number> {
    const text: string = profile.toMemoryText();
    const vector: Array<number> = await EmbeddingManager.embed(text);
    LOG.info('save health profile, text=%{public}s', text);
    return VectorDatabase.add(text, vector, MEMORY_TYPE);
  }

  static async searchRelated(query: string): Promise<Array<string>> {
    const vector: Array<number> = await EmbeddingManager.embed(query);
    const records = await VectorDatabase.search(vector, TOP_K);
    return records.map((record) => record.content);
  }

  private static tryEnableNativeEmbedding(context: common.Context): void {
    const filesDir: string = context.filesDir;
    const modelPath: string = filesDir + '/models/' + MODEL_FILE_NAME;
    const tokenizerPath: string = filesDir + '/models/' + TOKENIZER_FILE_NAME;
    try {
      if (fileIo.accessSync(modelPath) && fileIo.accessSync(tokenizerPath)) {
        NativeEmbedding.init(modelPath, tokenizerPath);
        EmbeddingManager.setProvider(new NativeEmbedding());
        LOG.info('native embedding enabled');
      } else {
        LOG.warn('embedding model files not found, keep placeholder embedding');
      }
    } catch (e) {
      LOG.warn('enable native embedding failed, keep placeholder embedding');
    }
  }
}