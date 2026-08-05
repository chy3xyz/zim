import { deleteLog, getLogs } from '@/services/logs';
import { ActionType, PageContainer, ProColumns, ProTable } from '@ant-design/pro-components';
import { useIntl } from '@umijs/max';
import { message, Space, Typography } from 'antd';
import Popconfirm from 'antd/es/popconfirm';
import moment from 'moment';
import { useRef } from 'react';
import { v4 as uuidv4 } from 'uuid';

const LogList = () => {
  const intl = useIntl();
  const actionRef = useRef<ActionType>();

  const deleteLogs = async (record: API.LogManage.LogItem) => {
    try {
      await deleteLog([record.logID]);
      message.success(intl.formatMessage({ id: 'api.success' }));
      actionRef.current?.reload();
    } catch (error) {
      console.log('error', error);
    }
  };

  const columns: ProColumns<API.LogManage.LogItem>[] = [
    {
      key: 'index',
      dataIndex: 'index',
      valueType: 'indexBorder',
      align: 'center',
    },
    {
      title: intl.formatMessage({ id: 'user.userID' }),
      dataIndex: 'userID',
      align: 'center',
      search: {
        transform: (value) => ({
          keyword: value,
        }),
      },
    },
    {
      title: intl.formatMessage({ id: 'user.nickname' }),
      dataIndex: 'nickname',
      hideInSearch: true,
      align: 'center',
    },
    {
      title: intl.formatMessage({ id: 'log.systemType' }),
      dataIndex: 'systemType',
      hideInSearch: true,
      align: 'center',
    },
    {
      title: intl.formatMessage({ id: 'log.platform' }),
      dataIndex: 'platform',
      align: 'center',
      hideInSearch: true,
    },
    {
      title: intl.formatMessage({ id: 'log.version' }),
      dataIndex: 'version',
      hideInSearch: true,
      align: 'center',
    },
    {
      title: intl.formatMessage({ id: 'group.createTime' }),
      key: 'createTime',
      dataIndex: 'createdAtRange',
      valueType: 'dateTimeRange',
      align: 'center',
      search: {
        transform: (value: any) => ({
          startTime: new Date(value[0]).getTime(),
          endTime: new Date(value[1]).getTime(),
        }),
      },
      render(_, entity) {
        return moment(entity.createTime).format('YYYY-MM-DD HH:mm:ss');
      },
    },
    {
      title: 'ex',
      dataIndex: 'ex',
      align: 'center',
      hideInSearch: true,
      render(_, entity) {
        return (
          <Typography.Text
            ellipsis={{
              tooltip: entity.ex,
            }}
            style={{ width: '80px' }}
          >
            {entity.ex}
          </Typography.Text>
        );
      },
    },
    {
      title: '',
      valueType: 'option',
      key: 'option',
      align: 'center',
      render: (_, record) => {
        return (
          <Space>
            <a href={record.url} download={record.filename}>
              {intl.formatMessage({ id: 'download' })}
            </a>
            <Popconfirm
              key="delete"
              title={intl.formatMessage({ id: 'log.delete.tips' })}
              onConfirm={() => deleteLogs(record)}
            >
              <a>{intl.formatMessage({ id: 'delete' })}</a>
            </Popconfirm>
          </Space>
        );
      },
    },
  ];

  return (
    <PageContainer>
      <ProTable<API.LogManage.LogItem>
        columns={columns}
        actionRef={actionRef}
        request={async (params = {}) => {
          const { data } = await getLogs({
            ...params,
            pagination: {
              pageNumber: params.current as number,
              showNumber: params.pageSize as number,
            },
          });
          return {
            data: data.logsInfos ?? [],
            success: true,
            total: data.total,
          };
        }}
        rowKey={() => uuidv4()}
        search={{
          labelWidth: 'auto',
        }}
        pagination={{
          defaultPageSize: 10,
        }}
      />
    </PageContainer>
  );
};

export default LogList;
