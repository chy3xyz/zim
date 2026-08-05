import OIMAvatar from '@/components/OIMAvatar';
import { GroupStatus } from '@/constants/enum';
import { cancelMuteGroup, dismissGroup, getGroupList, muteGroup } from '@/services/group';
import type { ActionType, ProColumns } from '@ant-design/pro-components';
import { PageContainer, ProTable } from '@ant-design/pro-components';
import { history, useIntl } from '@umijs/max';
import { Button, message, Popconfirm, Space } from 'antd';
import moment from 'moment';
import { useMemo, useRef, useState } from 'react';
import GroupActionDrawer, { DrawerOptions } from './GroupActionDrawer';

const GroupList = () => {
  const intl = useIntl();
  const actionRef = useRef<ActionType>();

  const [drawerOptions, setDrawerOptions] = useState<DrawerOptions>({
    open: false,
    opType: 'create',
  });

  const reload = () => {
    actionRef.current?.reload();
  };

  const toGroupMember = (groupInfo: API.GroupManage.GroupInfo) => {
    history.push('/im/group/group_member', {
      groupInfo,
    });
  };

  const muteGroupHandler = async (isMuted: boolean, groupID: string) => {
    const func = isMuted ? cancelMuteGroup : muteGroup;
    try {
      await func(groupID);
      message.success(intl.formatMessage({ id: 'api.success' }));
      reload();
    } catch (error) {
      console.log(error);
    }
  };

  const dismissGroupHandler = async (groupID: string) => {
    try {
      await dismissGroup(groupID);
      message.success(intl.formatMessage({ id: 'api.success' }));
      reload();
    } catch (error) {
      console.log(error);
    }
  };

  const closeDrawer = () => {
    setDrawerOptions({
      open: false,
      opType: 'create',
      groupInfo: undefined,
    });
  };

  const openDrawer = (opType: 'create' | 'edit', groupInfo?: API.GroupManage.GroupInfo) => {
    setDrawerOptions({
      open: true,
      opType,
      groupInfo,
    });
  };

  const columns: ProColumns<API.GroupManage.Groups>[] = useMemo(
    () => [
      {
        key: 'index',
        dataIndex: 'index',
        valueType: 'indexBorder',
      },
      {
        title: intl.formatMessage({ id: 'group.faceURL' }),
        dataIndex: 'faceURL',
        key: 'faceURL',
        hideInSearch: true,
        align: 'center',
        render: (_, record) => <OIMAvatar src={record.groupInfo.faceURL} isgroup />,
      },
      {
        title: intl.formatMessage({ id: 'group.groupName' }),
        key: 'groupName',
        dataIndex: 'groupName',
        align: 'center',
        render: (_, record) => <span>{record.groupInfo.groupName}</span>,
      },
      {
        title: intl.formatMessage({ id: 'group.groupID' }),
        key: 'groupID',
        dataIndex: 'groupID',
        align: 'center',
        render: (_, record) => <span>{record.groupInfo.groupID}</span>,
      },
      {
        title: intl.formatMessage({ id: 'group.memberCount' }),
        key: 'memberCount',
        dataIndex: 'memberCount',
        hideInSearch: true,
        align: 'center',
        render: (_, record) => <span>{record.groupInfo.memberCount}</span>,
      },
      {
        title: intl.formatMessage({ id: 'group.GroupOwnerID' }),
        key: 'GroupOwnerID',
        dataIndex: 'GroupOwnerID',
        hideInSearch: true,
        align: 'center',
        render: (_, record) => <span>{record.groupInfo.ownerUserID}</span>,
      },
      {
        title: intl.formatMessage({ id: 'group.createTime' }),
        key: 'createTime',
        dataIndex: 'createTime',
        hideInSearch: true,
        align: 'center',
        render: (_, record) => (
          <span>{moment(record.groupInfo.createTime).format('YYYY-MM-DD')}</span>
        ),
      },
      {
        title: '',
        valueType: 'option',
        key: 'option',
        align: 'center',
        render: (_, record) => {
          const isMuted = record.groupInfo.status === GroupStatus.Muted;
          return (
            <Space>
              <a onClick={() => toGroupMember(record.groupInfo)}>
                {intl.formatMessage({ id: 'group.member' })}
              </a>
              <a onClick={() => openDrawer('edit', record.groupInfo)}>
                {intl.formatMessage({ id: 'group.setting' })}
              </a>
              <Popconfirm
                title={
                  isMuted
                    ? intl.formatMessage({ id: 'group.closeAllMute.tips' })
                    : intl.formatMessage({ id: 'group.allMute.tips' })
                }
                onConfirm={() => muteGroupHandler(isMuted, record.groupInfo.groupID)}
              >
                <a>
                  {isMuted
                    ? intl.formatMessage({ id: 'group.closeAllMute' })
                    : intl.formatMessage({ id: 'group.allMute' })}
                </a>
              </Popconfirm>
              <Popconfirm
                title={intl.formatMessage({ id: 'group.dismiss.tips' })}
                onConfirm={() => dismissGroupHandler(record.groupInfo.groupID)}
              >
                <a>{intl.formatMessage({ id: 'group.dismiss' })}</a>
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
      <GroupActionDrawer reload={reload} closeDrawer={closeDrawer} drawerOptions={drawerOptions} />
      <ProTable<API.GroupManage.Groups>
        columns={columns}
        actionRef={actionRef}
        request={async (params = {}) => {
          const { data } = await getGroupList({
            ...params,
            groupID: params.groupID ?? '',
            pagination: {
              pageNumber: params.current as number,
              showNumber: params.pageSize as number,
            },
          });
          return {
            data: data.groups,
            success: true,
            total: data.total,
          };
        }}
        rowKey={(record) => record.groupInfo.groupID}
        search={{
          labelWidth: 'auto',
        }}
        pagination={{
          defaultPageSize: 10,
          showQuickJumper: true,
        }}
        toolbar={{
          actions: [
            <Button key="add" type="primary" onClick={() => openDrawer('create')}>
              {intl.formatMessage({ id: 'group.create' })}
            </Button>,
          ],
          settings: [],
        }}
      />
    </PageContainer>
  );
};

export default GroupList;
