import { PageContainer } from '@ant-design/pro-components';
import { Avatar, Button, Card, Input, message, Space, Upload } from 'antd';

import { UploadOutlined } from '@ant-design/icons';
import { UploadRequestOption } from 'rc-upload/lib/interface';
import { useEffect, useState } from 'react';
import { splitUpload } from '@/services/upload';
import { getOrganizationInfo, updateOrganizationInfo } from '@/services/organization';
import { useIntl } from '@umijs/max';

const OrganizationEdit = () => {
  const intl = useIntl();
  const [, setUploadUrl] = useState('');
  const [orgInfo, setOrgInfo] = useState<API.OrganizationManage.Organization>({
    logoURL: '',
    name: '',
    homepage: '',
    introduction: '',
  });

  const getInfo = async () => {
    const { data } = await getOrganizationInfo();
    setOrgInfo(data);
  };

  const updateInfo = async () => {
    try {
      await updateOrganizationInfo(orgInfo);
    } catch (error) {
      console.log(error);
    }
    message.success(intl.formatMessage({ id: 'api.success' }));
  };

  useEffect(() => {
    getInfo();
  }, []);

  const inputChang = (e: any) => {
    const val = (e.target as HTMLInputElement).value;
    setOrgInfo((values) => {
      return {
        ...values,
        name: val,
      };
    });
  };

  const customUpload = async (data: UploadRequestOption) => {
    try {
      const { url: avatarUrl } = await splitUpload(data.file as File);
      if (avatarUrl) {
        setUploadUrl(avatarUrl);
        await updateOrganizationInfo({ ...orgInfo, logoURL: avatarUrl });
        getInfo();
      }
    } catch (error) {
      console.log(error);
    }
  };

  return (
    <PageContainer>
      <Card>
        <Space direction="vertical">
          <Space direction="vertical" align="center">
            <Avatar
              size={{ xs: 24, sm: 32, md: 40, lg: 64, xl: 80, xxl: 100 }}
              src={orgInfo.logoURL}
            />
            <Upload accept="image/*" customRequest={customUpload} showUploadList={false}>
              <Button icon={<UploadOutlined />}>{intl.formatMessage({ id: 'api.upload' })}</Button>
            </Upload>
          </Space>
          <div style={{ marginTop: '20px' }}>{intl.formatMessage({ id: 'org.name' })}</div>
          <Space>
            <Input value={orgInfo.name} onChange={inputChang} />
            <Button type={'primary'} onClick={() => updateInfo()}>
              {intl.formatMessage({ id: 'save' })}
            </Button>
          </Space>
        </Space>
      </Card>
    </PageContainer>
  );
};

export default OrganizationEdit;
