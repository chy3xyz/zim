import avatar_upload from '@/assets/images/avatar_upload.png';

import { areaCode } from '@/constants/areaCode';
import { ProForm, ProFormDatePicker, ProFormSelect, ProFormText } from '@ant-design/pro-components';
import { Avatar, Drawer, Form, Input, message, Select, Space, TreeSelect, Upload } from 'antd';
import md5 from 'md5';
import moment from 'moment';
import { UploadRequestOption } from 'rc-upload/lib/interface';
import { FC, useEffect, useState } from 'react';
import { DrawerType } from '../data';
import {
  createUser,
  getUserInfo,
  updateUserDepartment,
  updateUserInfo,
} from '@/services/organization';
import { splitUpload } from '@/services/upload';
import { useIntl } from '@umijs/max';

type UserDrawerProps = {
  type: DrawerType;
  treeData: any[];
  userID: string;
  departmentIdList: string[];
  refreshData: () => void;
  setUserDrawerType: (type: DrawerType) => void;
};

const UserDrawer: FC<UserDrawerProps> = ({
  type,
  treeData,
  userID,
  departmentIdList,
  refreshData,
  setUserDrawerType,
}) => {
  const intl = useIntl();
  const [form] = Form.useForm();
  const [uploadUrl, setUploadUrl] = useState('');

  const departmentID = departmentIdList[0];

  const onClose = () => {
    setTimeout(() => {
      form.resetFields();
      setUploadUrl('');
    }, 500);
    setUserDrawerType(DrawerType.Null);
  };

  const getUser = async () => {
    try {
      const { data } = await getUserInfo([userID]);
      form.setFieldsValue({
        ...data.users[0].user,
        gender:
          data.users[0].user.gender === 1
            ? intl.formatMessage({ id: 'user.gender.man' })
            : intl.formatMessage({ id: 'user.gender.woman' }),
        position: data.users[0].members.find((e) => e.departmentID === departmentID)?.position,
      });
      setUploadUrl(data.users[0].user.faceURL);
    } catch (error) {
      console.log(error);
    }
  };

  useEffect(() => {
    if (type === DrawerType.Edit) {
      getUser();
    }
    if (type === DrawerType.Create) {
      form.setFieldsValue({
        departmentID: departmentIdList[0],
      });
    }
  }, [type]);

  const onCreateHandler = async (values: any) => {
    try {
      const params = {
        user: {
          ...values,
          birth: moment(values.birth).unix() * 1000,
          faceURL: uploadUrl,
          areaCode: '+86',
          gender: Number(values.gender),
          password: md5(values.password),
        },
        departments: [
          {
            departmentID: values.departmentID,
            position: values.position,
          },
        ],
      };
      await createUser(params);
      message.success(intl.formatMessage({ id: 'api.success' }));
      onClose();
      refreshData();
    } catch (error) {
      console.log(error);
    }
  };

  const onEditHandler = async (values: any) => {
    try {
      await updateUserInfo({
        ...values,
        userID,
        birth: moment(values.birth).unix() * 1000,
        areaCode: '+86',
        gender: Number(values.gender),
        faceURL: uploadUrl,
      });
      if (departmentID) {
        await updateUserDepartment({
          departmentID,
          userID,
          station: '',
          position: values.position,
        });
      }
      message.success(intl.formatMessage({ id: 'api.success' }));
      onClose();
      refreshData();
    } catch (error) {
      console.log(error);
    }
  };

  const onFinish = async (values: any) => {
    if (type === DrawerType.Create) {
      onCreateHandler(values);
      return;
    }
    if (type === DrawerType.Edit) {
      onEditHandler(values);
    }
  };

  const customUpload = async (data: UploadRequestOption) => {
    try {
      const { url: avatarUrl } = await splitUpload(data.file as File);
      if (avatarUrl) {
        setUploadUrl(avatarUrl);
      }
    } catch (error) {
      console.log(error);
    }
  };

  const isEdit = type === DrawerType.Edit;

  const getFieldRules = () => {
    return {
      nickname: isEdit
        ? []
        : [{ required: true, message: intl.formatMessage({ id: 'user.nickname.tips' }) }],
      password: isEdit
        ? []
        : [{ required: true, message: intl.formatMessage({ id: 'org.user.password.tips' }) }],
    };
  };

  return (
    <Drawer
      title={
        isEdit
          ? intl.formatMessage({ id: 'org.user.edit' })
          : intl.formatMessage({ id: 'org.user.create' })
      }
      placement="right"
      onClose={onClose}
      destroyOnClose
      open={type !== DrawerType.Null}
    >
      <div className="w-full text-center mb-12">
        <div className="flex flex-col">
          <Upload accept="image/*" customRequest={customUpload} showUploadList={false}>
            <Avatar shape="square" size={55} src={uploadUrl || avatar_upload} />
            <div className="text-[#1890FFFF] mt-3">{intl.formatMessage({ id: 'api.upload' })}</div>
          </Upload>
        </div>
      </div>
      <ProForm
        labelCol={{ flex: '65px' }}
        labelAlign="right"
        submitter={{
          resetButtonProps: {
            style: {
              display: 'none',
            },
          },
          submitButtonProps: {
            style: { marginLeft: 'auto' },
          },
          searchConfig: {
            submitText: isEdit
              ? intl.formatMessage({ id: 'org.user.edit' })
              : intl.formatMessage({ id: 'org.user.create' }),
          },
        }}
        form={form}
        layout="horizontal"
        onFinish={onFinish}
        initialValues={{
          areaCode: '86',
        }}
      >
        <ProFormText
          name="nickname"
          label={intl.formatMessage({ id: 'user.nickname' })}
          width="md"
          rules={getFieldRules()['nickname']}
        />
        <ProFormSelect
          name="gender"
          label={intl.formatMessage({ id: 'user.gender' })}
          valueEnum={{
            1: intl.formatMessage({ id: 'user.gender.man' }),
            2: intl.formatMessage({ id: 'user.gender.woman' }),
          }}
        />

        <ProFormDatePicker
          name="birth"
          label={intl.formatMessage({ id: 'user.birth' })}
          width="md"
          fieldProps={{ disabledDate: (current) => current && current > moment().endOf('day') }}
        />

        <Form.Item required label={intl.formatMessage({ id: 'user.phoneNumber' })}>
          <Space.Compact>
            <Form.Item name="areaCode">
              <Select onSearch={() => {}} showSearch className="!w-24">
                {areaCode.map((country) => (
                  <Select.Option
                    key={country.value}
                    value={country.value}
                  >{`${country.value}`}</Select.Option>
                ))}
              </Select>
            </Form.Item>
            <Form.Item
              name="phoneNumber"
              rules={[
                { required: true, message: intl.formatMessage({ id: 'user.phoneNumber.tips' }) },
              ]}
            >
              <Input
                type="number"
                placeholder={intl.formatMessage({ id: 'user.phoneNumber.tips' })}
              />
            </Form.Item>
          </Space.Compact>
        </Form.Item>

        <Form.Item name="email" label={intl.formatMessage({ id: 'user.email' })}>
          <Input type="email" />
        </Form.Item>

        {!isEdit && (
          <>
            <Form.Item
              name="departmentID"
              label={intl.formatMessage({ id: 'org.user.department' })}
              rules={[
                {
                  required: true,
                  message: intl.formatMessage({ id: 'org.user.department.tips' }),
                },
              ]}
            >
              <TreeSelect
                placeholder={intl.formatMessage({ id: 'org.user.department.tips' })}
                fieldNames={{ value: 'key' }}
                showSearch
                allowClear
                treeDefaultExpandAll
                treeData={treeData}
              />
            </Form.Item>
            <ProFormText name="position" label={intl.formatMessage({ id: 'org.user.position' })} />
          </>
        )}
        <ProFormText
          name="account"
          label={intl.formatMessage({ id: 'org.user.account' })}
          disabled={isEdit}
          rules={[
            {
              required: true,
              message: intl.formatMessage({ id: 'org.user.account.tips' }),
            },
          ]}
        />
        {isEdit && (
          <ProFormText
            name="position"
            label={intl.formatMessage({ id: 'org.user.position' })}
            hidden={departmentIdList.length <= 0}
          />
        )}
        <ProFormText.Password
          name="password"
          label={intl.formatMessage({ id: 'org.user.password' })}
          hidden={isEdit}
          rules={getFieldRules()['password']}
        />
      </ProForm>
    </Drawer>
  );
};

export default UserDrawer;
