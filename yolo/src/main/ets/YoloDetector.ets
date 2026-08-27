import yoloNative from 'libyolo.so';
import { DetectionResult } from './DetectionResult';

const RAW_MODEL_NAME: string = 'yolov8n.ms';

export class YoloDetector {
  static init(resourceManager: Object): void {
    yoloNative.init(resourceManager, RAW_MODEL_NAME);
  }

  static detect(imageData: ArrayBuffer, width: number, height: number): Promise<Array<DetectionResult>> {
    return yoloNative.detect(imageData, width, height) as Promise<Array<DetectionResult>>;
  }
}
