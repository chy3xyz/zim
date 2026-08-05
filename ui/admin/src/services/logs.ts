import { API_URL } from '@/config';
import { request } from '@umijs/max';

export async function getLogs(params: API.LogManage.SearchLogs) {
  return request('/third/logs/search', {
    method: 'POST',
    data: {
      ...params,
    },
    baseURL: API_URL,
  });
}

export function deleteLog(logIDs: string[]) {
  return request('/third/logs/delete', {
    method: 'POST',
    data: {
      logIDs,
    },
    baseURL: API_URL,
  });
}
