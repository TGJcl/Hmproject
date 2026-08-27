import { common } from '@kit.AbilityKit';
import { ChatBubble } from '../components/ChatBubble';
import { ChatMessage } from '../model/ChatMessage';
import { HealthProfile } from '../model/HealthProfile';
import { HealthChatService } from '../services/HealthChatService';
import { MemoryService } from '../services/MemoryService';
import { ConversationService } from '../services/ConversationService';

@Entry
@Component
struct HealthChat {
  @State messages: Array<ChatMessage> = [];
  @State input: string = '';
  @State profile: HealthProfile = new HealthProfile();
  @State saved: boolean = false;

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

  private async handleSend(): Promise<void> {
    const text: string = this.input.trim();
    if (text === '') {
      return;
    }
    this.input = '';
    const userMsg = new ChatMessage();
    userMsg.role = 'user';
    userMsg.text = text;
    this.messages.push(userMsg);
    this.recordMessage('user', text);

    const turn = HealthChatService.handleUserMessage(text, this.profile);
    this.profile = turn.profile;
    this.pushBot(turn.reply);
    if (turn.done && !this.saved) {
      this.saved = true;
      const context = getContext(this) as common.UIAbilityContext;
      await MemoryService.init(context);
      const id: number = await MemoryService.saveHealthProfile(this.profile);
      this.pushBot('已存入记忆库（记录编号 ' + id + '）');
    }
  }

  build() {
    Column() {
      Text($r('app.string.chat_title'))
        .fontSize($r('app.float.title_font_size'))
        .fontColor($r('app.color.text_primary'))
        .fontWeight(FontWeight.Bold)
        .padding($r('app.float.page_margin'))
            List({ space: 12 }) { // List.space 仅支持 number|string，SDK 限制无法引用 float 资源
        ForEach(this.messages, (msg: ChatMessage, index: number) => {
          ListItem() {
            ChatBubble({ role: msg.role, text: msg.text })
          }
        }, (msg: ChatMessage, index: number) => index.toString())
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
  }
}