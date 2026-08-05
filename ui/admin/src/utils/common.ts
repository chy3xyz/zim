/* eslint-disable no-case-declarations */
import { CustomMessageType } from '@/constants/enum';
import { Platform } from '@/constants/platform';
import { splitUpload } from '@/services/upload';
import { useIntl } from '@umijs/max';
import { message } from 'antd';
import { isThisYear } from 'date-fns';
import dayjs from 'dayjs';
import calendar from 'dayjs/plugin/calendar';
import updateLocale from 'dayjs/plugin/updateLocale';
import { MessageType } from 'open-im-sdk';
import { MessageItem, PublicUserItem } from 'open-im-sdk/lib/types/entity';
import { useCallback } from 'react';
import { v4 as uuidV4 } from 'uuid';

dayjs.extend(calendar);
dayjs.extend(updateLocale);

dayjs.updateLocale('en', {
  calendar: {
    sameDay: 'HH:mm',
    nextDay: '[tomorrow]',
    nextWeek: 'dddd',
    lastDay: '[yesterday] HH:mm',
    lastWeek: 'dddd HH:mm',
    sameElse: 'YYYY/M/D HH:mm',
  },
});
dayjs.updateLocale('zh-cn', {
  calendar: {
    sameDay: 'HH:mm',
    nextDay: '[明天]',
    nextWeek: 'dddd',
    lastDay: '[昨天] HH:mm',
    lastWeek: 'dddd HH:mm',
    sameElse: 'YYYY年M月D日 HH:mm',
  },
});

export const switchOnline = (platformInfo: API.UserManage.UserPlatformInfo[]) => {
  let str = '';
  platformInfo?.map((info) => {
    str += `${Platform[info.platformID]}/`;
    return null;
  });
  return `${str.slice(0, -1)}`;
};

export const useCopy2Text = () => {
  const intl = useIntl();

  const copy2Text = useCallback((text: string) => {
    if (navigator.clipboard) {
      navigator.clipboard.writeText(text);
    } else {
      const textarea = document.createElement('textarea');
      document.body.appendChild(textarea);
      textarea.style.position = 'fixed';
      textarea.style.clip = 'rect(0 0 0 0)';
      textarea.style.top = '10px';
      textarea.value = text;
      textarea.select();
      document.execCommand('copy', true);
      document.body.removeChild(textarea);
    }
    message.success(intl.formatMessage({ id: 'copy.success' }));
  }, []);

  return {
    copy2Text,
  };
};

interface GetConversationIDParams {
  groupID?: string;
  sendID?: string;
  recvID?: string;
  isNotification?: boolean;
}

export const getConversationID = (params: GetConversationIDParams) => {
  if (params.isNotification) {
    return `sn_${params.sendID}_${params.recvID}`;
  }
  if (params.groupID) {
    return `sg_${params.groupID}`;
  }
  const array = [params.sendID, params.recvID].sort();
  return `si_${array[0]}_${array[1]}`;
};

export const bytesToSize = (bytes: number) => {
  if (bytes === 0) return '0 B';
  const k = 1024,
    sizes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'],
    i = Math.floor(Math.log(bytes) / Math.log(k));

  return `${(bytes / Math.pow(k, i)).toPrecision(3)} ${sizes[i]}`;
};

export const formatMessageTime = (timestemp: number, keepSameYear = false): string => {
  if (!timestemp) return '';

  const isRecent = dayjs().diff(timestemp, 'day') < 7;
  const keepYear = keepSameYear || !isThisYear(timestemp);

  if (!isRecent && !keepYear) {
    return dayjs(timestemp).format('M/D HH:mm');
  }

  return dayjs(timestemp).calendar();
};

export const useParseMessage = () => {
  const intl = useIntl();

  const sec2Time = (seconds: number) => {
    let theTime1 = 0;
    let theTime2 = 0;
    let theTime3 = 0;
    let mySeconds = seconds;
    if (mySeconds > 60) {
      theTime1 = parseInt(String(mySeconds / 60));
      mySeconds = parseInt(String(mySeconds % 60));
      if (theTime1 > 60) {
        theTime2 = parseInt(String(theTime1 / 60));
        theTime1 = parseInt(String(theTime1 % 60));
        if (theTime2 > 24) {
          theTime3 = parseInt(String(theTime2 / 24));
          theTime2 = parseInt(String(theTime2 % 24));
        }
      }
    }
    let result = '';
    if (mySeconds > 0) {
      result = intl.formatMessage({ id: 'second' }, { num: parseInt(String(mySeconds)) });
    }
    if (theTime1 > 0) {
      result = intl.formatMessage({ id: 'minute' }, { num: parseInt(String(theTime1)) });
    }
    if (theTime2 > 0) {
      result = intl.formatMessage({ id: 'hour' }, { num: parseInt(String(theTime2)) });
    }
    if (theTime3 > 0) {
      result = intl.formatMessage({ id: 'day' }, { num: parseInt(String(theTime3)) });
    }
    return result;
  };

  const parseMessageByType = (message?: MessageItem) => {
    if (!message) return '';
    const getName = (user: PublicUserItem) => user.nickname;

    try {
      switch (message.contentType) {
        case MessageType.TextMessage:
          return message.textElem?.content;
        case MessageType.AtTextMessage:
          let mstr = message.atTextElem.text;
          const pattern = /@\S+\s/g;
          const arr = mstr.match(pattern);
          arr?.map((a) => {
            const member = (message.atTextElem.atUsersInfo ?? []).find(
              (gm) => gm.atUserID === a.slice(1, -1),
            );
            if (member) {
              const reg = new RegExp(a, 'g');
              mstr = mstr.replace(reg, `@${member.groupNickname} `);
            }
            return null;
          });
          return mstr;
        case MessageType.PictureMessage:
          return intl.formatMessage({ id: 'imageMessage' });
        case MessageType.VideoMessage:
          return intl.formatMessage({ id: 'videoMessage' });
        case MessageType.VoiceMessage:
          return intl.formatMessage({ id: 'voiceMessage' });
        case MessageType.LocationMessage:
          const locationInfo = JSON.parse(message.locationElem.description);
          return intl.formatMessage({ id: 'locationMessage' }, { location: locationInfo.name });
        case MessageType.CardMessage:
          return intl.formatMessage({ id: 'cardMessage' });
        case MessageType.MergeMessage:
          return intl.formatMessage({ id: 'mergeMessage' });
        case MessageType.FileMessage:
          return intl.formatMessage({ id: 'fileMessage' }, { file: message.fileElem.fileName });
        case MessageType.RevokeMessage:
          const data = JSON.parse(message.notificationElem.detail);
          const operator = data.revokerNickname;
          const revoker = data.sourceMessageSenderNickname;
          const isAdminRevoke = data.revokerID !== data.sourceMessageSendID;

          if (isAdminRevoke) {
            return intl.formatMessage({ id: 'advanceRevokeMessage' }, { operator, revoker });
          }
          return intl.formatMessage({ id: 'revokeMessage' }, { revoker });
        case MessageType.CustomMessage:
          const customEl = message.customElem;
          const customData = JSON.parse(customEl.data);
          if (customData.customType === CustomMessageType.MassMsg)
            return intl.formatMessage({ id: 'massMessage' });
          if (customData.customType === CustomMessageType.Call)
            return intl.formatMessage({ id: 'callMessage' });
          if (customData.customType === CustomMessageType.MeetingInvitation)
            return intl.formatMessage({ id: 'meetingMessage' });
          return intl.formatMessage({ id: 'customMessage' });
        case MessageType.QuoteMessage:
          return message.quoteElem.text || intl.formatMessage({ id: 'quoteMessage' });
        case MessageType.FaceMessage:
          return intl.formatMessage({ id: 'faceMessage' });
        case MessageType.FriendAdded:
          return intl.formatMessage({ id: 'alreadyFriendMessage' });
        case MessageType.MemberEnter:
          const enterDetails = JSON.parse(message.notificationElem.detail);
          const enterUser = enterDetails.entrantUser;
          return intl.formatMessage({ id: 'joinGroupMessage' }, { name: getName(enterUser) });
        case MessageType.GroupCreated:
          const groupCreatedDetail = JSON.parse(message.notificationElem.detail);
          const groupCreatedUser = groupCreatedDetail.opUser;
          return intl.formatMessage(
            { id: 'createGroupMessage' },
            { creator: getName(groupCreatedUser) },
          );
        case MessageType.MemberInvited:
          const inviteDetails = JSON.parse(message.notificationElem.detail);
          const inviteOpUser = inviteDetails.opUser;
          const invitedUserList = inviteDetails.invitedUserList ?? [];
          let inviteStr = '';
          invitedUserList.slice(0, 3).map((user: any) => (inviteStr += `${getName(user)}、`));
          inviteStr = inviteStr.slice(0, -1);
          return intl.formatMessage(
            { id: 'invitedToGroupMessage' },
            {
              operator: getName(inviteOpUser),
              invitedUser: `${inviteStr}${
                invitedUserList.length > 3
                  ? intl.formatMessage({ id: 'somePerson' }, { num: invitedUserList.length })
                  : ''
              }`,
            },
          );
        case MessageType.MemberKicked:
          const kickDetails = JSON.parse(message.notificationElem.detail);
          const kickOpUser = kickDetails.opUser;
          const kickdUserList = kickDetails.kickedUserList ?? [];
          let kickStr = '';
          kickdUserList.slice(0, 3).map((user: any) => (kickStr += `${getName(user)}、`));
          kickStr = kickStr.slice(0, -1);
          return intl.formatMessage(
            { id: 'kickInGroupMessage' },
            {
              operator: getName(kickOpUser),
              invitedUser: `${kickStr}${
                kickdUserList.length > 3
                  ? intl.formatMessage({ id: 'somePerson' }, { num: kickdUserList.length })
                  : ''
              }`,
            },
          );
        case MessageType.MemberQuit:
          const quitDetails = JSON.parse(message.notificationElem.detail);
          const quitUser = quitDetails.quitUser;
          return intl.formatMessage({ id: 'quitGroupMessage' }, { name: getName(quitUser) });
        case MessageType.GroupOwnerTransferred:
          const transferDetails = JSON.parse(message.notificationElem.detail);
          const transferOpUser = transferDetails.opUser;
          const newOwner = transferDetails.newGroupOwner;
          return intl.formatMessage(
            { id: 'transferGroupMessage' },
            { owner: getName(transferOpUser), newOwner: getName(newOwner) },
          );
        case MessageType.GroupDismissed:
          const dismissDetails = JSON.parse(message.notificationElem.detail);
          const dismissUser = dismissDetails.opUser;
          return intl.formatMessage(
            { id: 'disbanedGroupMessage' },
            { operator: getName(dismissUser) },
          );
        case MessageType.GroupMuted:
          const GROUPMUTEDDetails = JSON.parse(message.notificationElem.detail);
          const groupMuteOpUser = GROUPMUTEDDetails.opUser;
          return intl.formatMessage(
            { id: 'allMuteMessage' },
            { operator: getName(groupMuteOpUser) },
          );
        case MessageType.GroupCancelMuted:
          const GROUPCANCELMUTEDDetails = JSON.parse(message.notificationElem.detail);
          const groupCancelMuteOpUser = GROUPCANCELMUTEDDetails.opUser;
          return intl.formatMessage(
            { id: 'cancelAllMuteMessage' },
            { operator: getName(groupCancelMuteOpUser) },
          );
        case MessageType.GroupMemberMuted:
          const gmMutedDetails = JSON.parse(message.notificationElem.detail);
          const muteTime = sec2Time(gmMutedDetails.mutedSeconds);
          return intl.formatMessage(
            { id: 'singleMuteMessage' },
            {
              operator: getName(gmMutedDetails.opUser),
              name: getName(gmMutedDetails.mutedUser),
              muteTime,
            },
          );
        case MessageType.GroupMemberCancelMuted:
          const gmcMutedDetails = JSON.parse(message.notificationElem.detail);
          return intl.formatMessage(
            { id: 'cancelSingleMuteMessage' },
            {
              operator: getName(gmcMutedDetails.opUser),
              name: getName(gmcMutedDetails.mutedUser),
            },
          );
        case MessageType.GroupAnnouncementUpdated:
          const groupAnnouncementDetails = JSON.parse(message.notificationElem.detail);
          return intl.formatMessage(
            { id: 'updateGroupAnnouncementMessage' },
            {
              operator: getName(groupAnnouncementDetails.opUser),
            },
          );
        case MessageType.GroupNameUpdated:
          const groupNameDetails = JSON.parse(message.notificationElem.detail);
          return intl.formatMessage(
            { id: 'updateGroupNameMessage' },
            {
              operator: getName(groupNameDetails.opUser),
              name: groupNameDetails.group.groupName,
            },
          );
        case MessageType.OANotification:
          const customNoti = JSON.parse(message.notificationElem.detail);
          return customNoti.text;
        case MessageType.BurnMessageChange:
          const burnDetails = JSON.parse(message.notificationElem.detail);
          return intl.formatMessage(
            { id: 'burnReadStatus' },
            {
              status: burnDetails.isPrivate
                ? intl.formatMessage({ id: 'open' })
                : intl.formatMessage({ id: 'close' }),
            },
          );
        default:
          return '';
      }
    } catch (error) {
      return '';
    }
  };

  return { parseMessageByType };
};

export const base64toFile = (base64Str: string) => {
  const arr = base64Str.split(','),
    fileType = arr[0].match(/:(.*?);/)![1],
    bstr = atob(arr[1]);
  let n = bstr.length;
  const u8arr = new Uint8Array(n);

  while (n--) {
    u8arr[n] = bstr.charCodeAt(n);
  }

  return new File([u8arr], `screenshot${Date.now()}.png`, {
    type: fileType,
  });
};

export const getPicInfo = (file: File): Promise<HTMLImageElement> => {
  return new Promise((resolve) => {
    const _URL = window.URL || window.webkitURL;
    const img = new Image();
    img.onload = function () {
      resolve(img);
    };
    img.src = _URL.createObjectURL(file);
  });
};

export const getVideoSnshotFile = (file: File): Promise<File> => {
  const url = URL.createObjectURL(file);
  return new Promise((reslove) => {
    const video = document.createElement('VIDEO') as HTMLVideoElement;
    video.setAttribute('autoplay', 'autoplay');
    video.setAttribute('muted', 'muted');
    video.innerHTML = `<source src="${url}" type="audio/mp4">`;
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    video.addEventListener('canplay', () => {
      const anw = document.createAttribute('width');
      //@ts-ignore
      anw.nodeValue = video.videoWidth;
      const anh = document.createAttribute('height');
      //@ts-ignore
      anh.nodeValue = video.videoHeight;
      canvas.setAttributeNode(anw);
      canvas.setAttributeNode(anh);
      //@ts-ignore
      ctx.drawImage(video, 0, 0, video.videoWidth, video.videoHeight);
      const base64 = canvas.toDataURL('image/png');
      //@ts-ignore
      video.pause();
      const file = base64toFile(base64);
      reslove(file);
    });
  });
};

export const getMediaDuration = (path: string): Promise<number> => {
  return new Promise((resolve) => {
    const vel = new Audio(path);
    vel.onloadedmetadata = function () {
      resolve(Number(vel.duration.toFixed()));
    };
  });
};

export const generatePictureElem = async (file: File, url: string) => {
  const { width, height } = await getPicInfo(file);
  const baseInfo = {
    uuid: uuidV4(),
    type: file.type,
    size: file.size,
    width,
    height,
    url,
  };
  return {
    sourcePath: '',
    sourcePicture: baseInfo,
    bigPicture: baseInfo,
    snapshotPicture: baseInfo,
  };
};

export const generateVideoElem = async (file: File, videoUrl: string) => {
  const snapShotFile = await getVideoSnshotFile(file);
  const { width, height } = await getPicInfo(snapShotFile);
  const { url: snapshotUrl } = await splitUpload(snapShotFile);

  const videoElem = {
    videoPath: '',
    videoUUID: uuidV4(),
    videoUrl,
    videoType: file.type,
    videoSize: file.size,
    duration: await getMediaDuration(URL.createObjectURL(file)),
    snapshotPath: '',
    snapshotUUID: uuidV4(),
    snapshotSize: snapShotFile.size,
    snapshotUrl: snapshotUrl,
    snapshotWidth: width,
    snapshotHeight: height,
    snapshotType: 'image/png',
  };

  return videoElem;
};
