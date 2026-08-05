import { ACCOUNT_URL } from '@/config';
import { importByExcel } from '@/services/organization';
import { FileExcelFilled, FileFilled } from '@ant-design/icons';
import { useIntl } from '@umijs/max';

import { Button, Space, Upload, UploadProps, message } from 'antd';
import { FC } from 'react';

type ImportPanelProps = {
  onClose: () => void;
  refreshData: () => void;
};

const ImportPanel: FC<ImportPanelProps> = ({ onClose, refreshData }) => {
  const intl = useIntl();

  const uploadProps: UploadProps = {
    maxCount: 1,
    action: ``,
    accept: '.xlsx',
    showUploadList: false,
    customRequest: async (options) => {
      try {
        await importByExcel(options.file as File);
        message.success(intl.formatMessage({ id: 'api.success' }));
        onClose();
        refreshData();
      } catch (error) {
        console.log(error);
      }
    },
  };

  return (
    <div style={{ textAlign: 'center', height: '260px' }}>
      <Space size={'large'} style={{ height: '100%' }}>
        <Space direction="vertical" size={26}>
          <div>{intl.formatMessage({ id: 'org.modal.import.tips1' })}</div>
          <div>
            <FileExcelFilled
              twoToneColor="#ebebeb"
              style={{
                fontSize: '3rem',
                color: '#ebebeb',
              }}
            />
          </div>
          <Button
            onClick={() => {
              window.open(`${ACCOUNT_URL}/organization/import/template`);
            }}
          >
            {intl.formatMessage({ id: 'org.modal.import.tips' })}
          </Button>
        </Space>
        <div>-</div>
        <Space direction="vertical" size={26}>
          <div>{intl.formatMessage({ id: 'org.modal.import.tips2' })}</div>
          <div>
            <FileFilled
              twoToneColor="#ebebeb"
              style={{
                fontSize: '3rem',
                color: '#ebebeb',
              }}
            />
          </div>
          <Upload {...uploadProps}>
            <Button>{intl.formatMessage({ id: 'api.upload' })}</Button>
          </Upload>
        </Space>
      </Space>
    </div>
  );
};

export default ImportPanel;
