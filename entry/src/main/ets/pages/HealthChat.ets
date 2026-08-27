import { common } from '@kit.AbilityKit';
import { DeepSeekConfig } from 'deepseek';
import { ApiKeyPrompt } from '../components/ApiKeyPrompt';
import { ChatBubble } from '../components/ChatBubble';
import { ChatMessage } from '../model/ChatMessage';
import { HealthProfile } from '../model/HealthProfile';
import { HealthChatService } from '../services/HealthChatService';
import { MemoryService } from '../services/MemoryService';
import { ConversationService } from '../services/ConversationService';
import { DietAdviceService } from '../services/DietAdviceService';

@Entry
@Component
struct HealthChat {
  @State messages: Array<ChatMessage> = [];
  @State input: string = '';
  @State profile: HealthProfile = new HealthProfile();
  @State saved: boolean = false;
  @State thinking: boolean = false;
  @State showKeyDialog: boolean = false;

  aboutToAppear(): void {
    this.pushBot(HealthChatService.greeting());
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
    ConversationService.recordHealth(context, role, text);
  }

  private showToast(text: string): void {
    this.getUIContext().getPromptAction().showToast({ message: text });
  }

  private async saveApiKey(key: string): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    await DeepSeekConfig.setApiKey(context, key);
    this.showKeyDialog = false;
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
      const result = await HealthChatService.handleUserMessageWithDeepSeek(context, text, this.profile);
      if (!result.ok) {
        const toastText: string = result.needKey ?
          context.resourceManager.getStringSync($r('app.string.api_key_missing_toast').id) :
          context.resourceManager.getStringSync($r('app.string.api_key_invalid_toast').id);
        this.showToast(toastText);
        this.showKeyDialog = true;
        return;
      }
      const turn = result.turn;
      if (turn === undefined) {
        return;
      }
      this.profile = turn.profile;
      this.pushBot(turn.reply);
      if (turn.done && !this.saved) {
        this.saved = true;
        await MemoryService.init(context);
        const id: number = await MemoryService.saveHealthProfile(this.profile);
        this.pushBot('已存入记忆库（记录编号 ' + id + '）');
        if (this.profile.history !== '' && this.profile.history !== '无') {
          const advice: string = await DietAdviceService.queryDietAdviceAndStore(context, this.profile.history);
          if (advice !== '') {
            this.pushBot('根据' + this.profile.history + '，为你查询到以下饮食注意事项：' + '\n' + advice);
          } else {
            this.pushBot('未能查询到' + this.profile.history + '的饮食建议，可稍后重试。');
          }
        }
      }
    } finally {
      this.thinking = false;
    }
  }

  build() {
    Stack() {
      Column() {
        Text($r('app.string.chat_title'))
          .fontSize($r('app.float.title_font_size'))
          .fontColor($r('app.color.text_primary'))
          .fontWeight(FontWeight.Bold)
          .padding($r('app.float.page_margin'))
        List({ space: 12 }) {
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