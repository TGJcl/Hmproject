import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { DeepSeekClient, DeepSeekConfig, DeepSeekMessage } from 'deepseek';
import { EmbeddingManager } from 'embedding';
import { VectorDatabase, VectorRecord } from 'vector';
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

interface AgentFact {
  subject: string;
  text: string;
  time: string;
  status: string;
}

const RAG_TOP_K: number = 3;
const PROMPT_RAW_PATH: string = 'prompts/agent_prompt.md';
const NO_MEMORY: string = '（暂无相关记忆）';
const FIELD_KEYS: Array<string> = ['age', 'height', 'weight', 'sleep', 'exercise', 'symptom', 'history', 'duration'];
const FALLBACK_SYSTEM_PROMPT: string =
  '你是“健康助手”，运行在用户本机（鸿蒙应用）里的 AI 助手，根据对话上下文自行判断当前任务：' +
  '1) 健康档案采集（mode=profile）：用户提供健康信息（年龄、身高、体重、睡眠、运动、症状、当前病史、患病周期）时抽取到 fields，并每次只追问一个缺失字段；' +
  '2) 健康问答（mode=qa）：用户提问时结合“记忆片段”回答，没有相关信息就如实说明。' +
  '3) 事实记录（facts）：用户透露出新的健康事实时输出记录 {"subject":"病症关键词","text":"完整句子","time":"YYYY-MM-DD","status":"active"}；用户表示已痊愈/不再发作时输出 status 为 resolved 的记录。' +
  '只输出严格 JSON：{"mode":"profile"或"qa","reply":"给用户的回复","fields":{"age":"","height":"","weight":"","sleep":"","exercise":"","symptom":"","history":"","duration":""},"facts":[],"done":false}。' +
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
        memoryText = records.map((record) => ChatAgent.memoryLine(record)).join('\n');
      }
      const messages: Array<DeepSeekMessage> = [
        { role: 'system', content: this.systemPrompt },
        {
          role: 'user',
          content: '当前日期：' + ChatAgent.today() + '\n当前档案：' + this.profileText() +
            '\n\n记忆片段：\n' + memoryText + '\n\n用户输入：' + input
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
    let replies: Array<string>;
    let resultWorkflow: AgentWorkflow;
    if (mode !== 'profile') {
      this.workflow = AgentWorkflow.AI_QA;
      replies = [reply];
      resultWorkflow = AgentWorkflow.AI_QA;
    } else {
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
      replies = [reply];
      resultWorkflow = AgentWorkflow.HEALTH_PROFILE;
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
        this.workflow = AgentWorkflow.AI_QA;
        this.profile = new HealthProfile();
        this.profileSaved = false;
      }
    }
    const facts: Array<AgentFact> = ChatAgent.parseFacts(parsed['facts']);
    await this.storeFacts(context, facts);
    return { replies: replies, workflow: resultWorkflow, needKey: false, apiError: false };
  }

  private static parseFacts(raw: Object | undefined): Array<AgentFact> {
    const result: Array<AgentFact> = [];
    if (raw === undefined) {
      return result;
    }
    const items: Array<Object> = raw as Array<Object>;
    for (const item of items) {
      const obj: Record<string, Object> = item as Record<string, Object>;
      const fact: AgentFact = {
        subject: (obj['subject'] as string) ?? '',
        text: (obj['text'] as string) ?? '',
        time: (obj['time'] as string) ?? '',
        status: (obj['status'] as string) ?? 'active'
      };
      result.push(fact);
    }
    return result;
  }

  private async storeFacts(context: common.Context, facts: Array<AgentFact>): Promise<void> {
    if (facts.length === 0) {
      return;
    }
    try {
      await VectorDatabase.init(context);
      for (const fact of facts) {
        const text: string = fact.text.trim();
        if (text === '') {
          continue;
        }
        const subject: string = fact.subject.trim();
        const time: string = fact.time.trim();
        if (fact.status === 'resolved') {
          await this.resolveFact(context, subject, text, time);
        } else {
          await this.storeActiveFact(context, subject, text, time);
        }
      }
    } catch (e) {
      LOG.warn('store facts failed: %{public}s', (e as Error).message);
    }
  }

  private async storeActiveFact(context: common.Context, subject: string, text: string, time: string): Promise<void> {
    if (subject !== '') {
      const pattern: string = '"subject":"' + subject + '"';
      const existing = await VectorDatabase.findByMetadataLike(pattern);
      for (const rec of existing) {
        if (ChatAgent.metaStatus(rec.metadata) === 'active') {
          LOG.info('fact already active, skip: %{public}s', subject);
          return;
        }
      }
    }
    const metadata: string = JSON.stringify({
      'source': 'chat_fact',
      'subject': subject,
      'status': 'active',
      'fact': text,
      'time': time
    });
    const vector: Array<number> = await EmbeddingManager.embed(text);
    await VectorDatabase.add(text, vector, metadata);
    LOG.info('fact stored: %{public}s', text);
  }

  private async resolveFact(context: common.Context, subject: string, text: string, time: string): Promise<void> {
    if (subject !== '') {
      const pattern: string = '"subject":"' + subject + '"';
      const existing = await VectorDatabase.findByMetadataLike(pattern);
      for (const rec of existing) {
        if (ChatAgent.metaStatus(rec.metadata) === 'active') {
          await VectorDatabase.deleteById(rec.id);
          LOG.info('fact resolved and removed: %{public}s', rec.content);
        }
      }
    }
    const dupPattern: string = '"fact":"' + text + '"';
    const dup = await VectorDatabase.findByMetadataLike(dupPattern);
    for (const rec of dup) {
      if (ChatAgent.metaStatus(rec.metadata) === 'resolved') {
        LOG.info('resolved fact already exists, skip: %{public}s', text);
        return;
      }
    }
    const metadata: string = JSON.stringify({
      'source': 'chat_fact',
      'subject': subject,
      'status': 'resolved',
      'fact': text,
      'time': time
    });
    const vector: Array<number> = await EmbeddingManager.embed(text);
    await VectorDatabase.add(text, vector, metadata);
    LOG.info('resolved fact stored: %{public}s', text);
  }

  private static metaStatus(metadata: string): string {
    try {
      const obj: Record<string, Object> = JSON.parse(metadata) as Record<string, Object>;
      const status: string = obj['status'] as string;
      return status === 'resolved' ? 'resolved' : 'active';
    } catch (e) {
      return 'active';
    }
  }

  private static memoryLine(record: VectorRecord): string {
    let tag: string = '';
    try {
      const meta: Record<string, Object> = JSON.parse(record.metadata) as Record<string, Object>;
      const time: string = meta['time'] as string;
      const status: string = meta['status'] as string;
      if (time !== undefined && time !== '') {
        tag = '[' + time + (status === 'resolved' ? '，已解除' : '') + '] ';
      }
    } catch (e) {
    }
    return '- ' + tag + record.content;
  }

  private static today(): string {
    const now = new Date();
    const month: string = (now.getMonth() + 1) < 10 ?
      '0' + (now.getMonth() + 1).toString() : (now.getMonth() + 1).toString();
    const day: string = now.getDate() < 10 ?
      '0' + now.getDate().toString() : now.getDate().toString();
    return now.getFullYear().toString() + '-' + month + '-' + day;
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