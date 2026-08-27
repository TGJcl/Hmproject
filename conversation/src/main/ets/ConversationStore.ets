import { common } from '@kit.AbilityKit';
import { RdbHelper } from 'database';
import { getLogger } from 'logger';
import { ConversationMessage } from './ConversationMessage';

const TABLE_NAME: string = 'conversation_message';
const SQL_CREATE_TABLE: string =
  'CREATE TABLE IF NOT EXISTS ' + TABLE_NAME +
  ' (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL DEFAULT "default", role TEXT NOT NULL, text TEXT NOT NULL, created_at INTEGER NOT NULL)';
const LOG = getLogger('ConversationStore');

export class ConversationStore {
  static async init(context: common.Context): Promise<void> {
    await RdbHelper.init(context);
    await RdbHelper.executeSql(SQL_CREATE_TABLE);
    LOG.info('init end');
  }

  static async addMessage(context: common.Context, role: string, text: string,
    sessionId: string = 'default'): Promise<number> {
    await ConversationStore.init(context);
    const values = {
      'session_id': sessionId,
      'role': role,
      'text': text,
      'created_at': Date.now()
    };
    const rowId: number = await RdbHelper.insert(TABLE_NAME, values);
    LOG.info('add message, id=%{public}d session=%{public}s role=%{public}s',
      rowId, sessionId, role);
    return rowId;
  }

  static async getHistory(context: common.Context, sessionId: string = 'default',
    limit: number = 100): Promise<Array<ConversationMessage>> {
    await ConversationStore.init(context);
    const sql: string = 'SELECT id, session_id, role, text, created_at FROM ' + TABLE_NAME +
      ' WHERE session_id = ? ORDER BY id DESC LIMIT ?';
    const resultSet = await RdbHelper.querySql(sql, [sessionId, limit]);
    const messages: Array<ConversationMessage> = [];
    try {
      while (resultSet.goToNextRow()) {
        messages.push({
          id: resultSet.getLong(resultSet.getColumnIndex('id')),
          sessionId: resultSet.getString(resultSet.getColumnIndex('session_id')),
          role: resultSet.getString(resultSet.getColumnIndex('role')),
          text: resultSet.getString(resultSet.getColumnIndex('text')),
          createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at'))
        });
      }
    } finally {
      resultSet.close();
    }
    messages.reverse();
    return messages;
  }

  static async clearHistory(context: common.Context, sessionId?: string): Promise<void> {
    await ConversationStore.init(context);
    if (sessionId !== undefined && sessionId !== '') {
      await RdbHelper.executeSql('DELETE FROM ' + TABLE_NAME + ' WHERE session_id = ?', [sessionId]);
      LOG.warn('clear history, session=%{public}s', sessionId);
    } else {
      await RdbHelper.executeSql('DELETE FROM ' + TABLE_NAME);
      LOG.warn('clear all history');
    }
  }
}