import { PageContainer } from '@ant-design/pro-components';
import { Button, Checkbox, Col, Input, message, Row, Select, Tag, Upload, UploadFile } from 'antd';
import { useEffect, useRef, useState } from 'react';
import { batchSendNotification, getNotificationAccounts } from '@/services/notification';
import SelectUserTable, {
  SelectUserTableHandle,
} from '@/components/SelectUserModal/SelectUserTable';
import { SelectedListItem } from '@/components/SelectUserModal';
import { useIntl } from '@umijs/max';
import { UploadOutlined } from '@ant-design/icons';
import { splitUpload } from '@/services/upload';
import { generatePictureElem, generateVideoElem } from '@/utils/common';

const PublishNotification = () => {
  const intl = useIntl();
  const [allSend, setAllSend] = useState(false);
  const [content, setContent] = useState('');
  const [externalUrl, setExternalUrl] = useState('');
  const [accounts, setAccounts] = useState<API.NotificationManage.Account[]>([]);
  const [selectedAccount, setSelectedAccount] = useState<string>();
  const [sending, setSending] = useState(false);
  const [fileList, setFileList] = useState<UploadFile[]>([]);

  const selectTableRef = useRef<SelectUserTableHandle>(null);
  const [selectedList, setSelectedList] = useState<SelectedListItem>({
    data: [],
    keys: [],
  });

  const onSelectedChange = (data: API.UserManage.User[], keys: React.Key[]) => {
    setSelectedList({ data, keys });
  };

  const cancelSelect = (userID: string) => {
    selectTableRef.current?.cancelSelect(userID);
    setSelectedList({
      data: selectedList.data.filter((user) => user.userID !== userID),
      keys: selectedList.keys.filter((id) => id !== userID),
    });
  };

  const getAccounts = async () => {
    try {
      const { data } = await getNotificationAccounts({
        pagination: {
          pageNumber: 1,
          showNumber: 100,
        },
      });
      setAccounts(data.notificationAccounts ?? []);
    } catch (error) {
      console.log(error);
    }
  };

  useEffect(() => {
    getAccounts();
  }, []);

  const send2User = async () => {
    if (!selectedAccount) {
      message.warning(intl.formatMessage({ id: 'notification.account.tips' }));
      return;
    }
    setSending(true);
    const account = accounts.find((account) => account.userID === selectedAccount);
    const fileData = fileList[0] as unknown as File;
    let params = {};
    if (fileList.length > 0 && fileList[0].type !== 'video/mp4') {
      const { url } = await splitUpload(fileData);
      params = {
        mixType: 1,
        pictureElem: await generatePictureElem(fileData, url!),
      };
    }
    if (fileList.length > 0 && fileList[0].type === 'video/mp4') {
      const { url } = await splitUpload(fileData);
      console.log(url);
      params = {
        mixType: 2,
        videoElem: await generateVideoElem(fileData, url!),
      };
    }
    try {
      await batchSendNotification({
        sendID: selectedAccount,
        isSendAll: allSend,
        recvIDList: selectedList.data.map((item) => item.userID),
        text: content,
        senderNickname: account?.nickName as string,
        senderFaceURL: account?.faceURL as string,
        externalUrl,
        mixType: 0,
        ...params,
      });
      selectTableRef.current?.clearSelect();
      setSelectedList({ data: [], keys: [] });
      setContent('');
      setExternalUrl('');
      setFileList([]);
      message.success(intl.formatMessage({ id: 'api.success' }));
    } catch (error) {
      console.log(error);
    }
    setSending(false);
  };

  return (
    <PageContainer>
      <Row>
        <Col span={13} xxl={15}>
          <div className="pb-3">
            <div className="font-medium mb-2">
              {intl.formatMessage({ id: 'notification.account' })}
            </div>
            <Select
              value={selectedAccount}
              onSelect={(str) => setSelectedAccount(str)}
              className="w-[360px]"
              placeholder={intl.formatMessage({ id: 'notification.account.tips' })}
            >
              {accounts.map((account) => (
                <Select.Option key={account.userID} value={account.userID}>
                  {account.nickName}
                </Select.Option>
              ))}
            </Select>
          </div>

          <div className="font-medium">{intl.formatMessage({ id: 'notification.recvUser' })}</div>
          <div className="w-full bg-white h-[120px] mt-3 mb-4 p-2 rounded-lg overflow-auto custom_scrollbar">
            {selectedList.data.map((user) => (
              <Tag key={user.userID} closable onClose={() => cancelSelect(user.userID)}>
                {user.nickname}
              </Tag>
            ))}
          </div>

          <div className="font-medium">{intl.formatMessage({ id: 'notification.attachment' })}</div>
          <div className="w-full mt-3 mb-4">
            <Upload
              accept="image/*,.mp4"
              maxCount={1}
              multiple={false}
              fileList={fileList}
              beforeUpload={(file) => {
                setFileList([file]);
                return false;
              }}
              onRemove={() => setFileList([])}
            >
              <Button icon={<UploadOutlined />}>{intl.formatMessage({ id: 'api.upload' })}</Button>
            </Upload>
          </div>

          <div className="font-medium">
            {intl.formatMessage({ id: 'notification.externalUrl' })}
          </div>
          <div className="w-full mt-3 mb-4">
            <Input
              placeholder={intl.formatMessage({ id: 'notification.externalUrl.tips' })}
              value={externalUrl}
              onChange={(e) => setExternalUrl(e.target.value)}
            />
          </div>

          <div>
            <div className="font-medium">{intl.formatMessage({ id: 'notification.content' })}</div>
            <div className="w-full bg-white h-[350px] mt-3 py-1 rounded-lg relative px-3">
              <Input.TextArea
                placeholder={intl.formatMessage({ id: 'notification.content.tips' })}
                variant="borderless"
                autoSize={{ maxRows: 8, minRows: 8 }}
                value={content}
                onChange={(e) => setContent(e.target.value)}
                showCount
                maxLength={500}
              />
              <Button
                loading={sending}
                onClick={send2User}
                className="!absolute right-5 bottom-8 px-6"
                type="primary"
              >
                {intl.formatMessage({ id: 'confirm' })}
              </Button>
            </div>
            <Checkbox
              checked={allSend}
              onChange={(e) => setAllSend(e.target.checked)}
              className="mt-4"
            >
              {intl.formatMessage({ id: 'notification.allSend' })}
            </Checkbox>
          </div>
        </Col>
        <Col className="bg-white rounded-md" offset={1} span={10} xxl={8}>
          <SelectUserTable ref={selectTableRef} onSelectedChange={onSelectedChange} />
        </Col>
      </Row>
    </PageContainer>
  );
};

export default PublishNotification;
