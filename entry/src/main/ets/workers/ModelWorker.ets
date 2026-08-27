import { worker, ThreadWorkerGlobalScope, MessageEvents } from '@kit.ArkTS';
import { EmbeddingManager, NativeEmbedding } from 'embedding';
import { YoloDetector } from 'yolo';

interface ModelRequest {
  id: number;
  type: string;
  payload: Object;
}

const workerPort: ThreadWorkerGlobalScope = worker.workerPort;
let embedNative: boolean = false;

workerPort.onmessage = (event: MessageEvents) => {
  const request: ModelRequest = event.data as ModelRequest;
  ModelWorker.handle(request).then((result: Object) => {
    workerPort.postMessage({ 'id': request.id, 'ok': true, 'payload': result });
  }).catch((error: Error) => {
    workerPort.postMessage({ 'id': request.id, 'ok': false, 'error': error.message });
  });
};

class ModelWorker {
  static async handle(request: ModelRequest): Promise<Object> {
    if (request.type === 'embed_init') {
      const payload: Record<string, string> = request.payload as Record<string, string>;
      try {
        NativeEmbedding.init(payload['modelPath'], payload['tokenizerPath']);
        EmbeddingManager.setProvider(new NativeEmbedding());
        embedNative = true;
      } catch (e) {
        embedNative = false;
      }
      return true;
    }
    if (request.type === 'embed') {
      const payload: Record<string, string> = request.payload as Record<string, string>;
      return await EmbeddingManager.embed(payload['text']);
    }
    if (request.type === 'yolo_init') {
      const payload: Record<string, Object> = request.payload as Record<string, Object>;
      const buffer: ArrayBuffer = payload['model'] as ArrayBuffer;
      YoloDetector.initFromBuffer(buffer);
      return true;
    }
    if (request.type === 'yolo_detect') {
      const payload: Record<string, Object> = request.payload as Record<string, Object>;
      const buffer: ArrayBuffer = payload['image'] as ArrayBuffer;
      const width: number = payload['width'] as number;
      const height: number = payload['height'] as number;
      return await YoloDetector.detect(buffer, width, height);
    }
    throw new Error('unknown request type: ' + request.type);
  }
}