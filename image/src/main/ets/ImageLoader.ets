import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

export class ImageLoader {
  static async loadPixelMapFromPath(path: string): Promise<image.PixelMap> {
    let file: fileIo.File;
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    } catch (e) {
      throw new Error((e as Error).message);
    }
    try {
      let source: image.ImageSource;
      try {
        source = image.createImageSource(file.fd);
      } catch (e) {
        throw new Error((e as Error).message);
      }
      try {
        // YOLO native 预处理按 RGBA_8888 读取，显式转换避免设备返回 BGRA 或其他格式。
        const pixelMap = await source.createPixelMap({
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888
        });
        return pixelMap;
      } catch (e) {
        throw new Error((e as Error).message);
      } finally {
        source.release();
      }
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
