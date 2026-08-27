import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

export class ImageLoader {
  static async loadPixelMapFromPath(path: string): Promise<image.PixelMap> {
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const source = image.createImageSource(file.fd);
      const pixelMap = await source.createPixelMap();
      source.release();
      return pixelMap;
    } finally {
      fileIo.closeSync(file);
    }
  }

  static async loadPixelMapFromRawFile(context: common.Context, fileName: string): Promise<image.PixelMap> {
    const rawFile = await context.resourceManager.getRawFileContent(fileName);
    const arrayBuffer = rawFile.buffer.slice(rawFile.byteOffset, rawFile.byteOffset + rawFile.byteLength) as ArrayBuffer;
    const source = image.createImageSource(arrayBuffer);
    try {
      return await source.createPixelMap();
    } finally {
      source.release();
    }
  }
}
