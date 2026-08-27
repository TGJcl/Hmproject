import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { DatabaseManager } from 'database';
import { ImageLoader } from 'image';
import { NetworkClient } from 'network';
import { getLogger } from 'logger';
import { HealthSummary } from '../model/HealthSummary';

const REMOTE_API_URL: string = 'https://example.com/api/health';
const SAMPLE_RAW_IMAGE: string = 'sample_image.png';
const LOG = getLogger('HealthService');

export class HealthService {
  static async init(context: common.Context): Promise<void> {
    LOG.info('init begin');
    await DatabaseManager.init(context);
    LOG.info('init end');
  }

  static async insertSample(value: number): Promise<void> {
    LOG.info('insert sample, value=%{public}d', value);
    await DatabaseManager.insertRecord(value);
  }

  static async loadSummary(): Promise<HealthSummary> {
    LOG.debug('load summary begin');
    const summary = new HealthSummary();
    summary.latestValue = await DatabaseManager.queryLatestValue();
    summary.recordCount = await DatabaseManager.queryRecordCount();
    summary.score = summary.latestValue;
    LOG.info('load summary end, score=%{public}d, records=%{public}d', summary.score, summary.recordCount);
    return summary;
  }

  static async fetchRemoteData(): Promise<string> {
    LOG.info('fetch remote data, url=%{public}s', REMOTE_API_URL);
    return NetworkClient.get(REMOTE_API_URL);
  }

  static async loadSampleImage(context: common.Context): Promise<image.PixelMap> {
    LOG.info('load sample image, file=%{public}s', SAMPLE_RAW_IMAGE);
    return ImageLoader.loadPixelMapFromRawFile(context, SAMPLE_RAW_IMAGE);
  }
}
