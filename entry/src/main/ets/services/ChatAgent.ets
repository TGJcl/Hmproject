import { common } from '@kit.AbilityKit';
import { DeepSeekConfig } from 'deepseek';
import { getLogger } from 'logger';
import { HealthProfile } from '../model/HealthProfile';
import { HealthChatService, HealthChatAiResult } from './HealthChatService';
import { AiChatService } from './AiChatService';
import { MemoryService } from './MemoryService';
import { DietAdviceService } from './DietAdviceService';

export enum AgentWorkflow {
  HEALTH_PROFILE = 0,
  AI_QA = 1
}

export interface AgentRunResult {
  replies: Array<string>;
  needKey: boolean;
  apiError: boolean;
}

const LOG = getLogger('ChatAgent');

export class ChatAgent {
  private workflow: AgentWorkflow = AgentWorkflow.HEALTH_PROFILE;
  private profile: HealthProfile = new HealthProfile();
  private profileSaved: boolean = false;

  setWorkflow(workflow: AgentWorkflow): void {
    this.workflow = workflow;
    this.profile = new HealthProfile();
    this.profileSaved = false;
    LOG.info('workflow switched to %{public}d', workflow);
  }

  greeting(): string {
    if (this.workflow === AgentWorkflow.HEALTH_PROFILE) {
      return HealthChatService.greeting();
    }
    return '你好！我是 AI 健康助手，可以结合你的记忆库回答健康问题。';
  }

  async run(context: common.Context, input: string): Promise<AgentRunResult> {
    if (this.workflow === AgentWorkflow.HEALTH_PROFILE) {
      return this.runHealthProfile(context, input);
    }
    return this.runAiQa(context, input);
  }

  private async runHealthProfile(context: common.Context, input: string): Promise<AgentRunResult> {
    const result: HealthChatAiResult = await HealthChatService.handleUserMessageWithDeepSeek(context, input, this.profile);
    if (!result.ok) {
      return { replies: [], needKey: result.needKey, apiError: !result.needKey };
    }
    const turn = result.turn;
    if (turn === undefined) {
      return { replies: [], needKey: false, apiError: false };
    }
    this.profile = turn.profile;
    const replies: Array<string> = [turn.reply];
    if (turn.done && !this.profileSaved) {
      this.profileSaved = true;
      await MemoryService.init(context);
      const id: number = await MemoryService.saveHealthProfile(this.profile);
      replies.push('已存入记忆库（记录编号 ' + id + '）');
      if (this.profile.history !== '' && this.profile.history !== '无') {
        const advice: string = await DietAdviceService.queryDietAdviceAndStore(context, this.profile.history);
        if (advice !== '') {
          replies.push('根据' + this.profile.history + '，为你查询到以下饮食注意事项：\n' + advice);
        } else {
          replies.push('未能查询到' + this.profile.history + '的饮食建议，可稍后重试。');
        }
      }
    }
    return { replies: replies, needKey: false, apiError: false };
  }

  private async runAiQa(context: common.Context, input: string): Promise<AgentRunResult> {
    try {
      const reply: string = await AiChatService.chat(context, input);
      return { replies: [reply], needKey: false, apiError: false };
    } catch (e) {
      LOG.warn('ai qa failed: %{public}s', (e as Error).message);
      let needKey: boolean = false;
      try {
        const apiKey: string = await DeepSeekConfig.getApiKey(context);
        needKey = apiKey === '';
      } catch (keyErr) {
        needKey = true;
      }
      return { replies: [], needKey: needKey, apiError: !needKey };
    }
  }
}