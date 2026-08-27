import { image } from '@kit.ImageKit';

export class ChatMessage {
  role: string = '';
  text: string = '';
  imageUri: string = '';
  imagePixelMap: image.PixelMap | undefined = undefined;
}