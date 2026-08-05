import { API_URL } from '@/config';
import { request } from '@umijs/max';

export async function getNotificationAccounts(
  params: API.NotificationManage.QueryNotificationAccountParams,
) {
  return request<{ data: API.NotificationManage.QueryNotificationAccountResult }>(
    '/user/search_notification_account',
    {
      method: 'POST',
      data: {
        ...params,
      },
      baseURL: API_URL,
    },
  );
}

export async function addNotificationAccount(userID: string, nickName: string, faceURL: string) {
  return request('/user/add_notification_account', {
    method: 'POST',
    data: {
      userID,
      nickName,
      faceURL,
    },
    baseURL: API_URL,
  });
}

export async function updateNotificationAccount(
  params: API.NotificationManage.UpdateNotificationAccountParams,
) {
  return request('/user/update_notification_account', {
    method: 'POST',
    data: {
      ...params,
    },
    baseURL: API_URL,
  });
}

export async function batchSendNotification({
  recvIDList,
  isSendAll,
  sendID,
  text,
  senderNickname,
  senderFaceURL,
  externalUrl,
  ...params
}: API.ChatLog.BatchSendParams) {
  return request('/msg/batch_send_msg', {
    method: 'POST',
    data: {
      isSendAll,
      sendID,
      recvIDs: recvIDList,
      groupID: '',
      senderNickname,
      senderFaceURL,
      senderPlatformID: 5,
      content: {
        notificationName: senderNickname,
        notificationType: 1,
        text,
        externalUrl,
        ...params,
      },
      contentType: 1400,
      sessionType: 4,
      isOnlineOnly: false,
      notOfflinePush: false,
      offlinePushInfo: {
        title: 'System Notification',
        desc: text,
        ex: '',
        iOSPushSound: 'default',
        iOSBadgeCount: true,
      },
    },
    baseURL: API_URL,
  });
}
