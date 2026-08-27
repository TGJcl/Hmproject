import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { DeepSeekClient, DeepSeekConfig, DeepSeekMessage } from 'deepseek';
import { EmbeddingManager } from 'embedding';
import { VectorDatabase } from 'vector';
import { getLogger } from 'logger';
import { HealthProfile } from '../model/HealthProfile';
import { MemoryService } from './MemoryService';
import { DietAdviceService } from './DietAdviceService';

export enum AgentWorkflow {
  HEALTH_PROFILE = 0,
  AI_QA = 1
}

export interface AgentRunResult {
  replies: Array<string>;
  workflow: AgentWorkflow;
  needKey: boolean;
  apiError: boolean;
}

const RAG_TOP_K: number = 3;
const PROMPT_RAW_PATH: string = 'prompts/agent_prompt.md';
const NO_MEMORY: string = '（暂无相关记忆）';
const FIELD_KEYS: Array<string> = ['age', 'height', 'weight', 'sleep', 'exercise', 'symptom', 'history', 'duration'];
const FALLBACK_SYSTEM_PROMPT: string =
  '你是“健康助手”，运行在用户本机（鸿蒙应用）里的 AI 助手，根据对话上下文自行判断当前任务：' +
  '1) 健康档案采集（mode=profile）：用户提供健康信息（年龄、身高、体重、睡眠、运动、症状、当前病史、患病周期）时抽取到 fields，并每次只追问一个缺失字段；' +
  '2) 健康问答（mode=qa）：用户提问时结合“记忆片段”回答，没有相关信息就如实说明。' +
  '只输出严格 JSON：{"mode":"profile"或"qa","reply":"给用户的回复","fields":{"age":"","height":"","weight":"","sleep":"","exercise":"","symptom":"","history":"","duration":""},"done":false}。' +
  'fields 只填本次确认的字段，未确认留空。';
const LOG = getLogger('ChatAgent');

export class ChatAgent {
  private workflow: AgentWorkflow = AgentWorkflow.AI_QA;
  private profile: HealthProfile = new HealthProfile();
  private profileSaved: boolean = false;
  private systemPrompt: string = FALLBACK_SYSTEM_PROMPT;
  private promptLoaded: boolean = false;

  get currentWorkflow(): AgentWorkflow {
    return this.workflow;
  }

  greeting(): string {
    return '你好！我是健康助手。你可以告诉我年龄、身高、体重、睡眠、运动、症状或病史等信息来建立健康档案，也可以直接向我提问健康问题。';
  }

  async run(context: common.Context, input: string): Promise<AgentRunResult> {
    const apiKey: string = await DeepSeekConfig.getApiKey(context);
    if (apiKey === '') {
      return { replies: [], workflow: this.workflow, needKey: true, apiError: false };
    }
    try {
      await this.ensurePrompt(context);
      await VectorDatabase.init(context);
      const queryVector: Array<number> = await EmbeddingManager.embed(input);
      const records = await VectorDatabase.search(queryVector, RAG_TOP_K);
      let memoryText: string = NO_MEMORY;
      if (records.length > 0) {
        memoryText = records.map((record) => '- ' + record.content).join('\n');
      }
      const messages: Array<DeepSeekMessage> = [
        { role: 'system', content: this.systemPrompt },
        {
          role: 'user',
          content: '当前档案：' + this.profileText() + '\n\n记忆片段：\n' + memoryText + '\n\n用户输入：' + input
        }
      ];
      const content: string = await DeepSeekClient.chat(apiKey, messages);
      return await this.handleContent(context, content);
    } catch (e) {
      LOG.warn('agent run failed: %{public}s', (e as Error).message);
      return { replies: [], workflow: this.workflow, needKey: false, apiError: true };
    }
  }

  private profileText(): string {
    const filled: Array<string> = [];
    for (const key of FIELD_KEYS) {
      if (this.profile.getField(key) !== '') {
        filled.push(this.profile.getField(key));
      }
    }
    return filled.length > 0 ? this.profile.toMemoryText() : '尚未建立';
  }

  private async handleContent(context: common.Context, content: string): Promise<AgentRunResult> {
    const jsonText: string = ChatAgent.extractJson(content);
    if (jsonText === '') {
      return { replies: [content], workflow: AgentWorkflow.AI_QA, needKey: false, apiError: false };
    }
    const parsed: Record<string, Object> = JSON.parse(jsonText) as Record<string, Object>;
    const reply: string = parsed['reply'] as string;
    if (reply === undefined || reply === '') {
      return { replies: [content], workflow: AgentWorkflow.AI_QA, needKey: false, apiError: false };
    }
    const mode: string = parsed['mode'] as string;
    if (mode !== 'profile') {
      this.workflow = AgentWorkflow.AI_QA;
      return { replies: [reply], workflow: AgentWorkflow.AI_QA, needKey: false, apiError: false };
    }
    // 健康档案工作流：抽取字段
    this.workflow = AgentWorkflow.HEALTH_PROFILE;
    const fields: Record<string, string> = parsed['fields'] as Record<string, string>;
    if (fields !== undefined) {
      for (const key of FIELD_KEYS) {
        const value: string = fields[key] as string;
        if (value !== undefined && value !== '' && this.profile.getField(key) === '') {
          this.profile.setField(key, value);
          LOG.info('agent collected %{public}s = %{public}s', key, value);
        }
      }
    }
    const replies: Array<string> = [reply];
    if (this.profile.isComplete() && !this.profileSaved) {
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
      // 档案已完成，回到问答工作流，等待下次重新建档
      this.workflow = AgentWorkflow.AI_QA;
      this.profile = new HealthProfile();
      this.profileSaved = false;
    }
    return { replies: replies, workflow: AgentWorkflow.HEALTH_PROFILE, needKey: false, apiError: false };
  }

  private static extractJson(text: string): string {
    const start: number = text.indexOf('{');
    const end: number = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      return '';
    }
    return text.substring(start, end + 1);
  }

  private async ensurePrompt(context: common.Context): Promise<void> {
    if (this.promptLoaded) {
      return;
    }
    try {
      const raw: Uint8Array = await context.resourceManager.getRawFileContent(PROMPT_RAW_PATH);
      const text: string = util.TextDecoder.create('utf-8').decodeToString(raw);
      if (text.trim().length > 0) {
        this.systemPrompt = text.trim();
        LOG.info('agent prompt loaded from rawfile');
      }
    } catch (e) {
      LOG.warn('load agent prompt failed, use built-in: %{public}s', (e as Error).message);
    }
    this.promptLoaded = true;
  }
}