import embeddingNative from 'libembedding.so';
import { EmbeddingProvider } from './LocalHashEmbedding';

export class NativeEmbedding implements EmbeddingProvider {
  static init(modelPath: string, tokenizerPath: string): void {
    embeddingNative.init(modelPath, tokenizerPath);
  }

  async embed(text: string): Promise<Array<number>> {
    return embeddingNative.embed(text);
  }
}
