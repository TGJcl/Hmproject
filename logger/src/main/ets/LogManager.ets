import { LogLevel } from './LogLevel';
import { LogConfig } from './LogConfig';
import { Logger } from './Logger';

export class LogManager {
  private static loggers: Map<string, Logger> = new Map();

  static setGlobalLevel(level: LogLevel): void {
    LogConfig.setGlobalLevel(level);
  }

  static setModuleLevel(moduleName: string, level: LogLevel): void {
    LogConfig.setModuleLevel(moduleName, level);
  }

  static getLogger(moduleName: string): Logger {
    let logger = LogManager.loggers.get(moduleName);
    if (logger === undefined) {
      logger = new Logger(moduleName);
      LogManager.loggers.set(moduleName, logger);
    }
    return logger;
  }
}

export function getLogger(moduleName: string): Logger {
  return LogManager.getLogger(moduleName);
}
