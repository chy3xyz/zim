import login_bg from '@/assets/images/login_bg.png';
import { adminLogin } from '@/services/account';
import { LockOutlined, UserOutlined } from '@ant-design/icons';
import { history, useIntl, useModel } from '@umijs/max';
import { Button, Checkbox, Form, Input } from 'antd';
import md5 from 'md5';
import { useState } from 'react';

type FormField = {
  account: string;
  password: string;
};

const Login = () => {
  const intl = useIntl();
  const [loading, setLoading] = useState(false);
  const { setInitialState } = useModel('@@initialState');

  const onFinish = async (value: FormField) => {
    setLoading(true);
    try {
      const { data } = await adminLogin({ account: value.account, password: md5(value.password) });

      localStorage.setItem('level', String(data.level));
      localStorage.setItem('IMAccountToken', data.adminToken);
      localStorage.setItem('IMAdminToken', data.imToken);
      localStorage.setItem('IMAdminAccount', value.account);
      localStorage.setItem('IMAdminUserID', data.imUserID);

      await setInitialState((s: any) => ({
        ...s,
        currentUser: data,
      }));
      setTimeout(() => {
        history.push('/chat/user/user_list');
      }, 200);
    } catch (error) {
      console.log(error);
    }
    setLoading(false);
  };

  return (
    <div className="w-screen h-screen flex justify-center items-center">
      <div className="flex">
        <img src={login_bg} alt="" />
        <div className="flex flex-col ml-24">
          <div className="text-2xl font-medium mb-16">
            {intl.formatMessage({ id: 'pages.login.welcome' })}
          </div>
          <Form
            name="basic"
            className="w-[364px]"
            onFinish={onFinish}
            initialValues={{
              check: true,
            }}
            autoComplete="off"
            requiredMark={false}
            size="large"
          >
            <Form.Item
              name="account"
              rules={[
                {
                  required: true,
                  message: intl.formatMessage({ id: 'pages.login.account.required' }),
                },
              ]}
            >
              <Input
                prefix={<UserOutlined className="text-[#4686fc]" />}
                placeholder={intl.formatMessage({ id: 'pages.login.account' })}
              />
            </Form.Item>

            <Form.Item
              name="password"
              rules={[
                {
                  required: true,
                  message: intl.formatMessage({ id: 'pages.login.password.required' }),
                },
              ]}
            >
              <Input.Password
                height={40}
                prefix={<LockOutlined className="text-[#4686fc]" />}
                placeholder={intl.formatMessage({ id: 'pages.login.password' })}
              />
            </Form.Item>

            <Form.Item wrapperCol={{ span: 24 }}>
              <Button className="w-full" type="primary" htmlType="submit" loading={loading}>
                {intl.formatMessage({ id: 'pages.login' })}
              </Button>
            </Form.Item>

            <Form.Item name="check" valuePropName="checked">
              <Checkbox>
                {intl.formatMessage({ id: 'pages.login.agreement' })}
                <span className="text-[#4686fc] mx-1">
                  {intl.formatMessage({ id: 'pages.login.agreement.service' })}
                </span>
                {intl.formatMessage({ id: 'pages.login.and' })}
                <span className="text-[#4686fc] mx-1">
                  {intl.formatMessage({ id: 'pages.login.agreement.privacy' })}
                </span>
              </Checkbox>
            </Form.Item>
          </Form>
        </div>
      </div>
    </div>
  );
};

export default Login;
