export interface YoloDetection {
  label: string;
  score: number;
  x: number;
  y: number;
  width: number;
  height: number;
}
export const init: (resourceManagerOrBuffer: Object, modelName?: string) => void;
export const detect: (imageData: ArrayBuffer, width: number, height: number) => Promise<Array<YoloDetection>>;
