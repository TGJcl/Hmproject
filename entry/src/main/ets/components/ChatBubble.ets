import { image } from '@kit.ImageKit';

@Component
export struct ChatBubble {
  @Prop role: string = 'bot';
  @Prop text: string = '';
  @Prop imagePixelMap: image.PixelMap | undefined = undefined;

  build() {
    Row() {
      Column() {
        if (this.imagePixelMap !== undefined) {
          Image(this.imagePixelMap)
            .width($r('app.float.image_bubble_size'))
            .height($r('app.float.image_bubble_size'))
            .objectFit(ImageFit.Cover)
            .borderRadius($r('app.float.card_radius'))
            .backgroundColor($r('app.color.card_background'))
        }
        if (this.text !== '') {
          Text(this.text)
            .fontSize($r('app.float.text_font_size'))
            .fontColor(this.role === 'user' ? $r('app.color.bubble_user_text') : $r('app.color.text_primary'))
            .margin({ top: this.imagePixelMap !== undefined ? $r('app.float.card_space') : 0 })
            .padding($r('app.float.card_padding'))
            .backgroundColor(this.role === 'user' ? $r('app.color.bubble_user') : $r('app.color.card_background'))
            .borderRadius($r('app.float.card_radius'))
            .maxWidth($r('app.float.bubble_max_width'))
        }
      }
      .padding(this.imagePixelMap !== undefined ? $r('app.float.card_space') : 0)
    }
    .width('100%')
    .justifyContent(this.role === 'user' ? FlexAlign.End : FlexAlign.Start)
  }
}