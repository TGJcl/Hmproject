import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'health.db';

export class RdbHelper {
  private static store: relationalStore.RdbStore | undefined = undefined;

  static async init(context: common.Context): Promise<void> {
    if (RdbHelper.store !== undefined) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: STORE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    RdbHelper.store = await relationalStore.getRdbStore(context, config);
  }

  static getStore(): relationalStore.RdbStore {
    if (RdbHelper.store === undefined) {
      throw new Error('RdbHelper not initialized. Call init() first.');
    }
    return RdbHelper.store;
  }

  static async executeSql(sql: string, bindArgs?: Array<relationalStore.ValueType>): Promise<void> {
    await RdbHelper.getStore().executeSql(sql, bindArgs);
  }

  static async insert(table: string, values: relationalStore.ValuesBucket): Promise<number> {
    return RdbHelper.getStore().insert(table, values);
  }

  static async querySql(sql: string, bindArgs?: Array<relationalStore.ValueType>): Promise<relationalStore.ResultSet> {
    return RdbHelper.getStore().querySql(sql, bindArgs);
  }
}
