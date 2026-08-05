import { ACCOUNT_URL, CHAT_URL } from '@/config';
import { request } from '@umijs/max';

export async function getAllOrganization() {
  return request<{ data: API.OrganizationManage.GetAllOrganizationResult }>(
    '/organization/department/all',
    {
      method: 'POST',
      data: {},
      headers: {
        isAccount: true,
      },
      baseURL: ACCOUNT_URL,
    },
  );
}

export async function getDepartmentUser(departmentIDList: string[]) {
  return request<{ data: API.OrganizationManage.GetDepartmentUserResult }>(
    '/organization/department/expand',
    {
      method: 'POST',
      data: {
        departmentID: departmentIDList[0],
      },
      headers: {
        isAccount: true,
      },
      baseURL: ACCOUNT_URL,
    },
  );
}

export async function createDepartment(params: API.OrganizationManage.CreateDeartmentParams) {
  return request('/organization/department/add', {
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

export async function updateDepartment(params: API.OrganizationManage.UpdateDeartmentParams) {
  return request('/organization/department/update', {
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

export async function deleteDepartment(departmentIDs: string[]) {
  return request('/organization/department/del', {
    method: 'POST',
    data: {
      departmentIDs,
    },
    headers: {
      isAccount: true,
    },
    baseURL: ACCOUNT_URL,
  });
}

export async function removeMember(params: { userID: string; departmentID: string }) {
  return request('/organization/department/member/del', {
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

export async function importByExcel(file: File) {
  const data = new FormData();
  data.append('data', file);
  return request('/organization/import', {
    method: 'POST',
    headers: {
      isAccount: true,
    },
    data,
    baseURL: ACCOUNT_URL,
  });
}

export async function createUser(params: API.OrganizationManage.CreateUserParams) {
  return request('/organization/user/add', {
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

export async function getUserInfo(userIDs: string[]) {
  return request<{ data: API.OrganizationManage.GetUserInfoResult }>(
    '/organization/department/user',
    {
      method: 'POST',
      data: {
        userIDs,
      },
      headers: {
        isAccount: true,
      },
      baseURL: ACCOUNT_URL,
    },
  );
}

export async function updateUserInfo(params: API.OrganizationManage.UpdateUserInfoParams) {
  return request('/organization/user/update', {
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

export async function updateUserDepartment(
  params: API.OrganizationManage.UpdateUserDepartmentParams,
) {
  return request('/organization/department/member/update', {
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

export async function getOrganizationInfo() {
  return request<{ data: API.OrganizationManage.Organization }>('/organization/get', {
    method: 'POST',
    data: {},
    headers: {
      isAccount: true,
    },
    baseURL: ACCOUNT_URL,
  });
}

export async function updateOrganizationInfo(params: API.OrganizationManage.Organization) {
  return request('/organization/set', {
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

export async function getSubDepartment(departmentID: string) {
  return request('/organization/department/expand', {
    method: 'POST',
    data: {
      departmentID,
    },
    headers: {
      isAccount: true,
    },
    baseURL: ACCOUNT_URL,
  });
}

export async function moveUserDepartment(params: API.OrganizationManage.MoveUserDepartmentParams) {
  return request('/organization/department/member/move', {
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

export async function sortDepartment(params: API.OrganizationManage.SortDepartment) {
  return request('/organization/department/sort', {
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

export async function searchFull(params: any) {
  return request('/user/search/full', {
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
