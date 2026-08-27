import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { DatabaseManager } from 'database';
import { ImageLoader } from 'image';
import { NetworkClient } from 'network';
import { HealthSummary } from '../model/HealthSummary';

const REMOTE_API_URL: string = 'https://example.com/api/health';
const SAMPLE_RAW_IMAGE: string = 'sample_image.png';

export class HealthService {
  static async init(context: common.Context): Promise<void> {
    await DatabaseManager.init(context);
  }

  static async insertSample(value: number): Promise<void> {
    await DatabaseManager.insertRecord(value);
  }

  static async loadSummary(): Promise<HealthSummary> {
    const summary = new HealthSummary();
    summary.latestValue = await DatabaseManager.queryLatestValue();
    summary.recordCount = await DatabaseManager.queryRecordCount();
    summary.score = summary.latestValue;
    return summary;
  }

  static async fetchRemoteData(): Promise<string> {
    return NetworkClient.get(REMOTE_API_URL);
  }

  static async loadSampleImage(context: common.Context): Promise<image.PixelMap> {
    return ImageLoader.loadPixelMapFromRawFile(context, SAMPLE_RAW_IMAGE);
  }
}
