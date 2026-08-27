import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { getLogger } from 'logger';

const MAX_SELECT: number = 1;
const LOG = getLogger('ImagePicker');

export class ImagePicker {
  static async pick(): Promise<string> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = MAX_SELECT;
      const result = await picker.select(options);
      if (result.photoUris.length > 0) {
        const uri: string = result.photoUris[0];
        LOG.info('picked image, uri=%{public}s', uri);
        return uri;
      }
      return '';
    } catch (e) {
      LOG.warn('pick image failed: %{public}s', (e as Error).message);
      return '';
    }
  }
}