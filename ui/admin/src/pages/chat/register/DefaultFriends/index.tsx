import SelectUserModal, {
  SelectModalOptions,
  SelectedListItem,
} from '@/components/SelectUserModal';
import { addDefaultFriends, getDefaultFriends, removeDefaultFriends } from '@/services/default';
import { ActionType, PageContainer, ProColumns, ProTable } from '@ant-design/pro-components';
import { useIntl } from '@umijs/max';
import { Button, Popconfirm, message } from 'antd';
import { useMemo, useRef, useState } from 'react';

const DefaultFriends = () => {
  const intl = useIntl();
  const actionRef = useRef<ActionType>();
  const [selectModalOptions, setSelectModalOptions] = useState<SelectModalOptions>({
    open: false,
    selectType: 'member',
  });

  const closeSelectModal = () => {
    setSelectModalOptions({
      open: false,
      selectType: 'member',
    });
  };

  const selectedCallBack = async (data: SelectedListItem) => {
    const userIDs = data.data.map((user) => user.userID);
    try {
      await addDefaultFriends(userIDs);
      message.success(intl.formatMessage({ id: 'api.success' }));
      actionRef.current?.reload();
    } catch (error) {
      console.log(error);
    }
  };

  const removeDefaultFriendsHandler = async (userID: string) => {
    try {
      await removeDefaultFriends([userID]);
      message.success(intl.formatMessage({ id: 'api.success' }));
      actionRef.current?.reload();
    } catch (error) {
      console.log(error);
    }
  };

  const columns: ProColumns<API.DefaultManage.DefaultFriends>[] = useMemo(
    () => [
      {
        key: 'index',
        dataIndex: 'index',
        valueType: 'indexBorder',
      },
      {
        title: intl.formatMessage({ id: 'user.userID' }),
        dataIndex: 'userID',
        key: 'userID',
        align: 'center',
      },
      {
        title: intl.formatMessage({ id: 'user.nickname' }),
        key: 'nickname',
        hideInSearch: true,
        align: 'center',
        render: (_, record) => <span>{record.user.nickname}</span>,
      },
      {
        title: '',
        valueType: 'option',
        key: 'option',
        align: 'center',
        render: (_, record) => (
          <Popconfirm
            key={'remove'}
            title={intl.formatMessage({ id: 'user.removeDefaultFriends.tips' })}
            onConfirm={() => removeDefaultFriendsHandler(record.userID)}
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
      <SelectUserModal
        selectModalOptions={selectModalOptions}
        selectedCallBack={selectedCallBack}
        closeSelectModal={closeSelectModal}
      />
      <ProTable<API.DefaultManage.DefaultFriends>
        columns={columns}
        actionRef={actionRef}
        rowKey="userID"
        request={async (params = {}) => {
          const { data } = await getDefaultFriends({
            ...params,
            keyword: params.userID,
            pagination: {
              pageNumber: params.current as number,
              showNumber: params.pageSize as number,
            },
          });
          return {
            data: data.users ?? [],
            success: true,
            total: data.total ?? 0,
          };
        }}
        search={{
          labelWidth: 'auto',
        }}
        pagination={{
          defaultPageSize: 10,
        }}
        toolbar={{
          actions: [
            <Button
              key={'add'}
              type="primary"
              onClick={() => {
                setSelectModalOptions({
                  open: true,
                  selectType: 'member',
                });
              }}
            >
              {intl.formatMessage({ id: 'add' })}
            </Button>,
          ],
          settings: [],
        }}
      />
    </PageContainer>
  );
};

export default DefaultFriends;
