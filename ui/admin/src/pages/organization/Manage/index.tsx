import {
  ApartmentOutlined,
  ClearOutlined,
  MenuOutlined,
  OrderedListOutlined,
  ShareAltOutlined,
} from '@ant-design/icons';
import type { ActionType, ProColumns } from '@ant-design/pro-components';
import { PageContainer, ProTable } from '@ant-design/pro-components';
import { Avatar, Button, Card, message, Space, Tree } from 'antd';
import type { TreeProps } from 'antd/es/tree';
import { useCallback, useRef, useState } from 'react';
import DepartmentDrawer from './DepartmentDrawer';
import HintModel from './HintModel';
import {
  getNodeChildrenByKey,
  getParentKey,
  useDepartmentDrawer,
  useHintModal,
  useOrganization,
  useUserDrawer,
} from './hook';
import UserDrawer from './UserDrawer';
import { deleteBlock, updateBlock } from '@/services/user';
import OIMAvatar from '@/components/OIMAvatar';
import { getDepartmentUser, searchFull, sortDepartment } from '@/services/organization';
import { useIntl } from '@umijs/max';
import { DrawerType, ModalType } from './data';

const OrganizationList = () => {
  const intl = useIntl();
  const { organization, treeDataHasNum, treeData, refresh } = useOrganization();

  const tableRef = useRef<ActionType>();
  const [userID, setUserID] = useState('');
  const [departmentName, setDepartmentName] = useState('');
  const [departmentIdList, setDepartmentIdList] = useState<string[]>([]);

  const [draggable, setDraggable] = useState(false);

  const [selectedRowKeys, setSelectedRowKeys] = useState<string[]>([]);
  const onSelectChange = (newSelectedRowKeys: React.Key[]) => {
    setSelectedRowKeys(newSelectedRowKeys as string[]);
  };

  const refreshData = useCallback(() => {
    refresh();
    tableRef.current?.reload();
  }, [refresh]);

  const { modalType, setModalType, showModal, changeModal } = useHintModal(
    selectedRowKeys,
    setUserID,
    refreshData,
  );

  const { depDrawerType, setDepDrawerType } = useDepartmentDrawer(refreshData);

  const { userDrawerType, setUserDrawerType, showUserDrawer } = useUserDrawer(setUserID);

  const onSelect: TreeProps['onSelect'] = (selectedKeys, info) => {
    if (!selectedKeys.length) {
      return;
    }
    tableRef.current?.reset?.();
    setSelectedRowKeys([]);
    setDepartmentName((info.node.title as string).split('(')[0]);
    setDepartmentIdList(selectedKeys as string[]);
  };

  const showPosition = (record: API.OrganizationManage.UserInfo) => {
    const hasDepartmentId = departmentIdList.length > 0;
    if (hasDepartmentId) {
      return <span>{record.member.position}</span>;
    }
    const positionList = record.members?.filter((dep) => !!dep.position).map((e) => e.position);
    return <span>{positionList?.join(',')}</span>;
  };

  const onDrop: TreeProps['onDrop'] = async (info) => {
    const departmentID = info.dragNode.key.toString();
    const parentID = info.node.key.toString();
    const currentParent = getParentKey(treeData, departmentID);
    const currentParentChildren = getNodeChildrenByKey(treeData, currentParent).map((e) => e.key);

    if (![currentParent, ...currentParentChildren].includes(parentID) && currentParent !== '') {
      message.warning(intl.formatMessage({ id: 'org.drop.tips' }));
      return;
    }
    if (!info.dropToGap) {
      const nextDepartmentID = getNodeChildrenByKey(treeData, parentID)[0]?.key || '';

      if (departmentID === nextDepartmentID) {
        return;
      }

      try {
        await sortDepartment({
          departmentID,
          nextDepartmentID,
        });
      } catch (error) {
        console.log(error);
      }
    } else {
      const currentParentID = getParentKey(treeData, parentID);
      const nextDepartmentID =
        getNodeChildrenByKey(treeData, currentParentID)?.[info.dropPosition]?.key ?? '';

      if (departmentID === nextDepartmentID) {
        return;
      }

      try {
        await sortDepartment({
          departmentID,
          nextDepartmentID,
        });
      } catch (error) {
        console.log(error);
      }
    }
    refresh();
  };

  const init = () => {
    setSelectedRowKeys([]);
    setDepartmentName('');
    setDepartmentIdList([]);
  };

  const changeBlockHandler = async (disabled: boolean | undefined, userID: string) => {
    try {
      if (disabled) {
        await deleteBlock({ userIDs: [userID] });
      } else {
        await updateBlock({ userID, reason: '' });
      }
      message.success(intl.formatMessage({ id: 'api.success' }));
      refreshData();
    } catch (error) {
      console.log(error);
    }
  };

  const showRemove = (departmentID: string) => {
    return departmentIdList[0] !== '$ungrouped' && departmentID !== '$ungrouped';
  };

  const columns: ProColumns<API.OrganizationManage.UserInfo>[] = [
    {
      title: intl.formatMessage({ id: 'user.faceURL' }),
      key: 'faceURL',
      render: (_, record) => <OIMAvatar src={record.user.faceURL} text={record.user.nickname} />,
      search: false,
      align: 'center',
    },
    {
      title: intl.formatMessage({ id: 'user.nickname' }),
      key: 'nickname',
      dataIndex: 'nickname',
      search: false,
      align: 'center',
      render: (_, record) => <span>{record.user.nickname}</span>,
    },
    {
      title: intl.formatMessage({ id: 'org.user.keyword' }),
      key: 'keyword',
      dataIndex: 'keyword',
      hideInTable: true,
      align: 'center',
      render: (_, record) => <span>{record.user.userID}</span>,
    },
    {
      title: intl.formatMessage({ id: 'user.userID' }),
      key: 'userID',
      dataIndex: 'userID',
      search: false,
      align: 'center',
      render: (_, record) => <span>{record.user.userID}</span>,
    },
    {
      title: intl.formatMessage({ id: 'user.account' }),
      key: 'account',
      dataIndex: 'account',
      search: false,
      align: 'center',
      render: (_, record) => <span>{record.user.account}</span>,
    },
    {
      title: intl.formatMessage({ id: 'user.phoneNumber' }),
      key: 'phoneNumber',
      dataIndex: 'phoneNumber',
      search: false,
      align: 'center',
      render: (_, record) => <span>{record.user.phoneNumber}</span>,
    },
    {
      title: intl.formatMessage({ id: 'user.email' }),
      key: 'email',
      dataIndex: 'email',
      search: false,
      align: 'center',
      render: (_, record) => <span>{record.user.email || '-'}</span>,
    },
    {
      title: intl.formatMessage({ id: 'org.user.position' }),
      key: 'position',
      search: false,
      align: 'center',
      render: (_, record) => <span>{showPosition(record)}</span>,
    },
    {
      title: '',
      key: 'option',
      search: false,
      align: 'center',
      render: (_, record) => (
        <>
          <Button key="edit" type="link" onClick={() => showUserDrawer(record.user.userID ?? '')}>
            {intl.formatMessage({ id: 'user.edit' })}
          </Button>
          <Button
            key="reset"
            type="link"
            onClick={() => showModal(record.user.userID ?? '', ModalType.ResetPassword)}
          >
            {intl.formatMessage({ id: 'user.resetPassword' })}
          </Button>
          {showRemove(record.members?.[0]?.departmentID) && (
            <Button
              key="remove"
              type="link"
              onClick={() => showModal(record.user.userID ?? '', ModalType.RemoveUser)}
            >
              {intl.formatMessage({ id: 'remove' })}
            </Button>
          )}
          <Button
            key="stop"
            type="link"
            onClick={() => changeBlockHandler(record.disabled, record.user.userID)}
          >
            {record.disabled
              ? intl.formatMessage({ id: 'user.deblock' })
              : intl.formatMessage({ id: 'user.block' })}
          </Button>
        </>
      ),
    },
  ];

  const LeftCard = (
    <Card style={{ width: '395px', marginRight: '5px' }} bordered={false}>
      <Space direction="vertical">
        <Space>
          <Button
            key="add"
            icon={<ApartmentOutlined />}
            onClick={() => setDepDrawerType(DrawerType.Create)}
            disabled={departmentIdList[0] === '$ungrouped'}
          >
            {intl.formatMessage({ id: 'org.create' })}
          </Button>
          <Button
            key="sort"
            icon={<OrderedListOutlined />}
            onClick={() => setDraggable(!draggable)}
          >
            {intl.formatMessage({ id: 'org.sort' })}
          </Button>
          <Button
            key="edit"
            icon={<ShareAltOutlined />}
            onClick={() => setDepDrawerType(DrawerType.Edit)}
            disabled={departmentIdList.length <= 0 || departmentIdList[0] === '$ungrouped'}
          >
            {intl.formatMessage({ id: 'org.edit' })}
          </Button>
          <Button
            key="delete"
            icon={<ClearOutlined />}
            onClick={() => setModalType(ModalType.DeleteDepartment)}
            disabled={departmentIdList.length <= 0 || departmentIdList[0] === '$ungrouped'}
          >
            {intl.formatMessage({ id: 'org.delete' })}
          </Button>
        </Space>
        <Space style={{ marginTop: '16px', cursor: 'pointer' }} onClick={() => init()}>
          <Avatar src={<img src={organization?.logoURL} alt="avatar" />} />
          <div>{organization?.name}</div>
        </Space>
        <div
          style={{
            background: 'rgb(230, 247, 255)',
            border: 'rgb(145, 213, 255) 1px solid',
            color: 'rgba(0, 137, 255, 1)',
            display: draggable ? 'flex' : 'none',
          }}
          className="h-10 flex justify-center items-center mt-3"
        >
          {intl.formatMessage({ id: 'org.sort.tips' })}
        </div>
        <Space>
          <Tree
            draggable={{ nodeDraggable: () => draggable, icon: <MenuOutlined /> }}
            selectedKeys={departmentIdList}
            blockNode={true}
            onSelect={onSelect}
            treeData={treeDataHasNum}
            onDrop={onDrop}
          />
        </Space>
      </Space>
    </Card>
  );

  const headerTitle = (
    <Space direction="vertical" size="large">
      <div>{departmentName}</div>
      <Space>
        <Button key="add" type="primary" onClick={() => setUserDrawerType(DrawerType.Create)}>
          {intl.formatMessage({ id: 'org.createUser' })}
        </Button>
        {departmentIdList.length > 0 && (
          <Button key="shuttle" onClick={() => changeModal(ModalType.Shuttle)}>
            {intl.formatMessage({ id: 'org.dep.shuttle' })}
          </Button>
        )}
        <Button key="import" onClick={() => changeModal(ModalType.Import)}>
          {intl.formatMessage({ id: 'org.dep.import' })}
        </Button>
        <Button key="remove" onClick={() => changeModal(ModalType.BatchRemoveUser)}>
          {intl.formatMessage({ id: 'org.dep.remove' })}
        </Button>
      </Space>
    </Space>
  );

  return (
    <>
      <DepartmentDrawer
        type={depDrawerType}
        departmentName={departmentName}
        departmentIdList={departmentIdList || []}
        setDepDrawer={setDepDrawerType}
      />
      <HintModel
        type={modalType}
        userID={userID}
        setModalType={setModalType}
        departmentIdList={departmentIdList || []}
        selectedRowKeys={selectedRowKeys}
        resetSelectedRowKeys={() => setSelectedRowKeys([])}
        init={init}
        refreshData={refreshData}
      />
      <UserDrawer
        type={userDrawerType}
        treeData={treeData}
        userID={userID}
        refreshData={refreshData}
        setUserDrawerType={setUserDrawerType}
        departmentIdList={departmentIdList}
      />
      <PageContainer>
        <ProTable<API.OrganizationManage.UserInfo>
          actionRef={tableRef}
          columns={columns}
          rowKey={(record) => record.user.userID}
          pagination={{
            defaultPageSize: 10,
          }}
          rowSelection={{
            selectedRowKeys,
            onChange: onSelectChange,
          }}
          tableRender={(_, dom) => (
            <div className=" w-full flex flex-1">
              {LeftCard}
              <div className="flex-1">{dom}</div>
            </div>
          )}
          search={{
            labelWidth: 'auto',
          }}
          headerTitle={headerTitle}
          request={async (params = {}) => {
            if (params.keyword) {
              const { data } = await searchFull({
                keyword: params.keyword as string,
                pagination: {
                  pageNumber: params.current as number,
                  showNumber: params.pageSize as number,
                },
              });
              init();
              const tableData = data.users.map((item: any) => ({
                ...item,
                user: item,
                member: item.members[0],
              }));
              return {
                data: tableData ?? [],
                success: true,
                total: data.users.length ?? 0,
              };
            }
            const { data } = await getDepartmentUser(params.departmentIdList);
            return {
              data: data.members ?? [],
              success: true,
              total: data.members?.length ?? 0,
            };
          }}
          params={{ departmentIdList }}
        />
      </PageContainer>
    </>
  );
};

export default OrganizationList;
