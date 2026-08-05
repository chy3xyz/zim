import { ActionType, PageContainer, ProColumns, ProTable } from '@ant-design/pro-components';
import { Button, Popconfirm, Space, message } from 'antd';
import { useMemo, useRef, useState } from 'react';
import { getUserList, getUsersOnlineStatus, updateBlock } from '@/services/user';
import OIMAvatar from '@/components/OIMAvatar';
import ResetModal from './ResetModal';
import UserActionDrawer from './UserActionDrawer';
import { useIntl } from '@umijs/max';
import { switchOnline } from '@/utils/common';

const UserList = () => {
  const intl = useIntl();
  const actionRef = useRef<ActionType>();
  const [resetUserID, setResetUserID] = useState<string | null>(null);

  const [openAction, setOpenAction] = useState(false);
  const [currentUser, setCurrentUser] = useState<API.UserManage.User | null>(null);

  const reloadTable = () => actionRef.current?.reload();

  const updateOpenAction = (record: API.UserManage.User | null) => {
    setCurrentUser(record);
    setOpenAction(true);
  };

  const closeModal = () => {
    setCurrentUser(null);
    setOpenAction(false);
  };

  const blockUser = async (userID: string) => {
    await updateBlock({ userID, reason: '' });
    reloadTable();
    message.success(intl.formatMessage({ id: 'api.success' }));
  };

  const attachInfo = async (userList: API.UserManage.User[]) => {
    try {
      const { data } = await getUsersOnlineStatus({
        userIDs: userList.map((user) => user.userID),
      });
      (data ?? []).forEach((status) => {
        userList.find((user) => {
          if (user.userID === status.userID) {
            user.onlineStr = switchOnline(status.singlePlatformToken);
          }
          return null;
        });
      });
    } catch (error) {
      console.log(error);
    }
  };

  const columns: ProColumns<API.UserManage.User>[] = useMemo(
    () => [
      {
        key: 'index',
        dataIndex: 'index',
        valueType: 'indexBorder',
      },
      {
        title: intl.formatMessage({ id: 'user.keyword' }),
        key: 'keyword',
        dataIndex: 'keyword',
        editable: false,
        hideInTable: true,
        align: 'center',
      },
      {
        title: intl.formatMessage({ id: 'user.faceURL' }),
        dataIndex: 'faceURL',
        valueType: 'avatar',
        key: 'faceURL',
        hideInSearch: true,
        editable: false,
        align: 'center',
        render: (_, record) => <OIMAvatar src={record.faceURL} text={record.nickname} />,
      },
      {
        title: intl.formatMessage({ id: 'user.nickname' }),
        key: 'nickname',
        dataIndex: 'nickname',
        hideInSearch: true,
        align: 'center',
      },
      {
        title: intl.formatMessage({ id: 'user.userID' }),
        key: 'userID',
        dataIndex: 'userID',
        hideInSearch: true,
        editable: false,
        align: 'center',
      },
      {
        title: intl.formatMessage({ id: 'user.gender' }),
        key: 'gender',
        dataIndex: 'gender',
        hideInSearch: true,
        valueType: 'select',
        align: 'center',
        request: async () => {
          return [
            {
              label: intl.formatMessage({ id: 'user.gender.secrecy' }),
              value: 0,
            },
            {
              label: intl.formatMessage({ id: 'user.gender.man' }),
              value: 1,
            },
            {
              label: intl.formatMessage({ id: 'user.gender.woman' }),
              value: 2,
            },
          ];
        },
      },
      {
        title: intl.formatMessage({ id: 'user.phoneNumber' }),
        key: 'phoneNumber',
        dataIndex: 'phoneNumber',
        hideInSearch: true,
        editable: false,
        align: 'center',
      },
      {
        title: intl.formatMessage({ id: 'user.email' }),
        key: 'email',
        dataIndex: 'email',
        hideInSearch: true,
        editable: false,
        align: 'center',
      },
      {
        title: intl.formatMessage({ id: 'user.online' }),
        key: 'onlineStr',
        dataIndex: 'onlineStr',
        hideInSearch: true,
        editable: false,
        align: 'center',
      },
      {
        title: '',
        valueType: 'option',
        key: 'option',
        align: 'center',
        render: (_, user) => {
          return (
            <Space>
              <a key="edit" onClick={() => updateOpenAction(user)}>
                {intl.formatMessage({ id: 'user.edit' })}
              </a>
              <a key="reset" onClick={() => setResetUserID(user.userID)}>
                {intl.formatMessage({ id: 'user.resetPassword' })}
              </a>
              <Popconfirm
                key="block"
                title={intl.formatMessage({ id: 'user.confirmBlock' })}
                onConfirm={() => blockUser(user.userID)}
              >
                <a>{intl.formatMessage({ id: 'user.block' })}</a>
              </Popconfirm>
            </Space>
          );
        },
      },
    ],
    [],
  );

  return (
    <PageContainer>
      <ResetModal userID={resetUserID} setUserID={setResetUserID} />
      <UserActionDrawer
        openAction={openAction}
        closeModal={closeModal}
        currentUser={currentUser}
        reloadTable={reloadTable}
      />
      <ProTable<API.UserManage.User>
        columns={columns}
        actionRef={actionRef}
        rowKey="userID"
        request={async (params = {}) => {
          const { data } = await getUserList({
            keyword: params.keyword,
            pagination: {
              pageNumber: params.current as number,
              showNumber: params.pageSize as number,
            },
          });
          const tmpData = data.users ?? [];
          await attachInfo(tmpData);
          return {
            data: tmpData,
            success: true,
            total: data.total ?? 0,
          };
        }}
        search={{
          labelWidth: 'auto',
        }}
        pagination={{
          defaultPageSize: 10,
          showQuickJumper: true,
        }}
        toolbar={{
          actions: [
            <Button key="key" type="primary" onClick={() => updateOpenAction(null)}>
              {intl.formatMessage({ id: 'user.createUser' })}
            </Button>,
          ],
          settings: [],
        }}
      />
    </PageContainer>
  );
};

export default UserList;
