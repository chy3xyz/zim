import { ACCOUNT_URL } from '@/config';
import { request } from '@umijs/max';

export async function addVersion(params: API.AppManage.AddVersionParams) {
  return request('/application/add_version', {
    method: 'POST',
    data: params,
    headers: {
      isAccount: true,
    },
    baseURL: ACCOUNT_URL,
  });
}

export async function deleteVersion(params: API.AppManage.DeleteVersionParams) {
  return request('/application/delete_version', {
    method: 'POST',
    data: params,
    headers: {
      isAccount: true,
    },
    baseURL: ACCOUNT_URL,
  });
}

export async function updateVersion(params: API.AppManage.Version) {
  return request('/application/update_version', {
    method: 'POST',
    data: params,
    headers: {
      isAccount: true,
    },
    baseURL: ACCOUNT_URL,
  });
}

export async function getVersionList(params: API.AppManage.GetVersionListParams) {
  return request<{ data: API.AppManage.GetVersionListResult }>('/application/page_versions', {
    method: 'POST',
    data: params,
    headers: {
      isAccount: true,
    },
    baseURL: ACCOUNT_URL,
  });
}

export async function allowRegister(allowRegister: boolean) {
  return request('/user/allow_register/set', {
    method: 'POST',
    data: {
      allowRegister,
    },
    headers: {
      isAccount: true,
    },
    baseURL: ACCOUNT_URL,
  });
}

export async function getAllowRegister() {
  return request<{ data: API.AppManage.GetAllowRegisterResult }>('/user/allow_register/get', {
    method: 'POST',
    data: {},
    headers: {
      isAccount: true,
    },
    baseURL: ACCOUNT_URL,
  });
}
