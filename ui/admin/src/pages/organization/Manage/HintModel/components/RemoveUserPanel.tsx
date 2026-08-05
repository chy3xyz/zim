import { useIntl } from '@umijs/max';

const RemoveUserPanel = () => {
  const intl = useIntl();
  return (
    <div>
      <p>{intl.formatMessage({ id: 'org.modal.removeUser.tips' })}</p>
    </div>
  );
};

export default RemoveUserPanel;
