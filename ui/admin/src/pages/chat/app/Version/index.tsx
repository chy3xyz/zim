import { deleteVersion, getVersionList } from '@/services/app';
import { ActionType, PageContainer, ProColumns, ProTable } from '@ant-design/pro-components';
import { useIntl } from '@umijs/max';
import { Button, message, Popconfirm, Space } from 'antd';
import React, { useMemo, useRef, useState } from 'react';
import VersionActionDrawer from './VersionActionDrawer';

const Version = () => {
  const intl = useIntl();
  const actionRef = useRef<ActionType>();

  const [openAction, setOpenAction] = useState(false);
  const [currentVersion, setCurrentVersion] = useState<API.AppManage.Version | null>(null);

  const reloadTable = () => actionRef.current?.reload();

  const closeModal = () => {
    setCurrentVersion(null);
    setOpenAction(false);
  };

  const updateOpenAction = (record: API.AppManage.Version | null) => {
    setCurrentVersion(record);
    setOpenAction(true);
  };

  const tryDeleteVersion = async (id: string) => {
    try {
      await deleteVersion({ id: [id] });
      reloadTable();
      message.success(intl.formatMessage({ id: 'api.success' }));
    } catch (error) {
      console.log(error);
    }
  };

  const columns: ProColumns<API.AppManage.Version>[] = useMemo(
    () => [
      {
        key: 'index',
        dataIndex: 'index',
        valueType: 'indexBorder',
      },
      {
        title: intl.formatMessage({ id: 'app.name' }),
        key: 'platform',
        dataIndex: 'platform',
        editable: false,
        hideInTable: false,
        align: 'center',
      },
      {
        title: intl.formatMessage({ id: 'app.version' }),
        key: 'version',
        dataIndex: 'version',
        editable: false,
        hideInSearch: true,
        align: 'center',
      },
      {
        title: intl.formatMessage({ id: 'app.text' }),
        key: 'text',
        dataIndex: 'text',
        hideInSearch: true,
        editable: false,
        align: 'center',
      },
      {
        title: intl.formatMessage({ id: 'app.force' }),
        key: 'force',
        dataIndex: 'force',
        hideInSearch: true,
        editable: false,
        align: 'center',
        render: (_, record) => {
          return <Space>{record.force ? '✅' : '❌'}</Space>;
        },
      },
      {
        title: intl.formatMessage({ id: 'app.latest' }),
        key: 'latest',
        dataIndex: 'latest',
        hideInSearch: true,
        editable: false,
        align: 'center',
        render: (_, record) => {
          return <Space>{record.latest ? '✅' : '❌'}</Space>;
        },
      },
      {
        title: intl.formatMessage({ id: 'app.hot' }),
        key: 'hot',
        dataIndex: 'hot',
        hideInSearch: true,
        editable: false,
        align: 'center',
        render: (_, record) => {
          return <Space>{record.hot ? '✅' : '❌'}</Space>;
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
              <a href={record.url} download={record.platform + record.version}>
                {intl.formatMessage({ id: 'download' })}
              </a>
              <a key="edit" onClick={() => updateOpenAction(record)}>
                {intl.formatMessage({ id: 'app.edit' })}
              </a>
              <Popconfirm
                key="delete"
                title={intl.formatMessage({ id: 'app.delete.tips' })}
                onConfirm={() => tryDeleteVersion(record.id)}
              >
                <a>{intl.formatMessage({ id: 'app.delete' })}</a>
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
      <VersionActionDrawer
        openAction={openAction}
        currentVersion={currentVersion}
        reloadTable={reloadTable}
        closeModal={closeModal}
      />
      <ProTable<API.AppManage.Version>
        columns={columns}
        actionRef={actionRef}
        rowKey="id"
        request={async (params = {}) => {
          const platform = params.platform ? [params.platform] : [];
          const { data } = await getVersionList({
            platform,
            pagination: {
              pageNumber: params.current as number,
              showNumber: params.pageSize as number,
            },
          });
          return {
            data: data.versions ?? [],
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
              {intl.formatMessage({ id: 'app.add' })}
            </Button>,
          ],
          settings: [],
        }}
      />
    </PageContainer>
  );
};

export default Version;
