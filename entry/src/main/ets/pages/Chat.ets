import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { window, KeyboardAvoidMode } from '@kit.ArkUI';
import { DeepSeekConfig } from 'deepseek';
import { ConversationMessage } from 'conversation';
import { ImageLoader, ImagePicker } from 'image';
import { ApiKeyPrompt } from '../components/ApiKeyPrompt';
import { ChatBubble } from '../components/ChatBubble';
import { ChatMessage } from '../model/ChatMessage';
import { ChatAgent, AgentRunResult, AgentWorkflow } from '../services/ChatAgent';
import { ConversationService } from '../services/ConversationService';
import { FoodRecognitionService } from '../services/FoodRecognitionService';

const IMAGE_TAG: string = '[图片]';

@Entry
@Component
struct Chat {
  @State messages: Array<ChatMessage> = [];
  @State input: string = '';
  @State thinking: boolean = false;
  @State showKeyDialog: boolean = false;
  @State workflow: AgentWorkflow = AgentWorkflow.AI_QA;
  @State pendingImageUri: string = '';
  @State pendingImagePixelMap: image.PixelMap | undefined = undefined;
  @State bottomSafeHeight: number = 0;
  private scroller: Scroller = new Scroller();
  private agent: ChatAgent = new ChatAgent();

  aboutToAppear(): void {
    this.setup();
    this.checkApiKey();
  }

  private async setup(): Promise<void> {
    this.applyKeyboardAvoidMode();
    this.queryBottomSafeHeight();
    await this.loadHistory();
    this.pushBot(this.agent.greeting());
  }

  private applyKeyboardAvoidMode(): void {
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    } catch (e) {
    }
  }

  private async queryBottomSafeHeight(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const win: window.Window = await window.getLastWindow(context);
      const navArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const systemArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const bottomPx: number = Math.max(navArea.bottomRect.height, systemArea.bottomRect.height);
      this.bottomSafeHeight = px2vp(bottomPx);
    } catch (e) {
      this.bottomSafeHeight = 0;
    }
  }

  private async loadHistory(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const aiHistory: Array<ConversationMessage> = await ConversationService.getAiHistory(context);
      const healthHistory: Array<ConversationMessage> = await ConversationService.getHealthHistory(context);
      const merged: Array<ConversationMessage> = aiHistory.concat(healthHistory);
      merged.sort((a, b) => a.createdAt - b.createdAt);
      const restored: Array<ChatMessage> = [];
      for (const hist of merged) {
        restored.push(this.historyToMessage(hist));
      }
      if (restored.length > 0) {
        this.messages = restored;
      }
    } catch (e) {
    }
  }

  private historyToMessage(hist: ConversationMessage): ChatMessage {
    const msg = new ChatMessage();
    msg.role = hist.role;
    const tagIndex: number = hist.text.indexOf(IMAGE_TAG);
    if (tagIndex >= 0) {
      const prefix: string = hist.text.substring(0, tagIndex);
      const uri: string = hist.text.substring(tagIndex + IMAGE_TAG.length);
      msg.text = prefix.trim();
      msg.imageUri = uri.trim();
    } else {
      msg.text = hist.text;
    }
    return msg;
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      if (this.messages.length > 0) {
        this.scroller.scrollToIndex(this.messages.length - 1, true, ScrollAlign.END);
      }
    }, 30);
  }

  private async checkApiKey(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const key: string = await DeepSeekConfig.getApiKey(context);
    if (key === '') {
      this.showKeyDialog = true;
    }
  }

  private pushBot(text: string): void {
    const msg = new ChatMessage();
    msg.role = 'bot';
    msg.text = text;
    this.messages.push(msg);
    this.recordMessage('bot', text);
    this.scrollToBottom();
  }

  private recordMessage(role: string, text: string): void {
    const context = getContext(this) as common.UIAbilityContext;
    if (this.workflow === AgentWorkflow.HEALTH_PROFILE) {
      ConversationService.recordHealth(context, role, text);
    } else {
      ConversationService.recordAi(context, role, text);
    }
  }

  private recordUserMessage(text: string, imageUri: string): void {
    let content: string = text;
    if (imageUri !== '') {
      content = (content === '' ? IMAGE_TAG : content + '\n' + IMAGE_TAG) + imageUri;
    }
    this.recordMessage('user', content);
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
    this.scrollToBottom();

    this.thinking = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      let result: AgentRunResult;
      if (imageUri !== '') {
        // 图片消息：先 YOLO 识别食物，再交给 agent 判断
        let labels: Array<string> = [];
        if (imagePixelMap !== undefined) {
          labels = await FoodRecognitionService.detectFood(context, imagePixelMap);
        }
        result = await this.agent.runWithImage(context, text, labels);
      } else {
        const question: string = text === '' ?
          context.resourceManager.getStringSync($r('app.string.img_only_send').id) : text;
        result = await this.agent.run(context, question);
      }
      this.workflow = result.workflow;
      if (result.needKey || result.apiError) {
        const toastText: string = result.needKey ?
          context.resourceManager.getStringSync($r('app.string.api_key_missing_toast').id) :
          context.resourceManager.getStringSync($r('app.string.api_key_invalid_toast').id);
        this.showToast(toastText);
        this.showKeyDialog = true;
        return;
      }
      for (const reply of result.replies) {
        this.pushBot(reply);
      }
    } catch (e) {
      this.pushBot('请求失败，请检查 API Key 或网络后重试。');
    } finally {
      this.thinking = false;
    }
  }

  build() {
    Stack() {
      Column() {
        List({ space: 12,scroller:this.scroller}) {
          ForEach(this.messages, (msg: ChatMessage, index: number) => {
            ListItem() {
              ChatBubble({ role: msg.role, text: msg.text, imageUri: msg.imageUri,
                imagePixelMap: msg.imagePixelMap })
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
            Text('＋')
              .fontSize($r('app.float.add_segment_font_size'))
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
      .padding({ bottom: this.bottomSafeHeight })

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
