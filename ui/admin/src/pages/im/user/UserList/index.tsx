import OIMAvatar from '@/components/OIMAvatar';
import { getUserListForIM, getUsersOnlineStatus } from '@/services/user';
import type { ActionType, ProColumns } from '@ant-design/pro-components';
import { PageContainer, ProTable } from '@ant-design/pro-components';
import { history, useIntl } from '@umijs/max';
import { Space } from 'antd';
import { useMemo, useRef, useState } from 'react';
import ForcedOfflineDrawer from './ForcedOfflineDrawer';
import PreviewMessageModal from './PreviewMessageModal';
import { switchOnline } from '@/utils/common';

export type DrawerOptions = {
  visible: boolean;
  selectUser: API.UserManage.User | undefined;
};

const UserList = () => {
  const intl = useIntl();
  const actionRef = useRef<ActionType>();
  const [drawerOptions, setDrawerOptions] = useState<DrawerOptions>({
    visible: false,
    selectUser: undefined,
  });

  const [selectedUserID, setSelectUserID] = useState('');

  const toRelationListHandler = (userId: string) => {
    history.push('/im/user/relation_list?userID=' + userId);
  };

  const columns: ProColumns<API.UserManage.User>[] = useMemo(
    () => [
      {
        key: 'index',
        dataIndex: 'index',
        valueType: 'indexBorder',
      },
      {
        title: intl.formatMessage({ id: 'user.faceURL' }),
        dataIndex: 'faceURL',
        key: 'faceURL',
        hideInSearch: true,
        align: 'center',
        render: (_, record) => <OIMAvatar src={record.faceURL} text={record.nickname} />,
      },
      {
        title: intl.formatMessage({ id: 'user.nickname' }),
        key: 'nickname',
        dataIndex: 'nickname',
        align: 'center',
      },
      {
        title: intl.formatMessage({ id: 'user.userID' }),
        key: 'userID',
        dataIndex: 'userID',
        align: 'center',
      },
      {
        title: intl.formatMessage({ id: 'user.online' }),
        key: 'onlineStr',
        dataIndex: 'onlineStr',
        hideInSearch: true,
        align: 'center',
      },
      {
        title: '',
        valueType: 'option',
        key: 'option',
        align: 'center',
        render: (_, record) => (
          <Space>
            <a
              key={'onlineStr'}
              onClick={() => {
                if (record.onlineStr?.length) {
                  setDrawerOptions({
                    visible: true,
                    selectUser: record,
                  });
                }
              }}
              style={{
                pointerEvents: record.onlineStr?.length ? 'auto' : 'none',
                color: record.onlineStr?.length ? '#1677ff' : '#ccc',
                cursor: record.onlineStr?.length ? 'pointer' : 'not-allowed',
              }}
            >
              {intl.formatMessage({ id: 'user.forcedOffline' })}
            </a>
            <a key="friend" onClick={() => toRelationListHandler(record.userID)}>
              {intl.formatMessage({ id: 'user.relation' })}
            </a>
            <a key="msg" onClick={() => setSelectUserID(record.userID)}>
              {intl.formatMessage({ id: 'user.conversation' })}
            </a>
          </Space>
        ),
      },
    ],
    [],
  );

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

  return (
    <PageContainer>
      <ForcedOfflineDrawer
        drawerOptions={drawerOptions}
        reload={() => actionRef.current?.reload()}
        setDrawerOptions={setDrawerOptions}
      />
      {selectedUserID && (
        <PreviewMessageModal userID={selectedUserID} closeModal={() => setSelectUserID('')} />
      )}
      <ProTable<API.UserManage.User>
        columns={columns}
        actionRef={actionRef}
        rowKey={(record) => record.userID}
        request={async (params = {}) => {
          const { data } = await getUserListForIM({
            ...params,
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
            total: data.total,
          };
        }}
        pagination={{
          defaultPageSize: 10,
          showQuickJumper: true,
        }}
      />
    </PageContainer>
  );
};

export default UserList;
