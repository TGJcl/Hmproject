import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { RdbHelper } from 'database';
import { getLogger } from 'logger';
import { VectorRecord, VectorMetaRecord } from './VectorRecord';

const TABLE_NAME: string = 'vector_memory';
const SQL_CREATE_TABLE: string =
  'CREATE TABLE IF NOT EXISTS ' + TABLE_NAME +
  ' (id INTEGER PRIMARY KEY AUTOINCREMENT, content TEXT NOT NULL, vector TEXT NOT NULL, metadata TEXT NOT NULL, created_at INTEGER NOT NULL)';
const SQL_SELECT_ALL: string = 'SELECT id, content, vector, metadata FROM ' + TABLE_NAME;
const SQL_COUNT: string = 'SELECT COUNT(*) AS count FROM ' + TABLE_NAME;
const LOG = getLogger('VectorDatabase');

export class VectorDatabase {
  static async init(context: common.Context): Promise<void> {
    await RdbHelper.init(context);
    await RdbHelper.executeSql(SQL_CREATE_TABLE);
    LOG.info('init end');
  }

  static async add(content: string, vector: Array<number>, metadata: string): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'content': content,
      'vector': JSON.stringify(vector),
      'metadata': metadata,
      'created_at': Date.now()
    };
    const rowId: number = await RdbHelper.insert(TABLE_NAME, values);
    LOG.info('add memory, id=%{public}d', rowId);
    return rowId;
  }

  static async existsByMetadata(metadata: string): Promise<boolean> {
    const sql: string = 'SELECT COUNT(*) AS count FROM ' + TABLE_NAME + ' WHERE metadata = ?';
    const resultSet = await RdbHelper.querySql(sql, [metadata]);
    try {
      let count: number = 0;
      if (resultSet.goToFirstRow()) {
        count = resultSet.getLong(resultSet.getColumnIndex('count'));
      }
      return count > 0;
    } finally {
      resultSet.close();
    }
  }

  static async findByMetadataLike(pattern: string): Promise<Array<VectorMetaRecord>> {
    const sql: string = 'SELECT id, content, metadata FROM ' + TABLE_NAME + ' WHERE metadata LIKE ?';
    const resultSet = await RdbHelper.querySql(sql, [pattern]);
    const records: Array<VectorMetaRecord> = [];
    try {
      while (resultSet.goToNextRow()) {
        records.push({
          id: resultSet.getLong(resultSet.getColumnIndex('id')),
          content: resultSet.getString(resultSet.getColumnIndex('content')),
          metadata: resultSet.getString(resultSet.getColumnIndex('metadata'))
        });
      }
    } finally {
      resultSet.close();
    }
    return records;
  }

  static async deleteById(id: number): Promise<void> {
    await RdbHelper.executeSql('DELETE FROM ' + TABLE_NAME + ' WHERE id = ?', [id]);
    LOG.info('delete memory, id=%{public}d', id);
  }

  static async search(query: Array<number>, topK: number): Promise<Array<VectorRecord>> {
    const resultSet = await RdbHelper.querySql(SQL_SELECT_ALL);
    const results: Array<VectorRecord> = [];
    try {
      while (resultSet.goToNextRow()) {
        const id: number = resultSet.getLong(resultSet.getColumnIndex('id'));
        const content: string = resultSet.getString(resultSet.getColumnIndex('content'));
        const vectorJson: string = resultSet.getString(resultSet.getColumnIndex('vector'));
        const metadata: string = resultSet.getString(resultSet.getColumnIndex('metadata'));
        const vector: Array<number> = JSON.parse(vectorJson) as Array<number>;
        const score: number = VectorDatabase.cosineSimilarity(query, vector);
        results.push({ id: id, content: content, vector: vector, metadata: metadata, score: score });
      }
    } finally {
      resultSet.close();
    }
    results.sort((a: VectorRecord, b: VectorRecord) => b.score - a.score);
    return results.slice(0, topK);
  }

  static async count(): Promise<number> {
    const resultSet = await RdbHelper.querySql(SQL_COUNT);
    try {
      let count: number = 0;
      if (resultSet.goToFirstRow()) {
        count = resultSet.getLong(resultSet.getColumnIndex('count'));
      }
      return count;
    } finally {
      resultSet.close();
    }
  }

  static async clear(): Promise<void> {
    await RdbHelper.executeSql('DELETE FROM ' + TABLE_NAME);
    LOG.warn('clear all memories');
  }

  static cosineSimilarity(a: Array<number>, b: Array<number>): number {
    let dot: number = 0;
    let na: number = 0;
    let nb: number = 0;
    for (let i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na === 0 || nb === 0) {
      return 0;
    }
    return dot / (Math.sqrt(na) * Math.sqrt(nb));
  }
}