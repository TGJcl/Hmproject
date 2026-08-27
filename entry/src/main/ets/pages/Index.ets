import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { router } from '@kit.ArkUI';
import { DeepSeekConfig } from 'deepseek';
import { ApiKeyPrompt } from '../components/ApiKeyPrompt';
import { HealthCard } from '../components/HealthCard';
import { HealthSummary } from '../model/HealthSummary';
import { HealthService } from '../services/HealthService';

const SAMPLE_RAW_IMAGE: string = 'sample_image.png';
const SAMPLE_VALUE: number = 92;

@Entry
@Component
struct Index {
  @State summary: HealthSummary = new HealthSummary();
  @State dbStatus: string = '';
  @State remoteStatus: string = '';
  @State imageStatus: string = '';
  @State pixelMap: image.PixelMap | undefined = undefined;
  @State showKeyDialog: boolean = false;

  aboutToAppear(): void {
    this.checkApiKey();
  }

  private async checkApiKey(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const key: string = await DeepSeekConfig.getApiKey(context);
    if (key === '') {
      this.showKeyDialog = true;
    }
  }

  private async saveApiKey(key: string): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    await DeepSeekConfig.setApiKey(context, key);
    this.showKeyDialog = false;
  }

  private closeApiKeyDialog(): void {
    this.showKeyDialog = false;
  }

  private getString(res: Resource): string {
    const context = getContext(this) as common.UIAbilityContext;
    return context.resourceManager.getStringSync(res.id);
  }

  private getStringWithArgs(res: Resource, count: number): string {
    const context = getContext(this) as common.UIAbilityContext;
    return context.resourceManager.getStringSync(res.id, count);
  }

  private async handleInitDatabase(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await HealthService.init(context);
      await HealthService.insertSample(SAMPLE_VALUE);
      this.summary = await HealthService.loadSummary();
      this.dbStatus = this.getStringWithArgs($r('app.string.db_ready'), this.summary.recordCount);
    } catch (e) {
      this.dbStatus = this.getString($r('app.string.db_error'));
    }
  }

  private async handleFetchRemote(): Promise<void> {
    try {
      await HealthService.fetchRemoteData();
      this.remoteStatus = this.getString($r('app.string.remote_ok'));
    } catch (e) {
      this.remoteStatus = this.getString($r('app.string.remote_error'));
    }
  }

  private async handleLoadImage(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.pixelMap = await HealthService.loadSampleImage(context);
      this.imageStatus = this.getString($r('app.string.image_loaded'));
    } catch (e) {
      this.imageStatus = this.getString($r('app.string.image_error'));
    }
  }

  private openHealthChat(): void {
    router.pushUrl({ url: 'pages/HealthChat' });
  }

  private openAiChat(): void {
    router.pushUrl({ url: 'pages/AiChat' });
  }

  build() {
    Stack() {
      Column({ space: $r('app.float.page_space') }) {
        Text($r('app.string.app_title'))
          .fontSize($r('app.float.title_font_size'))
          .fontColor($r('app.color.text_primary'))
          .fontWeight(FontWeight.Bold)
        HealthCard({ score: this.summary.score, recordCount: this.summary.recordCount })
        Text(this.dbStatus)
          .fontSize($r('app.float.text_font_size'))
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Start)
        Text(this.remoteStatus)
          .fontSize($r('app.float.text_font_size'))
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Start)
        Text(this.imageStatus)
          .fontSize($r('app.float.text_font_size'))
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Start)
        if (this.pixelMap !== undefined) {
          Image(this.pixelMap)
            .width($r('app.float.image_size'))
            .height($r('app.float.image_size'))
            .borderRadius($r('app.float.card_radius'))
        }
        Button($r('app.string.btn_open_chat'))
          .width($r('app.float.button_width'))
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.button_background'))
          .fontColor($r('app.color.button_text'))
          .onClick(() => {
            this.openHealthChat();
          })
        Button($r('app.string.btn_open_ai'))
          .width($r('app.float.button_width'))
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.button_background'))
          .fontColor($r('app.color.button_text'))
          .onClick(() => {
            this.openAiChat();
          })
        Button($r('app.string.btn_init_db'))
          .width($r('app.float.button_width'))
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.button_background'))
          .fontColor($r('app.color.button_text'))
          .onClick(() => {
            this.handleInitDatabase();
          })
        Button($r('app.string.btn_fetch_remote'))
          .width($r('app.float.button_width'))
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.button_background'))
          .fontColor($r('app.color.button_text'))
          .onClick(() => {
            this.handleFetchRemote();
          })
        Button($r('app.string.btn_load_image'))
          .width($r('app.float.button_width'))
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.button_background'))
          .fontColor($r('app.color.button_text'))
          .onClick(() => {
            this.handleLoadImage();
          })
      }
      .width('100%')
      .height('100%')
      .padding($r('app.float.page_margin'))
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
