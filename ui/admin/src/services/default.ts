import { ACCOUNT_URL } from '@/config';
import { request } from '@umijs/max';

export enum InvitationCodeStatus {
  All = 1,
  UnUsed = 2,
  Used = 3,
}

export async function getDefaultGroup(params: API.DefaultManage.GetDefaultGroupParams) {
  return request<{ data: API.DefaultManage.GetDefaultGroupResult }>('/default/group/search', {
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

export async function addDefaultGroup(groupIDs: string[]) {
  return request('/default/group/add', {
    method: 'POST',
    data: {
      groupIDs,
    },
    headers: {
      isAccount: true,
    },
    baseURL: ACCOUNT_URL,
  });
}

export async function removeDefaultGroup(groupIDs: string[]) {
  return request('/default/group/del', {
    method: 'POST',
    data: {
      groupIDs,
    },
    headers: {
      isAccount: true,
    },
    baseURL: ACCOUNT_URL,
  });
}

export async function generateInvitationCode(num = 1, len = 8) {
  return request('/invitation_code/gen', {
    method: 'POST',
    data: {
      num,
      len,
      chars: 'ABCDEFGHIJKLM0123456789',
    },
    headers: {
      isAccount: true,
    },
    baseURL: ACCOUNT_URL,
  });
}

export async function getDefaultFriends(params: API.DefaultManage.GetDefaultFriendsParams) {
  return request<{ data: API.DefaultManage.GetDefaultFriendsResult }>('/default/user/search', {
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

export async function addDefaultFriends(userIDs: string[]) {
  return request('/default/user/add', {
    method: 'POST',
    data: {
      userIDs,
    },
    headers: {
      isAccount: true,
    },
    baseURL: ACCOUNT_URL,
  });
}

export async function removeDefaultFriends(userIDs: string[]) {
  return request('/default/user/del', {
    method: 'POST',
    data: {
      userIDs,
    },
    headers: {
      isAccount: true,
    },
    baseURL: ACCOUNT_URL,
  });
}
