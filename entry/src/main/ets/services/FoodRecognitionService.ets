import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { DetectionResult, YoloDetector } from 'yolo';
import { getLogger } from 'logger';

const FOOD_LABELS: Array<string> = ['banana', 'apple', 'sandwich', 'orange', 'broccoli', 'carrot', 'hot dog', 'pizza', 'donut', 'cake'];
const LOG = getLogger('FoodRecognitionService');

export class FoodRecognitionService {
  private static initialized: boolean = false;

  /**
   * 识别图片中的食物，返回带置信度的标签列表（如 “banana（87%）”）；失败返回空数组。
   */
  static async detectFood(context: common.Context, pixelMap: image.PixelMap): Promise<Array<string>> {
    try {
      if (!FoodRecognitionService.initialized) {
        YoloDetector.init(context.resourceManager);
        FoodRecognitionService.initialized = true;
        LOG.info('yolo detector initialized');
      }
      const buffer: ArrayBuffer = new ArrayBuffer(pixelMap.getPixelBytesNumber());
      await pixelMap.readPixelsToBuffer(buffer);
      const info = pixelMap.getImageInfoSync();
      const detections: Array<DetectionResult> = await YoloDetector.detect(buffer, info.size.width, info.size.height);
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