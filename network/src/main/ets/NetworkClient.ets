import { http } from '@kit.NetworkKit';

const CONNECT_TIMEOUT: number = 10000;
const READ_TIMEOUT: number = 10000;
const HTTP_OK: number = 200;

export class NetworkClient {
  static async get(url: string): Promise<string> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: CONNECT_TIMEOUT,
        readTimeout: READ_TIMEOUT
      });
      if (response.responseCode !== HTTP_OK) {
        throw new Error('HTTP ' + response.responseCode.toString());
      }
      return response.result as string;
    } finally {
      request.destroy();
    }
  }

  static async postJson(url: string, headers: Record<string, string>, body: object, timeout: number = READ_TIMEOUT): Promise<string> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: timeout,
        readTimeout: timeout
      });
      if (response.responseCode !== HTTP_OK) {
        throw new Error('HTTP ' + response.responseCode.toString() + ' ' + response.result);
      }
      return response.result as string;
    } finally {
      request.destroy();
    }
  }
}
