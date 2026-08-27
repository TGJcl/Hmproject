import { NetworkClient } from 'network';
import { getLogger } from 'logger';
import { DeepSeekMessage, DeepSeekRequest, DeepSeekResponse } from './DeepSeekMessage';

const API_URL: string = 'https://api.deepseek.com/chat/completions';
const MODEL_NAME: string = 'deepseek-chat';
const TEMPERATURE: number = 0.7;
const REQUEST_TIMEOUT: number = 60000;
const LOG = getLogger('DeepSeekClient');

export class DeepSeekClient {
  static async chat(apiKey: string, messages: Array<DeepSeekMessage>): Promise<string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + apiKey
    };
    const body: DeepSeekRequest = {
      model: MODEL_NAME,
      messages: messages,
      temperature: TEMPERATURE,
      stream: false
    };
    const response: string = await NetworkClient.postJson(API_URL, headers, body, REQUEST_TIMEOUT);
    const parsed = JSON.parse(response) as DeepSeekResponse;
    if (parsed.choices === undefined || parsed.choices.length === 0) {
      throw new Error('DeepSeek response has no choices');
    }
    const content: string = parsed.choices[0].message.content;
    if (content === '') {
      throw new Error('DeepSeek response content is empty');
    }
    LOG.info('chat ok, reply length=%{public}d', content.length);
    return content;
  }
}
