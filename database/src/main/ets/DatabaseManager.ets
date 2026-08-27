import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'health.db';
const TABLE_NAME: string = 'health_record';
const SQL_CREATE_TABLE: string =
  'CREATE TABLE IF NOT EXISTS ' + TABLE_NAME +
  ' (id INTEGER PRIMARY KEY AUTOINCREMENT, value INTEGER NOT NULL, created_at INTEGER NOT NULL)';
const SQL_COUNT: string = 'SELECT COUNT(*) AS count FROM ' + TABLE_NAME;
const SQL_LATEST: string = 'SELECT value FROM ' + TABLE_NAME + ' ORDER BY id DESC LIMIT 1';

export class DatabaseManager {
  private static store: relationalStore.RdbStore | undefined = undefined;

  static async init(context: common.Context): Promise<void> {
    if (DatabaseManager.store !== undefined) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: STORE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    DatabaseManager.store = await relationalStore.getRdbStore(context, config);
    await DatabaseManager.store.executeSql(SQL_CREATE_TABLE);
  }

  static async insertRecord(value: number): Promise<void> {
    const store = DatabaseManager.requireStore();
    const values: relationalStore.ValuesBucket = {
      'value': value,
      'created_at': Date.now()
    };
    await store.insert(TABLE_NAME, values);
  }

  static async queryRecordCount(): Promise<number> {
    const store = DatabaseManager.requireStore();
    const resultSet = await store.querySql(SQL_COUNT);
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

  static async queryLatestValue(): Promise<number> {
    const store = DatabaseManager.requireStore();
    const resultSet = await store.querySql(SQL_LATEST);
    try {
      let latest: number = 0;
      if (resultSet.goToFirstRow()) {
        latest = resultSet.getLong(resultSet.getColumnIndex('value'));
      }
      return latest;
    } finally {
      resultSet.close();
    }
  }

  private static requireStore(): relationalStore.RdbStore {
    if (DatabaseManager.store === undefined) {
      throw new Error('DatabaseManager not initialized. Call init() first.');
    }
    return DatabaseManager.store;
  }
}
