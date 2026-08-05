import { useIntl } from '@umijs/max';

const DeleteDepPanel = () => {
  const intl = useIntl();
  return (
    <div>
      <p>{intl.formatMessage({ id: 'org.modal.deleteDepartment.title' })}</p>
      <br />
      <p className="font-normal text-xs">
        {intl.formatMessage({ id: 'org.modal.deleteDepartment.tips' })}
      </p>
    </div>
  );
};

export default DeleteDepPanel;
