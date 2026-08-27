import { LogLevel } from './LogLevel';

const DEFAULT_LEVEL: LogLevel = LogLevel.DEBUG;

export class LogConfig {
  private static globalLevel: LogLevel = DEFAULT_LEVEL;
  private static moduleLevels: Map<string, LogLevel> = new Map();

  static setGlobalLevel(level: LogLevel): void {
    LogConfig.globalLevel = level;
  }

  static setModuleLevel(moduleName: string, level: LogLevel): void {
    LogConfig.moduleLevels.set(moduleName, level);
  }

  static getEffectiveLevel(moduleName: string): LogLevel {
    const moduleLevel = LogConfig.moduleLevels.get(moduleName);
    if (moduleLevel !== undefined) {
      return moduleLevel;
    }
    return LogConfig.globalLevel;
  }
}
