import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { EmbeddingManager } from 'embedding';
import { VectorDatabase } from 'vector';
import { getLogger } from 'logger';

const KNOWLEDGE_RAW_PATH: string = 'knowledge/un_dietary_guidelines.json';
const KNOWLEDGE_SOURCE: string = 'un_dietary_guidelines';
const LOG = getLogger('KnowledgeService');

interface KnowledgeChunk {
  id: string;
  category: string;
  title: string;
  content: string;
}

interface KnowledgeDoc {
  source: string;
  reference: string;
  updated: string;
  chunks: Array<KnowledgeChunk>;
}

export class KnowledgeService {
  /**
   * 导入联合国膳食营养指南到本地向量库，按 id 去重，可重复调用。
   */
  static async importGuidelines(context: common.Context): Promise<void> {
    try {
      const raw: Uint8Array = await context.resourceManager.getRawFileContent(KNOWLEDGE_RAW_PATH);
      const text: string = util.TextDecoder.create('utf-8').decodeToString(raw);
      const doc: KnowledgeDoc = JSON.parse(text) as KnowledgeDoc;
      let imported: number = 0;
      for (const chunk of doc.chunks) {
        const metadata: string = JSON.stringify({
          'source': KNOWLEDGE_SOURCE,
          'id': chunk.id,
          'title': chunk.title,
          'category': chunk.category
        });
        if (await VectorDatabase.existsByMetadata(metadata)) {
          continue;
        }
        const vector: Array<number> = await EmbeddingManager.embed(chunk.content);
        await VectorDatabase.add(chunk.content, vector, metadata);
        imported++;
      }
      LOG.info('guidelines imported, chunks=%{public}d new=%{public}d',
        doc.chunks.length, imported);
    } catch (e) {
      LOG.warn('import guidelines failed: %{public}s', (e as Error).message);
    }
  }
}