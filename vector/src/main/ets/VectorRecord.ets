export interface VectorRecord {
  id: number;
  content: string;
  vector: Array<number>;
  metadata: string;
  score: number;
}
