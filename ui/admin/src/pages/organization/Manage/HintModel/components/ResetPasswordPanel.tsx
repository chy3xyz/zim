import { useIntl } from '@umijs/max';

const ResetPasswordPanel = () => {
  const intl = useIntl();
  return (
    <div>
      <p> {intl.formatMessage({ id: 'org.modal.resetPassword.title' })}</p>
    </div>
  );
};

export default ResetPasswordPanel;
