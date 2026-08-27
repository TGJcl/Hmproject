@Component
export struct HealthCard {
  @Prop score: number = 0;
  @Prop recordCount: number = 0;

  build() {
    Column({ space: $r('app.float.card_space') }) {
      Text($r('app.string.health_score_label'))
        .fontSize($r('app.float.text_font_size'))
        .fontColor($r('app.color.text_secondary'))
      Text(`${this.score}`)
        .fontSize($r('app.float.score_font_size'))
        .fontColor($r('app.color.accent'))
        .fontWeight(FontWeight.Bold)
      Text($r('app.string.record_count_label', this.recordCount))
        .fontSize($r('app.float.text_font_size'))
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding($r('app.float.card_padding'))
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
    .alignItems(HorizontalAlign.Start)
  }
}
