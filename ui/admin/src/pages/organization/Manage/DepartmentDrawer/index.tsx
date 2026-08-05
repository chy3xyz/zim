import { ProForm, ProFormText } from '@ant-design/pro-components';
import { Drawer, Form, message } from 'antd';
import type { Key } from 'antd/es/table/interface';
import { FC, useEffect } from 'react';
import { DrawerType } from '../data';
import { createDepartment, updateDepartment } from '@/services/organization';
import { useIntl } from '@umijs/max';

type OrgDepartmentDrawerProps = {
  type: DrawerType;
  departmentName: string;
  departmentIdList: Key[];
  setDepDrawer: (type: DrawerType) => void;
};

const OrgDepartmentDrawer: FC<OrgDepartmentDrawerProps> = ({
  type,
  departmentName,
  departmentIdList,
  setDepDrawer,
}) => {
  const intl = useIntl();
  const [form] = Form.useForm();

  useEffect(() => {
    if (type) {
      form.setFieldsValue({
        departmentName,
      });
    }
  }, [type]);

  const onClose = () => {
    setDepDrawer(DrawerType.Null);
    form.resetFields();
  };

  const onCreateHandler = async (values: any) => {
    try {
      await createDepartment({
        name: values.name,
        parentDepartmentID: String(departmentIdList[0] ?? ''),
      });
      message.success(intl.formatMessage({ id: 'api.success' }));
      onClose();
    } catch (error) {
      console.log(error);
    }
  };

  const onEditHandler = async (values: any) => {
    try {
      await updateDepartment({ name: values.name, departmentID: String(departmentIdList[0]) });
      message.success(intl.formatMessage({ id: 'api.success' }));
      onClose();
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

  const titleType =
    type === DrawerType.Create
      ? intl.formatMessage({ id: 'org.dep.create' })
      : intl.formatMessage({ id: 'org.dep.edit' });

  return (
    <Drawer title={titleType} placement="right" onClose={onClose} open={type !== DrawerType.Null}>
      <ProForm
        submitter={{
          resetButtonProps: {
            style: {
              display: 'none',
            },
          },
        }}
        form={form}
        layout="horizontal"
        onFinish={onFinish}
      >
        <ProFormText
          name="departmentName"
          label={
            type === DrawerType.Create
              ? intl.formatMessage({ id: 'org.dep.superiors' })
              : intl.formatMessage({ id: 'org.dep.name' })
          }
          disabled
        />
        <ProFormText name="name" label={intl.formatMessage({ id: 'org.dep.name' })} />
      </ProForm>
    </Drawer>
  );
};

export default OrgDepartmentDrawer;
