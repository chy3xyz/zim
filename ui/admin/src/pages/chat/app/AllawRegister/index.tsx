import { allowRegister, getAllowRegister } from '@/services/app';
import { PageContainer } from '@ant-design/pro-components';
import { Checkbox, message, Spin } from 'antd';
import React, { useEffect, useState } from 'react';
import { useIntl } from '@umijs/max';

const AllawRegister = () => {
  const intl = useIntl();
  const [isAllow, setIsAllow] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const getConfig = async () => {
    try {
      setIsLoading(true);
      const { data } = await getAllowRegister();
      setIsAllow(data.allowRegister);
    } catch (error) {
      console.log(error);
    } finally {
      setIsLoading(false);
    }
  };

  const updateConfig = async () => {
    try {
      await allowRegister(!isAllow);
      getConfig();
      message.success(intl.formatMessage({ id: 'api.success' }));
    } catch (error) {
      console.log(error);
    }
  };

  useEffect(() => {
    getConfig();
  }, []);

  return (
    <PageContainer>
      <div className="text-base font-medium mb-6 py-5 px-5 bg-white">
        <Spin spinning={isLoading} tip="Loading">
          <Checkbox checked={isAllow} onChange={updateConfig} disabled={isLoading}>
            {intl.formatMessage({ id: 'user.allow.register' })}
            <div className=" text-xs text-gray-400">
              *{intl.formatMessage({ id: 'user.allow.register.tips' })}
            </div>
          </Checkbox>
        </Spin>
      </div>
    </PageContainer>
  );
};

export default AllawRegister;
