import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { DeepSeekConfig } from 'deepseek';
import { ImageLoader, ImagePicker } from 'image';
import { ApiKeyPrompt } from '../components/ApiKeyPrompt';
import { ChatBubble } from '../components/ChatBubble';
import { ChatMessage } from '../model/ChatMessage';
import { AiChatService } from '../services/AiChatService';
import { ConversationService } from '../services/ConversationService';

const AI_GREETING: string = '你好！我是 AI 健康助手，可以结合你的记忆库回答健康问题。';
const IMAGE_TAG: string = '[图片]';

@Entry
@Component
struct AiChat {
  @State messages: Array<ChatMessage> = [];
  @State input: string = '';
  @State thinking: boolean = false;
  @State showKeyDialog: boolean = false;
  @State pendingImageUri: string = '';
  @State pendingImagePixelMap: image.PixelMap | undefined = undefined;

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

  private recordUserMessage(text: string, imageUri: string): void {
    let content: string = text;
    if (imageUri !== '') {
      content = (content === '' ? IMAGE_TAG : content + '\n' + IMAGE_TAG) + imageUri;
    }
    this.recordMessage('user', content);
  }

  private async pickImage(): Promise<void> {
    const uri: string = await ImagePicker.pick();
    if (uri === '') {
      return;
    }
    try {
      const pixelMap: image.PixelMap = await ImageLoader.loadPixelMapFromPath(uri);
      this.pendingImageUri = uri;
      this.pendingImagePixelMap = pixelMap;
    } catch (e) {
      this.pendingImageUri = uri;
      this.pendingImagePixelMap = undefined;
    }
  }

  private clearPendingImage(): void {
    this.pendingImageUri = '';
    this.pendingImagePixelMap = undefined;
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
    const hasImage: boolean = this.pendingImageUri !== '';
    if ((text === '' && !hasImage) || this.thinking) {
      return;
    }
    const imageUri: string = this.pendingImageUri;
    const imagePixelMap: image.PixelMap | undefined = this.pendingImagePixelMap;
    this.input = '';
    this.clearPendingImage();

    const userMsg = new ChatMessage();
    userMsg.role = 'user';
    userMsg.text = text;
    userMsg.imageUri = imageUri;
    userMsg.imagePixelMap = imagePixelMap;
    this.messages.push(userMsg);
    this.recordUserMessage(text, imageUri);

    this.thinking = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const question: string = text === '' ?
        context.resourceManager.getStringSync($r('app.string.img_only_send').id) : text;
      const reply: string = await AiChatService.chat(context, question);
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
              ChatBubble({ role: msg.role, text: msg.text, imagePixelMap: msg.imagePixelMap })
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

        if (this.pendingImageUri !== '') {
          Row() {
            Stack({ alignContent: Alignment.TopEnd }) {
              if (this.pendingImagePixelMap !== undefined) {
                Image(this.pendingImagePixelMap)
                  .width($r('app.float.image_preview_size'))
                  .height($r('app.float.image_preview_size'))
                  .objectFit(ImageFit.Cover)
                  .borderRadius($r('app.float.card_radius'))
              } else {
                Row()
                  .width($r('app.float.image_preview_size'))
                  .height($r('app.float.image_preview_size'))
                  .backgroundColor($r('app.color.card_background'))
                  .borderRadius($r('app.float.card_radius'))
              }
              Text('×')
                .fontSize($r('app.float.small_font_size'))
                .fontColor($r('app.color.button_text'))
                .textAlign(TextAlign.Center)
                .width($r('app.float.image_remove_size'))
                .height($r('app.float.image_remove_size'))
                .backgroundColor($r('app.color.mask_color'))
                .borderRadius($r('app.float.card_radius'))
                .onClick(() => {
                  this.clearPendingImage();
                })
            }
            .width($r('app.float.image_preview_size'))
            .height($r('app.float.image_preview_size'))
          }
          .width('100%')
          .padding({
            left: $r('app.float.page_margin'),
            top: $r('app.float.page_space'),
            bottom: $r('app.float.page_space')
          })
        }

        Row({ space: $r('app.float.page_space') }) {
          Button({ type: ButtonType.Circle }) {
            Text('🖼️')
              .fontSize($r('app.float.text_font_size'))
          }
          .width($r('app.float.input_height'))
          .height($r('app.float.input_height'))
          .backgroundColor($r('app.color.card_background'))
          .onClick(() => {
            this.pickImage();
          })
          TextInput({ placeholder: $r('app.string.ai_input_placeholder'), text: this.input })
            .layoutWeight(1)
            .height($r('app.float.input_height'))
            .fontSize($r('app.float.text_font_size'))
            .backgroundColor($r('app.color.card_background'))
            .borderRadius($r('app.float.card_radius'))
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