@Component
export struct ApiKeyPrompt {
  @Prop show: boolean = false;
  @State input: string = '';
  onSave: (key: string) => void = () => {};
  onClose: () => void = () => {};

  build() {
    if (this.show) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.mask_color'))
          .onClick(() => {
            this.onClose();
          })
        Column({ space: $r('app.float.page_space') }) {
          Text($r('app.string.api_key_title'))
            .fontSize($r('app.float.title_font_size'))
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Bold)
          Text($r('app.string.api_key_hint'))
            .fontSize($r('app.float.text_font_size'))
            .fontColor($r('app.color.text_secondary'))
          TextInput({ placeholder: $r('app.string.api_key_placeholder'), text: this.input })
            .height($r('app.float.input_height'))
            .fontSize($r('app.float.text_font_size'))
            .onChange((value: string) => {
              this.input = value;
            })
          Row({ space: $r('app.float.page_space') }) {
            Button($r('app.string.btn_cancel'))
              .layoutWeight(1)
              .height($r('app.float.button_height'))
              .backgroundColor($r('app.color.card_background'))
              .fontColor($r('app.color.text_primary'))
              .onClick(() => {
                this.input = '';
                this.onClose();
              })
            Button($r('app.string.btn_save'))
              .layoutWeight(1)
              .height($r('app.float.button_height'))
              .backgroundColor($r('app.color.button_background'))
              .fontColor($r('app.color.button_text'))
              .onClick(() => {
                const key: string = this.input.trim();
                if (key !== '') {
                  this.onSave(key);
                  this.input = '';
                }
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding($r('app.float.card_padding'))
        .borderRadius($r('app.float.card_radius'))
        .backgroundColor($r('app.color.card_background'))
      }
      .width('100%')
      .height('100%')
    }
  }
}
