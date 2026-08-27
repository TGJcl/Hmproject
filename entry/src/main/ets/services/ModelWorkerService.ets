import { common } from '@kit.AbilityKit';
import { worker, MessageEvents } from '@kit.ArkTS';
import { DetectionResult } from 'yolo';
import { getLogger } from 'logger';

const MODEL_FILE_NAME: string = 'jina-embeddings-v2-base-zh-static.ms';
const TOKENIZER_FILE_NAME: string = 'tokenizer.json';
const YOLO_RAW_MODEL: string = 'yolov8n.ms';
const LOG = getLogger('ModelWorkerService');

interface ModelRequest {
  id: number;
  type: string;
  payload: Object;
}

interface ModelResponse {
  id: number;
  ok: boolean;
  payload: Object;
  error: string;
}

interface PendingEntry {
  resolve: (value: Object) => void;
  reject: (reason: Error) => void;
}

export class ModelWorkerService {
  private static threadWorker: worker.ThreadWorker | undefined = undefined;
  private static nextId: number = 1;
  private static pending: Map<number, PendingEntry> = new Map();
  private static embedInitialized: boolean = false;
  private static yoloInitialized: boolean = false;

  static async init(context: common.Context): Promise<void> {
    if (ModelWorkerService.embedInitialized) {
      return;
    }
    ModelWorkerService.embedInitialized = true;
    const modelPath: string = context.filesDir + '/models/' + MODEL_FILE_NAME;
    const tokenizerPath: string = context.filesDir + '/models/' + TOKENIZER_FILE_NAME;
    const initPayload: Record<string, string> = {
      'modelPath': modelPath,
      'tokenizerPath': tokenizerPath
    };
    await ModelWorkerService.post('embed_init', initPayload);
    LOG.info('embedding worker init requested');
  }

  static async embed(text: string): Promise<Array<number>> {
    const embedPayload: Record<string, string> = { 'text': text };
    const result: Object = await ModelWorkerService.post('embed', embedPayload);
    return result as Array<number>;
  }

  static async detect(context: common.Context, image: ArrayBuffer, width: number, height: number):
    Promise<Array<DetectionResult>> {
    await ModelWorkerService.ensureYolo(context);
    const detectPayload: Record<string, Object> = {
      'image': image,
      'width': width,
      'height': height
    };
    const result: Object = await ModelWorkerService.post('yolo_detect', detectPayload, [image]);
    return result as Array<DetectionResult>;
  }

  private static async ensureYolo(context: common.Context): Promise<void> {
    if (ModelWorkerService.yoloInitialized) {
      return;
    }
    ModelWorkerService.yoloInitialized = true;
    const raw: Uint8Array = await context.resourceManager.getRawFileContent(YOLO_RAW_MODEL);
    const buffer: ArrayBuffer = raw.buffer.slice(raw.byteOffset, raw.byteOffset + raw.byteLength) as ArrayBuffer;
    const yoloPayload: Record<string, Object> = { 'model': buffer };
    await ModelWorkerService.post('yolo_init', yoloPayload, [buffer]);
    LOG.info('yolo worker init requested');
  }

  private static ensureWorker(): worker.ThreadWorker {
    if (ModelWorkerService.threadWorker === undefined) {
      const w: worker.ThreadWorker = new worker.ThreadWorker('entry/ets/workers/ModelWorker');
      w.onmessage = (event: MessageEvents) => {
        const response: ModelResponse = event.data as ModelResponse;
        const entry: PendingEntry | undefined = ModelWorkerService.pending.get(response.id);
        if (entry === undefined) {
          return;
        }
        ModelWorkerService.pending.delete(response.id);
        if (response.ok) {
          entry.resolve(response.payload);
        } else {
          entry.reject(new Error(response.error));
        }
      };
      w.onerror = (event: Object) => {
        const errData: Record<string, Object> = event as Record<string, Object>;
        const message: string = (errData['message'] as string) ?? 'model worker error';
        LOG.warn('model worker error: %{public}s', message);
        const keys: Array<number> = Array.from(ModelWorkerService.pending.keys());
        for (const key of keys) {
          const entry = ModelWorkerService.pending.get(key);
          if (entry !== undefined) {
            entry.reject(new Error('model worker error'));
          }
          ModelWorkerService.pending.delete(key);
        }
      };
      ModelWorkerService.threadWorker = w;
    }
    return ModelWorkerService.threadWorker;
  }

  private static post(type: string, payload: Object, transfer?: Array<ArrayBuffer>): Promise<Object> {
    const w: worker.ThreadWorker = ModelWorkerService.ensureWorker();
    return new Promise<Object>((resolve: (value: Object) => void, reject: (reason: Error) => void) => {
      const id: number = ModelWorkerService.nextId++;
      const entry: PendingEntry = { resolve: resolve, reject: reject };
      ModelWorkerService.pending.set(id, entry);
      const request: ModelRequest = { 'id': id, 'type': type, 'payload': payload };
      if (transfer !== undefined && transfer.length > 0) {
        w.postMessage(request, transfer);
      } else {
        w.postMessage(request);
      }
    });
  }
}