import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { DetectionResult } from 'yolo';
import { ModelWorkerService } from './ModelWorkerService';
import { getLogger } from 'logger';

const FOOD_LABELS: Array<string> = ['banana', 'apple', 'sandwich', 'orange', 'broccoli', 'carrot', 'hot dog', 'pizza', 'donut', 'cake'];
const LOG = getLogger('FoodRecognitionService');

export class FoodRecognitionService {
  /**
   * 识别图片中的食物（推理在 Worker 线程），返回带置信度的标签列表；失败返回空数组。
   */
  static async detectFood(context: common.Context, pixelMap: image.PixelMap): Promise<Array<string>> {
    try {
      const buffer: ArrayBuffer = new ArrayBuffer(pixelMap.getPixelBytesNumber());
      await pixelMap.readPixelsToBuffer(buffer);
      const info = pixelMap.getImageInfoSync();
      const detections: Array<DetectionResult> = await ModelWorkerService.detect(context, buffer,
        info.size.width, info.size.height);
      const labels: Array<string> = [];
      for (const d of detections) {
        if (FOOD_LABELS.includes(d.label) && !labels.includes(d.label)) {
          const score: number = Math.round(d.score * 100);
          labels.push(d.label + '（' + score.toString() + '%）');
          LOG.info('food detected: %{public}s %{public}d%%', d.label, score);
        }
      }
      return labels;
    } catch (e) {
      LOG.warn('food detect failed: %{public}s', (e as Error).message);
      return [];
    }
  }
}