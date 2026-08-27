export interface YoloDetection {
  label: string;
  score: number;
  x: number;
  y: number;
  width: number;
  height: number;
}
export const init: (resourceManager: Object, modelName: string) => void;
export const initFromBuffer: (buffer: ArrayBuffer) => void;
export const detect: (imageData: ArrayBuffer, width: number, height: number) => Promise<Array<YoloDetection>>;
