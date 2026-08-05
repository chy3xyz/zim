import { message } from 'antd';
import { useCallback, useEffect, useState } from 'react';
import { DrawerType, ModalType, TreeNode } from './data';
import { getAllOrganization, getOrganizationInfo } from '@/services/organization';
import { useIntl } from '@umijs/max';

const convertToTreeData = (data: API.OrganizationManage.DepartmentList[], showNum: boolean) => {
  const result = [];
  for (let i = 0; i < data.length; i++) {
    const { department, subdepartments } = data[i];
    const { departmentID, name, memberNum, order } = department;
    const children: TreeNode[] = subdepartments ? convertToTreeData(subdepartments, showNum) : [];
    if (!showNum && order < 0) {
      continue;
    }
    result.push({
      key: departmentID,
      title: `${name}${memberNum && showNum ? `(${memberNum})` : ''}`,
      children,
      memberNum,
    });
  }
  return result;
};

export const getParentKey = (
  data: TreeNode[],
  targetKey: string | number,
  parentKey = '',
): string => {
  for (let i = 0; i < data.length; i++) {
    const node = data[i];
    if (node.key === String(targetKey)) {
      return parentKey;
    } else if (node.children && node.children.length > 0) {
      const result = getParentKey(node.children, String(targetKey), node.key);
      if (result) {
        return result;
      }
    }
  }
  return '';
};

export const getNodeChildrenByKey = (data: TreeNode[], targetKey: string): TreeNode[] | [] => {
  for (let i = 0; i < data.length; i++) {
    const node = data[i];
    if (node.key === targetKey) {
      return node.children;
    } else if (node.children && node.children.length > 0) {
      const result = getNodeChildrenByKey(node.children, targetKey);
      if (result.length > 0) {
        return result;
      }
    }
  }
  return [];
};

export const useOrganization = () => {
  const [departmentList, setDepartmentList] = useState<API.OrganizationManage.DepartmentList[]>();
  const [organization, setOrganization] = useState<API.OrganizationManage.Organization>();

  const getOrganization = async () => {
    try {
      const { data } = await getAllOrganization();
      const { data: orgData } = await getOrganizationInfo();
      setDepartmentList(data.departments);
      setOrganization(orgData);
    } catch (error) {
      console.log(error);
    }
  };

  const refresh = useCallback(() => {
    getOrganization();
  }, []);

  useEffect(() => {
    getOrganization();
  }, []);

  const treeData = convertToTreeData(departmentList ?? [], false);
  const treeDataHasNum = convertToTreeData(departmentList ?? [], true);

  return { organization, departmentList, treeData, treeDataHasNum, refresh };
};

export const useHintModal = (
  selectedRowKeys: string[],
  setUserID: (id: string) => void,
  refreshData: () => void,
) => {
  const intl = useIntl();
  const [modalType, setModalType] = useState<ModalType>(ModalType.Null);

  useEffect(() => {
    if (!modalType) {
      refreshData();
    }
  }, [modalType, refreshData]);

  const showModal = (id: string, type: ModalType) => {
    setUserID(id);
    setModalType(type);
  };

  const changeModal = (type: ModalType) => {
    if (
      (type === ModalType.Shuttle ||
        type === ModalType.RemoveUser ||
        type === ModalType.BatchRemoveUser) &&
      selectedRowKeys.length === 0
    ) {
      message.error(intl.formatMessage({ id: 'org.user.select.tips' }));
      return;
    }
    setModalType(type);
  };

  return { modalType, setModalType, showModal, changeModal };
};

export const useUserDrawer = (setUserID: (id: string) => void) => {
  const [userDrawerType, setUserDrawerType] = useState<DrawerType>(DrawerType.Null);

  const showUserDrawer = (id: string) => {
    setUserID(id);
    setUserDrawerType(DrawerType.Edit);
  };

  return { userDrawerType, setUserDrawerType, showUserDrawer };
};

export const useDepartmentDrawer = (refreshData: () => void) => {
  const [depDrawerType, setDepDrawerType] = useState<DrawerType>(DrawerType.Null);

  useEffect(() => {
    if (depDrawerType === DrawerType.Null) {
      refreshData();
    }
  }, [depDrawerType, refreshData]);

  return { depDrawerType, setDepDrawerType };
};
