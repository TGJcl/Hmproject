import { getLogger } from 'logger';
import { HealthProfile } from '../model/HealthProfile';

const QUESTION_ORDER: Array<string> = ['age', 'height', 'weight', 'sleep', 'exercise', 'symptom'];
const QUESTIONS: Record<string, string> = {
  'age': '请问你今年多大（岁）？',
  'height': '你的身高是多少（cm）？',
  'weight': '你的体重是多少（kg）？',
  'sleep': '最近睡眠情况如何（每晚几小时，或有什么困扰）？',
  'exercise': '平时有运动习惯吗（比如跑步、游泳，每周几次）？',
  'symptom': '最近身体有没有不适或症状？'
};
const LOG = getLogger('HealthChatService');

export interface ChatTurn {
  reply: string;
  profile: HealthProfile;
  done: boolean;
}

export class HealthChatService {
  static greeting(): string {
    return '你好！我是健康助手，想通过对话了解你的身体状况并记入我的记忆库。先从年龄开始吧：请问你今年多大（岁）？';
  }

  static handleUserMessage(input: string, profile: HealthProfile): ChatTurn {
    const text: string = input.trim();
    for (const key of QUESTION_ORDER) {
      if (profile.getField(key) !== '') {
        continue;
      }
      const value: string = HealthChatService.extractField(key, text);
      if (value !== '') {
        profile.setField(key, value);
        LOG.info('collected %{public}s = %{public}s', key, value);
      }
    }
    const next: string = HealthChatService.nextQuestion(profile);
    if (next !== '') {
      return { reply: next, profile: profile, done: false };
    }
    return { reply: HealthChatService.buildSummary(profile), profile: profile, done: true };
  }

  static nextQuestion(profile: HealthProfile): string {
    for (const key of QUESTION_ORDER) {
      if (profile.getField(key) === '') {
        return QUESTIONS[key] ?? '';
      }
    }
    return '';
  }

  static buildSummary(profile: HealthProfile): string {
    return '好的，已为你建立健康档案：' + profile.toMemoryText() + '。现在把它存入我的记忆库。';
  }

  private static extractField(key: string, text: string): string {
    switch (key) {
      case 'age': return HealthChatService.extractAge(text);
      case 'height': return HealthChatService.extractHeight(text);
      case 'weight': return HealthChatService.extractWeight(text);
      case 'sleep': return HealthChatService.extractSleep(text);
      case 'exercise': return HealthChatService.extractExercise(text);
      case 'symptom': return HealthChatService.extractSymptom(text);
      default: return '';
    }
  }

  private static extractAge(text: string): string {
    const m: RegExpMatchArray | null = text.match(/(\d{1,3})\s*岁/);
    if (m !== null && m[1] !== undefined) {
      return m[1] + '岁';
    }
    return '';
  }

  private static extractHeight(text: string): string {
    const m: RegExpMatchArray | null = text.match(/(\d{2,3})\s*(?:cm|厘米)/);
    if (m !== null && m[1] !== undefined) {
      return m[1] + 'cm';
    }
    return '';
  }

  private static extractWeight(text: string): string {
    const kg: RegExpMatchArray | null = text.match(/(\d{2,3})\s*(?:kg|公斤|千克)/);
    if (kg !== null && kg[1] !== undefined) {
      return kg[1] + 'kg';
    }
    const jin: RegExpMatchArray | null = text.match(/(\d{2,3})\s*斤/);
    if (jin !== null && jin[1] !== undefined) {
      return jin[1] + '斤';
    }
    return '';
  }

  private static extractSleep(text: string): string {
    const hours: RegExpMatchArray | null = text.match(/(\d+(?:\.\d+)?)\s*小时/);
    if (hours !== null && hours[1] !== undefined) {
      return hours[1] + '小时';
    }
    if (/失眠|熬夜/.test(text)) {
      return '失眠/熬夜';
    }
    return HealthChatService.extractNone(text);
  }

  private static extractExercise(text: string): string {
    const activity: RegExpMatchArray | null = text.match(/(跑步|游泳|散步|健身|瑜伽|骑行|篮球|羽毛球|太极|跳绳)/);
    if (activity !== null && activity[1] !== undefined) {
      const freq: RegExpMatchArray | null = text.match(/每[周天]?\s*(\d+)\s*次/);
      if (freq !== null && freq[1] !== undefined) {
        return activity[1] + '，每周' + freq[1] + '次';
      }
      return activity[1];
    }
    return HealthChatService.extractNone(text);
  }

  private static extractSymptom(text: string): string {
    const keywords: Array<string> = ['头疼', '头痛', '发热', '发烧', '咳嗽', '胃痛', '胃疼', '腹泻', '便秘', '乏力', '过敏'];
    const found: Array<string> = [];
    for (const keyword of keywords) {
      if (text.includes(keyword)) {
        found.push(keyword);
      }
    }
    if (found.length > 0) {
      return found.join('、');
    }
    return HealthChatService.extractNone(text);
  }

  private static extractNone(text: string): string {
    if (/没有|无/.test(text)) {
      return '无';
    }
    return '';
  }
}
