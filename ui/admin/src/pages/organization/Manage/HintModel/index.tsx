import { message, Modal } from 'antd';
import md5 from 'md5';
import { FC, useState } from 'react';
import { ModalType, MoveUserDepartment } from '../data';
import { deleteDepartment, moveUserDepartment, removeMember } from '@/services/organization';
import { resetUserPassword } from '@/services/user';
import { useIntl } from '@umijs/max';
import ShuttlePanel from './components/ShuttlePanel';
import DeleteDepPanel from './components/DeleteDepPanel';
import RemoveUserPanel from './components/RemoveUserPanel';
import ResetPasswordPanel from './components/ResetPasswordPanel';
import ImportPanel from './components/ImportPanel';

type HintModelProps = {
  type: ModalType;
  userID: string;
  departmentIdList: string[];
  selectedRowKeys: string[];
  setModalType: (type: ModalType) => void;
  resetSelectedRowKeys: () => void;
  init: () => void;
  refreshData: () => void;
};

const HintModel: FC<HintModelProps> = ({
  type,
  userID,
  departmentIdList,
  selectedRowKeys,
  setModalType,
  resetSelectedRowKeys,
  init,
  refreshData,
}) => {
  const intl = useIntl();
  const departmentId = departmentIdList[0];

  const [targetDepartmentList, setTargetDepartmentList] = useState<string[]>([]);

  const onClose = () => {
    setModalType(ModalType.Null);
  };

  const deleteDepHandler = async () => {
    try {
      await deleteDepartment(departmentIdList);
      init();
      refreshData();
      message.success(intl.formatMessage({ id: 'api.success' }));
      onClose();
    } catch (error) {
      console.log(error);
    }
  };

  const resetPasswordHandler = async () => {
    try {
      await resetUserPassword({
        userID,
        newPassword: md5('123456'),
      });
      message.success(intl.formatMessage({ id: 'org.modal.resetPassword.tips' }));
      onClose();
    } catch (error) {
      console.log(error);
    }
  };

  const removeUserHandler = async () => {
    try {
      await removeMember({ departmentID: departmentId, userID });
      message.success(intl.formatMessage({ id: 'api.success' }));
      resetSelectedRowKeys();
      refreshData();
      onClose();
    } catch (error) {
      console.log(error);
    }
  };

  const batchRemoveUserHandler = async () => {
    try {
      const list = selectedRowKeys.map((item) => ({ departmentID: departmentId, userID: item }));
      await Promise.all(list.map((item) => removeMember(item)));
      message.success(intl.formatMessage({ id: 'api.success' }));
      resetSelectedRowKeys();
      refreshData();
      onClose();
    } catch (error) {
      console.log(error);
    }
  };

  const shuttleHandler = async () => {
    try {
      const list: MoveUserDepartment[] = [];
      selectedRowKeys.forEach((user_ID) => {
        targetDepartmentList.forEach((depID) => {
          list.push({
            userID: user_ID,
            departmentID: depID,
            currentDepartmentID: departmentId,
          });
        });
      });
      await moveUserDepartment({ moves: list });
      message.success(intl.formatMessage({ id: 'api.success' }));
      resetSelectedRowKeys();
      refreshData();
      onClose();
    } catch (error) {
      console.log(error);
    }
  };

  const importHandler = async () => {
    resetSelectedRowKeys();
    onClose();
  };

  const modals = {
    [ModalType.DeleteDepartment]: {
      title: intl.formatMessage({ id: 'org.modal.deleteDepartment' }),
      el: <DeleteDepPanel />,
    },
    [ModalType.RemoveUser]: {
      title: intl.formatMessage({ id: 'org.modal.removeUser' }),
      el: <RemoveUserPanel />,
    },
    [ModalType.BatchRemoveUser]: {
      title: intl.formatMessage({ id: 'org.modal.batchRemoveUser' }),
      el: <RemoveUserPanel />,
    },
    [ModalType.ResetPassword]: {
      title: intl.formatMessage({ id: 'org.modal.resetPassword' }),
      el: <ResetPasswordPanel />,
    },
    [ModalType.Import]: {
      title: intl.formatMessage({ id: 'org.modal.import' }),
      el: <ImportPanel onClose={onClose} refreshData={refreshData} />,
    },
    [ModalType.Shuttle]: {
      title: intl.formatMessage({ id: 'org.modal.shuttle' }),
      el: (
        <ShuttlePanel
          setTargetDepartmentList={setTargetDepartmentList}
          departmentId={departmentId}
        />
      ),
    },
  } as { [key in ModalType]: { title: string; el: JSX.Element } };

  const onOK = async () => {
    switch (type) {
      case ModalType.DeleteDepartment:
        deleteDepHandler();
        break;
      case ModalType.ResetPassword:
        resetPasswordHandler();
        break;
      case ModalType.RemoveUser:
        removeUserHandler();
        break;
      case ModalType.BatchRemoveUser:
        batchRemoveUserHandler();
        break;
      case ModalType.Import:
        importHandler();
        break;
      case ModalType.Shuttle:
        shuttleHandler();
        break;
    }
  };

  return (
    <Modal
      title={modals[type]?.title || ''}
      open={type !== ModalType.Null}
      onOk={onOK}
      onCancel={onClose}
      centered
      width={type === ModalType.Import || type === ModalType.Shuttle ? 700 : 420}
    >
      {modals[type]?.el || <></>}
    </Modal>
  );
};

export default HintModel;
