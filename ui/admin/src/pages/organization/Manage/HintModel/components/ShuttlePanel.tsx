import { ApartmentOutlined } from '@ant-design/icons';
import { Checkbox, Col, message, Row } from 'antd';
import type { CheckboxValueType } from 'antd/es/checkbox/Group';
import { FC, useEffect, useState } from 'react';
import { getSubDepartment } from '@/services/organization';
import { useIntl } from '@umijs/max';
import { useOrganization } from '../../hook';

type Item = {
  label: string;
  value: string;
  checked: boolean;
};

type Title = {
  id: string;
  title: string;
};

type ShuttleProps = {
  departmentId: string;
  setTargetDepartmentList: (arr: string[]) => void;
};

const Shuttle: FC<ShuttleProps> = ({ departmentId, setTargetDepartmentList }) => {
  const intl = useIntl();
  const { departmentList, organization } = useOrganization();

  const [options, setOptions] = useState<Item[]>([]);
  const [showOptions, setShowOptions] = useState<Item[]>([]);
  const [selectId, setSelectId] = useState<Item[]>([]);

  const [titleList, setTitleList] = useState<Title[]>([]);

  useEffect(() => {
    setOptions(
      departmentList?.map((e) => {
        return { label: e.department.name, value: e.department.departmentID, checked: false };
      }) || [],
    );

    setShowOptions(
      departmentList?.map((e) => {
        return { label: e.department.name, value: e.department.departmentID, checked: false };
      }) || [],
    );
  }, [departmentList]);

  const onChange = (checkedValues: CheckboxValueType[]) => {
    const arr = (checkedValues as string[]).map((str) => {
      const item = options.find((e) => e.value === str) as Item;
      return { label: item.label, value: item.value, checked: true };
    });
    setSelectId(arr);
    setTargetDepartmentList(checkedValues as string[]);
  };

  const getSubList = async (id: string, cb = () => {}) => {
    try {
      const { data } = await getSubDepartment(id);

      if (!data.departments || data.departments?.length === 0) {
        return message.warning(intl.formatMessage({ id: 'org.dep.last' }));
      }
      cb();
      const arr = [...options];
      const newList =
        data.departments?.map((e: API.OrganizationManage.Department) => {
          return { label: e.name, value: e.departmentID, checked: false };
        }) || [];
      newList.forEach((element: Item) => {
        if (!arr.some((e) => e.value === element.value)) {
          arr.push(element);
        }
      });
      setShowOptions(newList);
      setOptions(arr);
    } catch (error) {
      console.log(error);
    }
  };

  const addSub = (id: string, title: string) => {
    getSubList(id, () => setTitleList([...titleList, { id, title }]));
  };

  const removeSub = (id: string, index: number) => {
    setTitleList(titleList.splice(0, index + 1));
    if (index === -1) {
      setShowOptions(
        departmentList?.map((e) => {
          return { label: e.department.name, value: e.department.departmentID, checked: false };
        }) || [],
      );
      return;
    }
    getSubList(id);
  };

  const disabledList = ['$ungrouped', departmentId];

  return (
    <div className="flex flex-row">
      <div className="w-1/2 mr-3">
        <div className="mb-3">
          <span onClick={() => removeSub('0', -1)}>{organization?.name}</span>
          {titleList.map((e, i) => {
            return (
              <span key={e.id} onClick={() => removeSub(e.id, i)}>
                {' > '}
                {e.title}
              </span>
            );
          })}
        </div>
        <Checkbox.Group onChange={onChange} style={{ width: '100%', flexDirection: 'column' }}>
          {options.map((e) => {
            return (
              <Row
                justify={'center'}
                key={e.value + new Date().getTime()}
                style={{
                  display: showOptions.some((o) => o.value === e.value) ? 'flex' : 'none',
                  marginBottom: '16px',
                }}
              >
                <Col span={18}>
                  <Checkbox
                    value={e.value}
                    checked={e.checked}
                    disabled={disabledList.includes(e.value)}
                  >
                    <div className="flex justify-start items-start">
                      <div className="rounded-md w-7 h-7 bg-[#e7f3ff] flex  justify-center items-center">
                        <ApartmentOutlined
                          style={{
                            color: '#1890ff',
                          }}
                        />
                      </div>
                      <div className="w-20 h-7 flex  justify-center items-center ml-2">
                        {e.label}
                      </div>
                    </div>
                  </Checkbox>
                </Col>
                <Col
                  span={6}
                  className="text-center text-blue-400 cursor-pointer"
                  onClick={() => addSub(e.value, e.label)}
                >
                  {intl.formatMessage({ id: 'org.dep.subordinate' })}
                </Col>
              </Row>
            );
          })}
        </Checkbox.Group>
      </div>
      <div className="w-1/2">
        <div className="mb-3">{intl.formatMessage({ id: 'org.dep.selected' })}</div>
        <Checkbox.Group style={{ width: '100%' }} name="select">
          <Row gutter={[0, 16]} justify={'center'}>
            {selectId.map((e) => {
              return (
                <Col span={24} key={e.value}>
                  <div className="flex justify-start items-start">
                    <div className="rounded-md w-7 h-7 bg-[#e7f3ff] flex  justify-center items-center">
                      <ApartmentOutlined
                        style={{
                          color: '#1890ff',
                        }}
                      />
                    </div>
                    <div className="w-20 h-7 flex  justify-center items-center ml-2">{e.label}</div>
                  </div>
                </Col>
              );
            })}
          </Row>
        </Checkbox.Group>
      </div>
    </div>
  );
};

export default Shuttle;
