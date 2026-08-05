import { FC, useEffect, useState } from 'react';
import { Button, Drawer, Form, Input, Select, Switch, Upload, UploadFile, message } from 'antd';
import { useIntl } from '@umijs/max';
import { addVersion, updateVersion } from '@/services/app';
import TextArea from 'antd/es/input/TextArea';
import { UploadRequestOption } from 'rc-upload/lib/interface';
import { splitUpload } from '@/services/upload';
import { UploadFileStatus } from 'antd/es/upload/interface';
import clsx from 'clsx';
import { language, platform } from '@/constants/app';

type VersionFormFields = Omit<API.AppManage.Version, 'id'> & {
  language: string;
  architecture: string;
};

type VersionActionDrawerProps = {
  openAction: boolean;
  currentVersion: API.AppManage.Version | null;
  closeModal: () => void;
  reloadTable: () => void;
};

const VersionActionDrawer: FC<VersionActionDrawerProps> = ({
  openAction,
  currentVersion,
  closeModal,
  reloadTable,
}) => {
  const intl = useIntl();
  const [form] = Form.useForm();
  const [fileList, setFileList] = useState<UploadFile<any>[]>([]);
  const [loading, setLoading] = useState(false);

  const isCreated = !currentVersion?.id;
  const title = isCreated
    ? intl.formatMessage({ id: 'app.add' })
    : intl.formatMessage({ id: 'app.edit' });
  const submitText = isCreated
    ? intl.formatMessage({ id: 'app.create' })
    : intl.formatMessage({ id: 'app.save' });

  useEffect(() => {
    form.setFieldsValue({ ...currentVersion });
  }, [currentVersion]);

  const closeDrawer = () => {
    form.resetFields();
    closeModal();
    setFileList([]);
  };

  const preViewFileList = (name: string, status: UploadFileStatus, url: string) => {
    setFileList([
      {
        uid: '1',
        name: name,
        status,
        percent: 66,
        url,
      },
    ]);
  };

  const customUpload = async (data: UploadRequestOption) => {
    try {
      preViewFileList((data.file as File).name, 'uploading', '');
      const { url } = await splitUpload(data.file as File);
      if (url) {
        preViewFileList((data.file as File).name, 'done', url);
      }
    } catch (error) {
      console.log(error);
      preViewFileList((data.file as File).name, 'error', '');
    }
  };

  const onRemove = () => {
    setFileList([]);
  };

  const onFinish = async (values: VersionFormFields) => {
    if (isCreated && !fileList[0]?.url) {
      message.error(intl.formatMessage({ id: 'app.url.tips' }));
      return;
    }
    const isCreatedPlatform = `${values.language}_${values.platform}${
      values.architecture ? '_' + values.architecture : ''
    }`;
    const params = {
      ...values,
      platform: isCreated ? isCreatedPlatform : currentVersion.platform,
      url: isCreated ? fileList[0].url! : currentVersion!.url,
    };
    try {
      setLoading(true);
      if (isCreated) {
        await addVersion(params);
      } else {
        await updateVersion({ id: currentVersion!.id, ...params });
      }
      reloadTable();
      closeDrawer();
      message.success(intl.formatMessage({ id: 'api.success' }));
    } catch (error) {
      console.error(error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Drawer
      title={title}
      placement="right"
      closable={false}
      onClose={closeDrawer}
      open={openAction}
    >
      <div>
        <Form<VersionFormFields>
          form={form}
          labelCol={{ span: 6 }}
          wrapperCol={{ span: 18 }}
          onFinish={onFinish}
          autoComplete="off"
          initialValues={{
            force: false,
            latest: false,
            hot: false,
          }}
        >
          {isCreated && (
            <Form.Item
              label={intl.formatMessage({ id: 'app.language' })}
              name="language"
              rules={[
                {
                  required: true,
                  message: intl.formatMessage({ id: 'app.language.tips' }),
                },
              ]}
            >
              <Select>
                {language.map((item) => (
                  <Select.Option key={item.value} value={item.value}>
                    {item.label}
                  </Select.Option>
                ))}
              </Select>
            </Form.Item>
          )}

          {isCreated && (
            <Form.Item
              label={intl.formatMessage({ id: 'app.platform' })}
              name="platform"
              rules={[
                {
                  required: true,
                  message: intl.formatMessage({ id: 'app.platform.tips' }),
                },
              ]}
            >
              <Select>
                {platform.map((item) => (
                  <Select.Option key={item.value} value={item.value}>
                    {item.label}
                  </Select.Option>
                ))}
              </Select>
            </Form.Item>
          )}

          {isCreated && (
            <Form.Item
              label={intl.formatMessage({ id: 'app.version' })}
              name="version"
              rules={[{ required: true, message: intl.formatMessage({ id: 'app.version.tips' }) }]}
            >
              <Input />
            </Form.Item>
          )}

          {isCreated && (
            <Form.Item label={intl.formatMessage({ id: 'app.architecture' })} name="architecture">
              <Input />
            </Form.Item>
          )}

          <Form.Item label={intl.formatMessage({ id: 'app.force' })} name="force">
            <Switch />
          </Form.Item>

          <Form.Item label={intl.formatMessage({ id: 'app.latest' })} name="latest">
            <Switch />
          </Form.Item>

          <Form.Item label={intl.formatMessage({ id: 'app.hot' })} name="hot">
            <Switch />
          </Form.Item>

          {isCreated && (
            <Form.Item
              label={
                <span>
                  <span
                    className="text-[#ff4d4f] text-sm"
                    style={{ fontFamily: 'SimSun, sans-serif' }}
                  >
                    *{' '}
                  </span>
                  {intl.formatMessage({ id: 'app.url' })}
                </span>
              }
            >
              <Upload
                fileList={fileList}
                onRemove={onRemove}
                customRequest={customUpload}
                maxCount={1}
              >
                <div
                  className={clsx('text-[#1890FFFF] cursor-pointer', fileList.length > 0 && 'mt-1')}
                >
                  {intl.formatMessage({ id: 'api.upload' })}
                </div>
              </Upload>
            </Form.Item>
          )}

          <Form.Item
            label={intl.formatMessage({ id: 'app.text' })}
            name="text"
            rules={[{ required: true, message: intl.formatMessage({ id: 'app.text.tips' }) }]}
          >
            <TextArea rows={4} />
          </Form.Item>

          <div className="w-full text-right">
            <Button className="px-6" type="primary" htmlType="submit" disabled={loading}>
              {submitText}
            </Button>
          </div>
        </Form>
      </div>
    </Drawer>
  );
};

export default VersionActionDrawer;
