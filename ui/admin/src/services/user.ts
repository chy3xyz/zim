import { ACCOUNT_URL, API_URL, CHAT_URL } from '@/config';
import { request } from '@umijs/max';
export async function getUserList(params: API.UserManage.GetUserParams) {
  return request<{ data: API.UserManage.GetUserResult }>('/user/search/full', {
    method: 'POST',
    data: {
      ...params,
      normal: 1,
    },
    headers: {
      isAccount: true,
    },
    baseURL: CHAT_URL,
  });
}

export async function getUserListForIM(params: API.UserManage.GetUserParams) {
  return request<{ data: API.UserManage.GetUserResult }>('/user/get_users', {
    method: 'POST',
    data: {
      ...params,
    },
    baseURL: API_URL,
  });
}

export async function getBlockList(params: API.UserManage.GetUserParams) {
  return request<{ data: API.UserManage.GetUserResult }>('/block/search', {
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

export async function getFriendList(params: API.UserManage.GetFriendsParams) {
  return request<{ data: API.UserManage.GetFriendsResult }>('/friend/get_friend_list', {
    method: 'POST',
    data: {
      ...params,
    },
    baseURL: API_URL,
  });
}

export async function getUsersOnlineStatus(params: API.UserManage.GetUsersOnlineStatusParams) {
  return request<{ data: API.UserManage.GetUsersOnlineStatusResult[] }>(
    '/user/get_users_online_token_detail',
    {
      method: 'POST',
      data: {
        ...params,
      },
      baseURL: API_URL,
    },
  );
}

export async function updateUserInfo(params: API.UserManage.UpdateUserInfoParams) {
  return request('user/update', {
    method: 'POST',
    data: {
      ...params,
    },
    headers: {
      isAccount: true,
    },
    baseURL: CHAT_URL,
  });
}

export async function registerUser(params: API.UserManage.RegisterUserParams) {
  return request('/user/import/json', {
    method: 'POST',
    data: {
      users: [
        {
          ...params.user,
          registerType: 0,
        },
      ],
    },
    headers: {
      isAccount: true,
    },
    baseURL: ACCOUNT_URL,
  });
}

export async function resetUserPassword(params: API.UserManage.ResetUserPasswordParams) {
  return request('/user/password/reset', {
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

export async function updateBlock(params: API.UserManage.UpdateBlockParams) {
  return request('/block/add', {
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

export async function deleteBlock(params: API.UserManage.DeleteBlockParams) {
  return request('/block/del', {
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

export async function deleteFriend(params: API.UserManage.DeleteFriendParams) {
  return request('/friend/delete_friend', {
    method: 'POST',
    data: {
      ...params,
    },
    baseURL: API_URL,
  });
}

export async function forceLogout(params: API.UserManage.KickUserParams) {
  return request('/auth/force_logout', {
    method: 'POST',
    data: {
      ...params,
    },
    baseURL: API_URL,
  });
}

export async function getUserToken(userID: string) {
  return request('/auth/get_user_token', {
    method: 'POST',
    data: {
      userID,
      platformID: 10,
    },
    baseURL: API_URL,
  });
}
