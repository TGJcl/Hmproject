@Component
export struct ChatBubble {
  @Prop role: string = 'bot';
  @Prop text: string = '';

  build() {
    Row() {
      Text(this.text)
        .fontSize($r('app.float.text_font_size'))
        .fontColor(this.role === 'user' ? $r('app.color.bubble_user_text') : $r('app.color.text_primary'))
        .padding($r('app.float.card_padding'))
        .backgroundColor(this.role === 'user' ? $r('app.color.bubble_user') : $r('app.color.card_background'))
        .borderRadius($r('app.float.card_radius'))
        .maxWidth($r('app.float.bubble_max_width'))
    }
    .width('100%')
    .justifyContent(this.role === 'user' ? FlexAlign.End : FlexAlign.Start)
  }
}
