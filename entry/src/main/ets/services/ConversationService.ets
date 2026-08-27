import { common } from '@kit.AbilityKit';
import { ConversationMessage, ConversationStore } from 'conversation';
import { getLogger } from 'logger';

const SESSION_HEALTH_CHAT: string = 'health_chat';
const SESSION_AI_CHAT: string = 'ai_chat';
const HISTORY_LIMIT: number = 100;
const LOG = getLogger('ConversationService');

export class ConversationService {
  static async recordHealth(context: common.Context, role: string, text: string): Promise<number> {
    return ConversationService.record(context, SESSION_HEALTH_CHAT, role, text);
  }

  static async recordAi(context: common.Context, role: string, text: string): Promise<number> {
    return ConversationService.record(context, SESSION_AI_CHAT, role, text);
  }

  static async getHealthHistory(context: common.Context): Promise<Array<ConversationMessage>> {
    return ConversationStore.getHistory(context, SESSION_HEALTH_CHAT, HISTORY_LIMIT);
  }

  static async getAiHistory(context: common.Context): Promise<Array<ConversationMessage>> {
    return ConversationStore.getHistory(context, SESSION_AI_CHAT, HISTORY_LIMIT);
  }

  private static async record(context: common.Context, sessionId: string,
    role: string, text: string): Promise<number> {
    const content: string = text.trim();
    if (content === '') {
      return -1;
    }
    try {
      return await ConversationStore.addMessage(context, role, content, sessionId);
    } catch (e) {
      LOG.warn('record conversation failed: %{public}s', (e as Error).message);
      return -1;
    }
  }
}