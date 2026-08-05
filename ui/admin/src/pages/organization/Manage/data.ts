export type TreeNode = {
  key: string;
  title: string;
  memberNum?: number;
  children: TreeNode[];
};

export enum DrawerType {
  Create = 'create',
  Edit = 'edit',
  Null = 'undefined',
}

export enum ModalType {
  DeleteDepartment = 'deleteDepartment',
  ResetPassword = 'resetPassword',
  RemoveUser = 'removeUser',
  BatchRemoveUser = 'batchRemoveUser',
  Import = 'import',
  Shuttle = 'shuttle',
  Null = 'undefined',
}

export type MoveUserDepartment = {
  currentDepartmentID?: string;
  departmentID: string;
  position?: string;
  userID: string;
};
