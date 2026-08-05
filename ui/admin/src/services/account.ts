import { ACCOUNT_URL } from '@/config';
import { request } from '@umijs/max';

export async function adminLogin(params: API.AccountManage.AdminLoginParams) {
  return request<{ data: API.AccountManage.Account }>('account/login', {
    method: 'POST',
    data: {
      ...params,
    },
    baseURL: ACCOUNT_URL,
  });
}

export async function adminInfo() {
  return request<{ data: API.AccountManage.AccountInfo }>('account/info', {
    method: 'POST',
    data: {},
    headers: {
      isAccount: true,
    },
    baseURL: ACCOUNT_URL,
  });
}

export async function updateAdminInfo(params: API.AccountManage.UpdateAdminInfoParams) {
  return request('/account/update', {
    method: 'POST',
    data: {
      ...params,
    },
    headers: {
      isAccount: true,
    },
    baseURL: ACCOUNT_URL,
  });
}

export async function changeAdminPassword(params: API.AccountManage.ChangeAdminPwdParams) {
  return request('/account/change_password', {
    method: 'POST',
    data: {
      ...params,
    },
    headers: {
      isAccount: true,
    },
    baseURL: ACCOUNT_URL,
  });
}
