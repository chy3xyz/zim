import OIMAvatar from '@/components/OIMAvatar';
import {
  addNotificationAccount,
  getNotificationAccounts,
  updateNotificationAccount,
} from '@/services/notification';
import { splitUpload } from '@/services/upload';
import { UploadOutlined } from '@ant-design/icons';
import { ActionType, PageContainer, ProColumns, ProTable } from '@ant-design/pro-components';
import { useIntl } from '@umijs/max';
import { Button, Form, Input, Modal, Upload } from 'antd';
import type { UploadFile } from 'antd/es/upload/interface';
import { UploadRequestOption } from 'rc-upload/lib/interface';
import { useRef, useState } from 'react';

const customUpload = async (
  userID: string,
  data: UploadRequestOption,
  reload?: (resetPageIndex?: boolean | undefined) => Promise<void>,
) => {
  try {
    const { url } = await splitUpload(data.file as File);
    if (url) {
      await updateNotificationAccount({
        userID,
        faceURL: url,
      });
      reload?.();
    }
  } catch (error) {
    console.log(error);
  }
};

const normFile = (e: any) => {
  if (Array.isArray(e)) {
    return e;
  }
  e?.fileList?.forEach((file: UploadFile) => {
    file.status = 'done';
  });
  return e?.fileList;
};

const AccountList = () => {
  const intl = useIntl();
  const [addModalVisible, setAddModalVisible] = useState(false);
  const [adding, setAdding] = useState(false);
  const actionRef = useRef<ActionType>();

  const columns: ProColumns<API.NotificationManage.Account>[] = [
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
      editable: false,
      align: 'center',
      render(_, record, __, action) {
        return (
          <Upload
            accept="image/*"
            customRequest={(option) => customUpload(record.userID, option, action?.reload)}
            showUploadList={false}
            className="cursor-pointer"
          >
            <OIMAvatar src={record.faceURL} text={record.nickName} />
          </Upload>
        );
      },
    },
    {
      title: intl.formatMessage({ id: 'user.nickname' }),
      key: 'nickName',
      dataIndex: 'nickName',
      align: 'center',
    },
    {
      title: intl.formatMessage({ id: 'user.userID' }),
      key: 'userID',
      dataIndex: 'userID',
      editable: false,
      align: 'center',
    },
    {
      title: '',
      valueType: 'option',
      key: 'option',
      align: 'center',
      render: (_, record, __, action) => {
        return (
          <a
            key="editable"
            onClick={() => {
              action?.startEditable?.(record.userID);
            }}
          >
            {intl.formatMessage({ id: 'edit' })}
          </a>
        );
      },
    },
  ];

  const confirmAdd = async ({
    userID,
    nickName,
    avatar,
  }: {
    userID: string;
    nickName: string;
    avatar: UploadFile[];
  }) => {
    setAdding(true);
    try {
      const { url } = await splitUpload(avatar[0].originFileObj as File);
      if (!url) {
        throw Error('splitUpload error');
      }
      await addNotificationAccount(userID, nickName, url);
      actionRef.current?.reload();
    } catch (error) {
      console.log(error);
    }
    setAdding(false);
    setAddModalVisible(false);
  };

  return (
    <PageContainer>
      <Modal
        title={intl.formatMessage({ id: 'add' })}
        width={400}
        open={addModalVisible}
        onCancel={() => {
          setAddModalVisible(false);
        }}
        centered
        destroyOnClose
        footer={null}
      >
        <Form onFinish={confirmAdd} labelCol={{ span: 6 }}>
          <Form.Item
            name="avatar"
            label={intl.formatMessage({ id: 'user.faceURL' })}
            valuePropName="fileList"
            getValueFromEvent={normFile}
            rules={[{ required: true, message: intl.formatMessage({ id: 'user.faceURL.tips' }) }]}
          >
            <Upload
              name="avatar"
              accept="image/*"
              customRequest={() => {}}
              listType="picture"
              maxCount={1}
              multiple={false}
            >
              <Button icon={<UploadOutlined />}>{intl.formatMessage({ id: 'api.upload' })}</Button>
            </Upload>
          </Form.Item>
          <Form.Item
            name="nickName"
            label={intl.formatMessage({ id: 'user.nickname' })}
            rules={[{ required: true, message: intl.formatMessage({ id: 'user.nickname.tips' }) }]}
          >
            <Input placeholder={intl.formatMessage({ id: 'user.nickname.tips' })} />
          </Form.Item>

          <Form.Item
            name="userID"
            label={intl.formatMessage({ id: 'user.userID' })}
            rules={[{ required: true, message: intl.formatMessage({ id: 'user.userID.tips' }) }]}
          >
            <Input placeholder={intl.formatMessage({ id: 'user.userID.tips' })} />
          </Form.Item>

          <div className="ml-[20%]">
            <Button type="primary" htmlType="submit" loading={adding}>
              {intl.formatMessage({ id: 'confirm' })}
            </Button>
          </div>
        </Form>
      </Modal>
      <ProTable<API.NotificationManage.Account>
        columns={columns}
        actionRef={actionRef}
        toolbar={{
          actions: [
            <Button
              key={'add'}
              type="primary"
              onClick={() => {
                setAddModalVisible(true);
              }}
            >
              {intl.formatMessage({ id: 'add' })}
            </Button>,
          ],
          settings: [],
        }}
        request={async (params = {}) => {
          const { data } = await getNotificationAccounts({
            keyword: params.userID || params.nickName,
            pagination: {
              pageNumber: params.current as number,
              showNumber: params.pageSize as number,
            },
          });

          return {
            data: data.notificationAccounts ?? [],
            success: true,
            total: data.total,
          };
        }}
        editable={{
          type: 'multiple',
          actionRender: (_, __, doms) => {
            return [doms.save, doms.cancel];
          },
          onSave: (_, record) => {
            return updateNotificationAccount({
              userID: record.userID,
              nickName: record.nickName,
            });
          },
        }}
        rowKey="userID"
        pagination={{
          defaultPageSize: 10,
          showQuickJumper: true,
        }}
        scroll={{ x: 'max-content' }}
      />
    </PageContainer>
  );
};

export default AccountList;
