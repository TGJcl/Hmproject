import { EmbeddingProvider, LocalHashEmbedding } from './LocalHashEmbedding';

export class EmbeddingManager {
  private static provider: EmbeddingProvider = new LocalHashEmbedding();

  static setProvider(provider: EmbeddingProvider): void {
    EmbeddingManager.provider = provider;
  }

  static async embed(text: string): Promise<Array<number>> {
    return EmbeddingManager.provider.embed(text);
  }
}
