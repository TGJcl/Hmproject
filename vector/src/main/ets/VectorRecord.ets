export interface VectorRecord {
  id: number;
  content: string;
  vector: Array<number>;
  metadata: string;
  score: number;
}

export interface VectorMetaRecord {
  id: number;
  content: string;
  metadata: string;
}