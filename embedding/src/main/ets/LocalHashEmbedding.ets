const VECTOR_DIM: number = 128;
const NGRAM_SIZE: number = 3;

export interface EmbeddingProvider {
  embed(text: string): Promise<Array<number>>;
}

// 占位实现：字符 n-gram 哈希向量。
// TODO: 后续替换为本地 ONNX / MindSpore 模型（NDK C++ 推理），接口保持不变。
export class LocalHashEmbedding implements EmbeddingProvider {
  async embed(text: string): Promise<Array<number>> {
    const vector: Array<number> = new Array<number>(VECTOR_DIM).fill(0);
    const normalized: string = text.trim().toLowerCase();
    for (let i = 0; i <= normalized.length - NGRAM_SIZE; i++) {
      const gram: string = normalized.substring(i, i + NGRAM_SIZE);
      let hash: number = 0;
      for (let j = 0; j < gram.length; j++) {
        hash = (hash * 31 + gram.charCodeAt(j)) >>> 0;
      }
      const index: number = hash % VECTOR_DIM;
      vector[index] = vector[index] + 1;
    }
    let norm: number = 0;
    for (const v of vector) {
      norm += v * v;
    }
    if (norm > 0) {
      const inv: number = 1 / Math.sqrt(norm);
      for (let i = 0; i < VECTOR_DIM; i++) {
        vector[i] = vector[i] * inv;
      }
    }
    return vector;
  }
}
