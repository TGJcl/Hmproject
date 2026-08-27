import { common } from '@kit.AbilityKit';
import { DeepSeekConfig } from 'deepseek';
import { ApiKeyPrompt } from '../components/ApiKeyPrompt';
import { ChatBubble } from '../components/ChatBubble';
import { ChatMessage } from '../model/ChatMessage';
import { AiChatService } from '../services/AiChatService';
import { ConversationService } from '../services/ConversationService';

const AI_GREETING: string = '你好！我是 AI 健康助手，可以结合你的记忆库回答健康问题。';

@Entry
@Component
struct AiChat {
  @State messages: Array<ChatMessage> = [];
  @State input: string = '';
  @State thinking: boolean = false;
  @State showKeyDialog: boolean = false;

  aboutToAppear(): void {
    this.checkApiKey();
  }

  private async checkApiKey(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const key: string = await DeepSeekConfig.getApiKey(context);
    if (key === '') {
      this.showKeyDialog = true;
    } else {
      this.pushBot(AI_GREETING);
    }
  }

  private pushBot(text: string): void {
    const msg = new ChatMessage();
    msg.role = 'bot';
    msg.text = text;
    this.messages.push(msg);
    this.recordMessage('bot', text);
  }

  private recordMessage(role: string, text: string): void {
    const context = getContext(this) as common.UIAbilityContext;
    ConversationService.recordAi(context, role, text);
  }

  private async saveApiKey(key: string): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    await DeepSeekConfig.setApiKey(context, key);
    this.showKeyDialog = false;
    this.pushBot(AI_GREETING);
  }

  private closeApiKeyDialog(): void {
    this.showKeyDialog = false;
  }

  private async handleSend(): Promise<void> {
    const text: string = this.input.trim();
    if (text === '' || this.thinking) {
      return;
    }
    this.input = '';
    const userMsg = new ChatMessage();
    userMsg.role = 'user';
    userMsg.text = text;
    this.messages.push(userMsg);
    this.recordMessage('user', text);
    this.thinking = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const reply: string = await AiChatService.chat(context, text);
      this.pushBot(reply);
    } catch (e) {
      this.pushBot('请求失败，请检查 API Key 或网络后重试。');
    } finally {
      this.thinking = false;
    }
  }

  build() {
    Stack() {
      Column() {
        Text($r('app.string.ai_chat_title'))
          .fontSize($r('app.float.title_font_size'))
          .fontColor($r('app.color.text_primary'))
          .fontWeight(FontWeight.Bold)
          .padding($r('app.float.page_margin'))
        List({ space: $r('app.float.page_space') }) {
          ForEach(this.messages, (msg: ChatMessage, index: number) => {
            ListItem() {
              ChatBubble({ role: msg.role, text: msg.text })
            }
          }, (msg: ChatMessage, index: number) => index.toString())
          if (this.thinking) {
            ListItem() {
              ChatBubble({ role: 'bot', text: '思考中…' })
            }
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding($r('app.float.page_margin'))
        Row({ space: $r('app.float.page_space') }) {
          TextInput({ placeholder: $r('app.string.input_placeholder'), text: this.input })
            .layoutWeight(1)
            .height($r('app.float.input_height'))
            .fontSize($r('app.float.text_font_size'))
            .onChange((value: string) => {
              this.input = value;
            })
          Button($r('app.string.btn_send'))
            .height($r('app.float.input_height'))
            .backgroundColor($r('app.color.button_background'))
            .fontColor($r('app.color.button_text'))
            .onClick(() => {
              this.handleSend();
            })
        }
        .width('100%')
        .padding($r('app.float.page_margin'))
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

      if (this.showKeyDialog) {
        ApiKeyPrompt({
          show: this.showKeyDialog,
          onSave: (key: string) => {
            this.saveApiKey(key);
          },
          onClose: () => {
            this.closeApiKeyDialog();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}