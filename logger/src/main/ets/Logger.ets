import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogLevel } from './LogLevel';
import { LogConfig } from './LogConfig';

// hilog 业务域，统一标识本应用日志；命名常量避免魔法数字
const DOMAIN: number = 0x0000;

export class Logger {
  private readonly moduleName: string;

  constructor(moduleName: string) {
    this.moduleName = moduleName;
  }

  debug(message: string, ...args: Array<string | number>): void {
    this.log(LogLevel.DEBUG, message, args);
  }

  info(message: string, ...args: Array<string | number>): void {
    this.log(LogLevel.INFO, message, args);
  }

  warn(message: string, ...args: Array<string | number>): void {
    this.log(LogLevel.WARN, message, args);
  }

  error(message: string, ...args: Array<string | number>): void {
    this.log(LogLevel.ERROR, message, args);
  }

  private log(level: LogLevel, message: string, args: Array<string | number>): void {
    if (level < LogConfig.getEffectiveLevel(this.moduleName)) {
      return;
    }
    const tag: string = "JclHealth" + this.moduleName;
    switch (level) {
      case LogLevel.DEBUG:
        hilog.debug(DOMAIN, tag, message, ...args);
        break;
      case LogLevel.INFO:
        hilog.info(DOMAIN, tag, message, ...args);
        break;
      case LogLevel.WARN:
        hilog.warn(DOMAIN, tag, message, ...args);
        break;
      case LogLevel.ERROR:
        hilog.error(DOMAIN, tag, message, ...args);
        break;
      default:
        break;
    }
  }
}
