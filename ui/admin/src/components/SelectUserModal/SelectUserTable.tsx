import { ActionType, FormInstance, ProColumns, ProTable } from '@ant-design/pro-components';
import {
  ForwardRefRenderFunction,
  Key,
  forwardRef,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
  useState,
} from 'react';
import OIMAvatar from '../OIMAvatar';
import { SearchOutlined } from '@ant-design/icons';
import { Input } from 'antd';
import { getUserList } from '@/services/user';
import { useIntl } from '@umijs/max';
import { getSomeGroupMemberList } from '@/services/group';

export type SelectedRowDataItem = Record<
  number,
  {
    keys: React.Key[];
    items: API.UserManage.User[];
  }
>;

type SelectUserTableProps = {
  selectType?: 'radio' | 'checkbox';
  groupID?: string;
  defaultSelected?: React.Key[];
  disabledData?: string[];
  onSelectedChange?: (data: API.UserManage.User[], keys: React.Key[]) => void;
};

export type SelectUserTableHandle = {
  clearSelect: () => void;
  cancelSelect: (value: string) => void;
};

const SelectUserTable: ForwardRefRenderFunction<SelectUserTableHandle, SelectUserTableProps> = (
  props,
  ref,
) => {
  const { selectType, defaultSelected, groupID, disabledData, onSelectedChange } = props;
  const intl = useIntl();
  const actionRef = useRef<ActionType>();
  const formRef = useRef<FormInstance>();

  const [idList, setIdList] = useState<Key[]>([]);
  const [inGroupUserList, setInGroupUserList] = useState<string[]>([]);

  useEffect(() => {
    setIdList(defaultSelected ?? []);
  }, [defaultSelected]);

  const onSelectChange = (keys: React.Key[], items: API.UserManage.User[]) => {
    setIdList(keys);
    if (onSelectedChange) {
      onSelectedChange(items, keys);
    }
  };

  const getCheckboxProps = (record: API.UserManage.User) => {
    if (groupID) {
      const disabledList = [...inGroupUserList, ...(disabledData ?? [])];
      return { disabled: disabledList?.includes(record.userID), name: record.nickname };
    }
    return { disabled: disabledData?.includes(record.userID), name: record.nickname };
  };

  const cancelSelect = (userID: string) => {
    setIdList(idList.filter((id) => id !== userID));
  };

  const clearSelect = () => {
    actionRef.current?.clearSelected!();
  };

  useImperativeHandle(ref, () => ({
    cancelSelect,
    clearSelect,
  }));

  const columns: ProColumns<API.UserManage.User>[] = useMemo(
    () => [
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
        hideInSearch: true,
        ellipsis: true,
        align: 'center',
      },
      {
        title: intl.formatMessage({ id: 'user.userID' }),
        key: 'userID',
        dataIndex: 'userID',
        align: 'center',
        ellipsis: true,
        hideInSearch: true,
      },
      {
        title: '',
        key: 'keyword',
        dataIndex: 'keyword',
        hideInTable: true,
        renderFormItem: () => {
          return (
            <div className="mb-[-32px]">
              <div className="font-medium mb-4">{intl.formatMessage({ id: 'user.keyword' })}</div>
              <Input
                className=" w-[360px]"
                onChange={(e) => {
                  formRef.current?.setFieldValue('keyword', e.target.value);
                }}
                prefix={<SearchOutlined />}
              />
            </div>
          );
        },
      },
    ],
    [],
  );

  return (
    <ProTable<API.UserManage.User>
      search={{
        optionRender: false,
      }}
      size="small"
      columns={columns}
      rowSelection={{
        columnTitle: '',
        selectedRowKeys: idList,
        type: selectType,
        onChange: onSelectChange,
        getCheckboxProps,
        preserveSelectedRowKeys: true,
      }}
      tableAlertRender={false}
      tableAlertOptionRender={false}
      actionRef={actionRef}
      formRef={formRef}
      columnsState={{
        defaultValue: {
          option: {
            fixed: 'right',
          },
        },
        persistenceKey: 'user_table_insearch',
        persistenceType: 'sessionStorage',
      }}
      request={async (params = {}) => {
        const { data } = await getUserList({
          ...params,
          keyword: params.keyword,
          pagination: {
            pageNumber: params.current as number,
            showNumber: params.pageSize as number,
          },
        });
        const tmpData = data.users ?? [];
        if (groupID) {
          const { data } = await getSomeGroupMemberList({
            groupID,
            userIDs: tmpData.map((item) => item.userID),
          });
          setInGroupUserList(
            ((data.members as API.UserManage.User[]) || []).map((user) => user.userID),
          );
        }
        return {
          data: tmpData,
          success: true,
          total: data.total,
        };
      }}
      rowKey="userID"
      pagination={{
        defaultPageSize: 10,
        showSizeChanger: false,
      }}
      toolbar={{
        actions: [],
        settings: [],
      }}
    />
  );
};

export default forwardRef(SelectUserTable);
