import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { getLogger } from 'logger';

const LOG = getLogger('EntryAbility');

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    LOG.info('Ability onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Chat', (err) => {
      if (err.code) {
        LOG.error('Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      LOG.info('Succeeded in loading the content.');
    });
  }
}

