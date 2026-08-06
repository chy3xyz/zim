import type { RequestOptions } from '@@/plugin-request/request';
import type { RequestConfig } from '@umijs/max';
import { history } from '@umijs/max';
import { message } from 'antd';
import { v4 } from 'uuid';

interface ResponseStructure {
  data: any;
  errDlt?: string;
  errCode?: number;
}

/**
 * @name 错误处理
 * pro 自带的错误处理， 可以在这里做自己的改动
 * @doc https://umijs.org/docs/max/request#配置
 */
export const errorConfig: RequestConfig = {
  errorConfig: {
    // 错误抛出
    errorThrower: (res) => {
      const { data, errCode, errDlt } = res as unknown as ResponseStructure;
      if (data?.errCode !== 0) {
        const error: any = new Error(errDlt);
        error.info = { errCode, errDlt, data };
        throw error;
      }
    },
    // 错误接收及处理
    errorHandler: (error: any, opts: any) => {
      if (opts?.skipErrorHandler) throw error;
      return console.log(error);
    },
  },

  // 请求拦截器
  requestInterceptors: [
    (config: RequestOptions) => {
      const authHeader = {
        ...config.headers,
        token:
          localStorage.getItem(config.headers?.isAccount ? 'IMAccountToken' : 'IMAdminToken') ?? '',
        operationID: v4(),
      };
      config.headers = authHeader;
      return { ...config };
    },
  ],

  // 响应拦截器
  responseInterceptors: [
    (response) => {
      const { data } = response as unknown as ResponseStructure;

      const tokenErrCode = [1501, 1502, 1503, 1504, 1505, 1506, 1507];

      if (data?.errDlt?.includes('token')) {
        localStorage.removeItem('IMAccountToken');
        localStorage.removeItem('IMAdminToken');
        history.push('/login');
        return Promise.reject(data.errMsg);
      }

      if (tokenErrCode.includes(data?.errCode)) {
        localStorage.removeItem('IMAccountToken');
        localStorage.removeItem('IMAdminToken');
        history.push('/login');
        // message.error('login has expired. Please log in again.');
        return Promise.reject(data.errMsg);
      }

      if (data?.errCode !== 0) {
        message.error(data.errMsg);
        return Promise.reject(data.errMsg);
      }

      return response;
    },
  ],
};
