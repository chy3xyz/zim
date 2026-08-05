import { MessageType } from 'open-im-sdk';

export enum GroupStatus {
  Nomal = 0,
  Baned = 1,
  Dismissed = 2,
  Muted = 3,
}

export enum GroupVerificationType {
  ApplyNeedInviteNot,
  AllNeed,
  AllNot,
}

export enum AllowType {
  Allowed,
  NotAllowed,
}

export enum GroupRole {
  Nomal = 20,
  Owner = 100,
  Admin = 60,
}

export enum GroupJoinSource {
  Invitation = 2,
  Search = 3,
  QrCode = 4,
}

export enum SessionType {
  Single = 1,
  Group = 2,
  SuperGroup = 3,
  Notification = 4,
}

export const CustomMessageType = {
  Call: 100,
  MassMsg: 903,
  MeetingInvitation: 905,
};

export const canRevokeMessage = [
  MessageType.TextMessage,
  MessageType.PictureMessage,
  MessageType.VoiceMessage,
  MessageType.VideoMessage,
  MessageType.FileMessage,
  MessageType.AtTextMessage,
  MessageType.MergeMessage,
  MessageType.CardMessage,
  MessageType.LocationMessage,
  MessageType.CustomMessage,
  MessageType.QuoteMessage,
  MessageType.FaceMessage,
];

export const nomalMessageTypes = [...canRevokeMessage, MessageType.RevokeMessage];

export const tipMessageTypes = [
  MessageType.FriendAdded,
  MessageType.GroupCreated,
  MessageType.GroupOwnerTransferred,
  MessageType.MemberQuit,
  MessageType.MemberInvited,
  MessageType.MemberKicked,
  MessageType.MemberEnter,
  MessageType.GroupDismissed,
  MessageType.GroupMuted,
  MessageType.GroupCancelMuted,
  MessageType.GroupMemberMuted,
  MessageType.GroupMemberCancelMuted,
  MessageType.GroupNameUpdated,
  MessageType.BurnMessageChange,
  MessageType.OANotification,
];

export const canSearchMessageTypes = [...nomalMessageTypes, ...tipMessageTypes];
