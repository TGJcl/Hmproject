import { common } from '@kit.AbilityKit';
import { VectorDatabase } from 'vector';
import { getLogger } from 'logger';
import { HealthProfile } from '../model/HealthProfile';
import { KnowledgeService } from './KnowledgeService';
import { ModelWorkerService } from './ModelWorkerService';

const MEMORY_TYPE: string = 'health_profile';
const TOP_K: number = 3;
const LOG = getLogger('MemoryService');

export class MemoryService {
  static async init(context: common.Context): Promise<void> {
    await VectorDatabase.init(context);
    await ModelWorkerService.init(context);
    await KnowledgeService.importGuidelines(context);
    LOG.info('init end');
  }

  static async saveHealthProfile(profile: HealthProfile): Promise<number> {
    const text: string = profile.toMemoryText();
    const vector: Array<number> = await ModelWorkerService.embed(text);
    LOG.info('save health profile, text=%{public}s', text);
    return VectorDatabase.add(text, vector, MEMORY_TYPE);
  }

  static async searchRelated(query: string): Promise<Array<string>> {
    const vector: Array<number> = await ModelWorkerService.embed(query);
    const records = await VectorDatabase.search(vector, TOP_K);
    return records.map((record) => record.content);
  }
}