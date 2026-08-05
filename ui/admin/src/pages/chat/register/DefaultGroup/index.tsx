import OIMAvatar from '@/components/OIMAvatar';
import { addDefaultGroup, getDefaultGroup, removeDefaultGroup } from '@/services/default';
import { UsergroupAddOutlined } from '@ant-design/icons';
import { ActionType, PageContainer, ProColumns, ProTable } from '@ant-design/pro-components';
import { useIntl } from '@umijs/max';
import { Button, Input, Popconfirm, Space, message } from 'antd';
import { useMemo, useRef, useState } from 'react';

const DefultGroup = () => {
  const intl = useIntl();
  const actionRef = useRef<ActionType>();
  const [addInputval, setaddInputval] = useState<string>();

  const removeDefaultGroupHandler = async (userID: string) => {
    try {
      await removeDefaultGroup([userID]);
      message.success(intl.formatMessage({ id: 'api.success' }));
      actionRef.current?.reload();
    } catch (error) {
      console.log(error);
    }
  };

  const addDefaultGroupHandler = async () => {
    if (!addInputval) return;
    try {
      await addDefaultGroup([addInputval]);
      setaddInputval('');
      message.success(intl.formatMessage({ id: 'api.success' }));
      actionRef.current?.reload();
    } catch (error) {
      console.log(error);
    }
  };

  const columns: ProColumns<API.GroupManage.GroupInfo>[] = useMemo(
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
        align: 'center',
        render: (_, record) => <OIMAvatar src={record.faceURL} isgroup />,
      },
      {
        title: intl.formatMessage({ id: 'group.groupID' }),
        dataIndex: 'groupID',
        key: 'groupID',
        align: 'center',
      },
      {
        title: intl.formatMessage({ id: 'group.groupName' }),
        key: 'groupName',
        dataIndex: 'groupName',
        align: 'center',
        render: (_, record) => <span>{record.groupName}</span>,
      },
      {
        title: '',
        valueType: 'option',
        key: 'option',
        align: 'center',
        render: (_, record) => (
          <Popconfirm
            key={'remove'}
            title={intl.formatMessage({ id: 'group.removeDefaultGroup.tips' })}
            onConfirm={() => removeDefaultGroupHandler(record.groupID)}
          >
            <a>{intl.formatMessage({ id: 'remove' })}</a>
          </Popconfirm>
        ),
      },
    ],
    [],
  );

  return (
    <PageContainer>
      <ProTable<API.GroupManage.GroupInfo>
        columns={columns}
        actionRef={actionRef}
        request={async (params = {}) => {
          const { data } = await getDefaultGroup({
            ...params,
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
        rowKey={(record) => record.groupID}
        pagination={{
          defaultPageSize: 10,
        }}
        search={false}
        toolbar={{
          actions: [
            <Space key={'add'}>
              <Input
                value={addInputval}
                prefix={<UsergroupAddOutlined />}
                onChange={(e) => setaddInputval(e.target.value)}
                placeholder={intl.formatMessage({ id: 'group.groupID' })}
              />
              <Button type="primary" onClick={addDefaultGroupHandler}>
                {intl.formatMessage({ id: 'add' })}
              </Button>
            </Space>,
          ],
          settings: [],
        }}
      />
    </PageContainer>
  );
};

export default DefultGroup;
