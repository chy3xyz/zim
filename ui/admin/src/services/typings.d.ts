declare namespace API {
  type Pagination = {
    pageNumber: number;
    showNumber: number;
  };

  declare namespace AccountManage {
    type Account = {
      adminAccount: string;
      adminToken: string;
      adminUserID: string;
      faceURL: string;
      imToken: string;
      imUserID: string;
      level: number;
      nickname: string;
    };

    type AccountInfo = {
      account: string;
      createTime: number;
      faceURL: string;
      level: number;
      nickname: string;
      password: string;
      userID: string;
    };

    type AdminLoginParams = {
      account: string;
      password: string;
    };

    type UpdateAdminInfoParams = {
      nickname?: string;
      faceURL?: string;
      password?: string;
      userID: string;
    };

    type ChangeAdminPwdParams = {
      userID: string;
      newPassword: string;
      currentPassword: string;
    };
  }

  declare namespace UserManage {
    type User = {
      account: string;
      allowAddFriend: number;
      allowBeep: number;
      allowVibration: number;
      areaCode: string;
      birth: number;
      email: string;
      faceURL: string;
      gender: number;
      globalRecvMsgOpt: GlobalRecvMsgOpt;
      level: number;
      nickname: string;
      password: string;
      phoneNumber: string;
      registerType: number;
      userID: string;
      onlineStr?: string;
      inGroup?: boolean;
    };

    enum Platform {
      iOS = 1,
      Android = 2,
      Windows = 3,
      MacOSX = 4,
      Web = 5,
      Linux = 7,
      AndroidPad = 8,
      iPad = 9,
    }

    type GetUserParams = {
      keyword?: string;
      pagination: Pagination;
    };

    type GetUserForIMParams = {
      userName?: string;
      userID?: string;
      pagination: Pagination;
    };

    type GetUserResult = {
      users: User[];
      total: number;
    };

    type GetFriendsParams = {
      userID?: string;
      pagination: Pagination;
    };

    type FriendUser = {
      appMangerLevel: number;
      createTime: number;
      ex: string;
      faceURL: string;
      globalRecvMsgOpt: number;
      nickname: string;
      userID: string;
    };

    type FriendsInfo = {
      addSource: number;
      createTime: number;
      ex: string;
      friendUser: FriendUser;
      isPinned: false;
      operatorUserID: string;
      ownerUserID: string;
      remark: string;
    };

    type GetFriendsResult = {
      friendsInfo: FriendsInfo[];
      total: number;
    };

    type GetUsersOnlineStatusParams = {
      userIDs: string[];
    };

    type UserPlatformInfo = {
      platformID: Platform;
      token: string[];
      total: number;
    };

    type GetUsersOnlineStatusResult = {
      singlePlatformToken: UserPlatformInfo[];
      status: string;
      userID: string;
    };

    type UpdateUserInfoParams = {
      userID: string;
    } & Partial<User>;

    type RegisterUserInfo = {
      areaCode: string;
      birth?: number;
      faceURL?: string;
      gender?: number;
      nickname: string;
      password: string;
      phoneNumber: string;
      registerType?: number;
    };

    type RegisterUserParams = {
      user: RegisterUserInfo;
    };

    type ResetUserPasswordParams = {
      userID: string;
      newPassword: string;
    };

    type UpdateBlockParams = {
      userID: string;
      reason: string;
    };

    type DeleteBlockParams = {
      userIDs: string[];
    };

    type DeleteFriendParams = {
      ownerUserID: string;
      friendUserID: string;
    };

    type KickUserParams = {
      userID: string;
      platformID: number;
    };
  }

  declare namespace DefaultManage {
    type GetDefaultFriendsParams = {
      keyword: string;
      pagination: Pagination;
    };

    type DefaultFriends = {
      userID: string;
      user: AccountManage.AccountInfo;
      createTime: number;
    };

    type GetDefaultFriendsResult = {
      users: DefaultFriends[];
      total: number;
    };

    type GetDefaultGroupParams = {
      pagination: Pagination;
    };

    type GetDefaultGroupResult = {
      groups: GroupManage.GroupInfo[];
      total: number;
    };
  }

  declare namespace GroupManage {
    type GetGroupParams = {
      groupName?: string;
      groupID?: string;
      pagination: {
        pageNumber: number;
        showNumber: number;
      };
    };

    type Groups = {
      groupInfo: GroupInfo;
      groupOwnerUserID: string;
      groupOwnerUserName: string;
    };

    type GetGroupResult = {
      groups: Groups[];
      total: number;
    };

    type CreateGroupParams = {
      memberUserIDs: string[];
      adminUserIDs: string[];
      ownerUserID: string;
      groupInfo: Partial<GroupInfo>;
    };

    type GroupInfo = {
      applyMemberFriend: number;
      createTime: number;
      creatorUserID: string;
      ex: string;
      faceURL: string;
      groupID: string;
      groupName: string;
      groupType: number;
      introduction: string;
      lookMemberInfo: number;
      memberCount: number;
      needVerification: number;
      notification: string;
      notificationUpdateTime: number;
      notificationUserID: string;
      ownerUserID: string;
      status: number;
    };

    type UpdateGroupParams = {
      groupInfoForSet: Partial<GroupInfo>;
    };

    type GroupMember = {
      appMangerLevel: number;
      ex: string;
      faceURL: string;
      groupID: string;
      inviterUserID: string;
      joinSource: number;
      joinTime: number;
      muteEndTime: number;
      nickname: string;
      operatorUserID: string;
      roleLevel: number;
      userID: string;
    };

    type GetGroupMembersParams = {
      keyword?: string;
      groupID: string;
      pagination: {
        pageNumber: number;
        showNumber: number;
      };
    };

    type GetGroupMembersResult = {
      members: GroupMember[];
      total: number;
    };

    type GetSomeGroupMembersParams = {
      groupID: string;
      userIDs: string[];
    };

    type MuteGroupMemebrParams = {
      mutedSeconds: number;
      userID: string;
      groupID: string;
    };

    type KickGroupMemebrParams = {
      groupID: string;
      kickedUserIDs: string[];
      reason: '';
    };

    type InviteGroupMemebrParams = {
      groupID: string;
      invitedUserIDs: string[];
      reason: '';
    };

    type UpdateGroupMemebrParams = {
      members: [
        {
          ex?: string;
          groupID: string;
          nickname?: string;
          roleLevel?: number;
          userGroupFaceUrl?: string;
          userID: string;
        },
      ];
    };

    type TransferGroupParams = {
      newOwnerUserID: string;
      oldOwnerUserID: string;
      groupID: string;
    };
  }

  declare namespace ChatLog {
    type GetChatLogParams = {
      sendID?: string;
      recvID?: string;
      contentType: number;
      sendTime?: string;
      sessionType: number;
      pagination: {
        pageNumber: number;
        showNumber: number;
      };
    };

    type ChatLog = {
      clientMsgID: string;
      content: string;
      contentType: number;
      createTime: number;
      ex: string;
      groupFaceURL: string;
      groupID: string;
      groupMemberCount: number;
      groupName: string;
      groupOwner: string;
      groupType: number;
      msgFrom: number;
      recvID: string;
      recvNickname: string;
      sendID: string;
      sendTime: number;
      senderFaceURL: string;
      senderNickname: string;
      senderPlatformID: number;
      seq: number;
      serverMsgID: string;
      sessionType: number;
      status: number;
    };

    type ChatLogs = {
      chatLog: ChatLog;
      isRevoked: boolean;
    };

    type GetChatLogResult = {
      chatLogs: ChatLogs[];
      chatLogsNum: number;
    };

    type RevokeMessageParams = {
      conversationID: string;
      seq: number;
      userID: string;
    };

    type OfflinePushInfo = {
      desc: string;
      ex: string;
      iOSBadgeCount: boolean;
      iOSPushSound: string;
      title: string;
    };

    type BatchSendParams = {
      recvIDList: string[];
      sendID: string;
      text: string;
      pictureElem?: {
        sourcePicture: PicBaseInfo;
        bigPicture: PicBaseInfo;
        snapshotPicture: PicBaseInfo;
      };
      externalUrl?: string;
      isSendAll: boolean;
      senderNickname: string;
      senderFaceURL: string;
      mixType: number;
    };

    type PicBaseInfo = {
      uuid: string;
      type: string;
      size: number;
      width: number;
      height: number;
      url: string;
    };
  }

  declare namespace NotificationManage {
    type Account = {
      userID: string;
      nickName: string;
      faceURL: string;
    };

    type QueryNotificationAccountParams = {
      keyword?: string;
      pagination: {
        pageNumber: number;
        showNumber: number;
      };
    };

    type QueryNotificationAccountResult = {
      notificationAccounts: Account[];
      total: number;
    };

    type UpdateNotificationAccountParams = {
      userID: string;
      nickName?: string;
      faceURL?: string;
    };
  }

  declare namespace AppManage {
    type GetAllowRegisterResult = {
      allowRegister: boolean;
    };

    type Version = {
      id: string;
      platform: string;
      version: string;
      url: string;
      text: string;
      force: boolean;
      latest: boolean;
      hot: boolean;
    };

    type DeleteVersionParams = {
      id: string[];
    };

    type AddVersionParams = Omit<Version, 'id'>;

    type GetVersionListParams = {
      platform: string[];
      pagination: Pagination;
    };

    type GetVersionListResult = {
      total: number;
      versions: Version[];
    };
  }

  declare namespace LogManage {
    type SearchLogs = {
      keyword?: string;
      startTime?: number;
      endTime?: number;
      pagination: {
        pageNumber: number;
        showNumber: number;
      };
    };

    type LogItem = {
      filename: string;
      nickname: string;
      userID: string;
      platform: number;
      createTime: number;
      url: string;
      logID: string;
      systemType: string;
      version: string;
      ex: string;
    };
  }

  declare namespace OrganizationManage {
    type Organization = {
      logoURL: string;
      name: string;
      homepage: string;
      introduction: string;
      createTime?: string;
    };

    type Department = {
      departmentID: string;
      faceURL: string;
      name: string;
      createTime: string;
      memberNum: number;
      position: string;
      order: number;
      memberPosition?: string;
    };

    type DepartmentList = {
      department: Department;
      subdepartments: DepartmentList[];
    };

    type GetAllOrganizationResult = {
      departments: DepartmentList[];
    };

    type UserInfo = {
      disabled?: boolean;
      user: User;
      member: Member;
      members: Member[];
    };

    type Member = {
      departmentID: string;
      position: string;
      station: string;
      createTime: number;
    };

    type GetUserInfoResult = {
      users: {
        user: User;
        members: Member[];
      }[];
    };

    type GetDepartmentUserResult = {
      members: UserInfo[];
    };

    type CreateDeartmentParams = {
      name: string;
      parentDepartmentID: string;
    };

    type UpdateDeartmentParams = {
      name: string;
      departmentID: string;
    };

    type RemoveMemberParams = {
      list: { departmentID: string; userID: string }[];
    };

    type BlockMemberParams = {
      userID: string;
      op: 1 | 2;
    };

    type CreateUserParams = {
      user: {
        nickname: string;
        birth?: number;
        email?: string;
        englishName?: string;
        faceURL?: string;
        gender?: number;
        areaCode?: string;
        phoneNumber?: string;
        account: string;
        password: string;
      };
      departments: {
        departmentID: string;
        position: string;
      }[];
    };

    type UpdateUserInfoParams = {
      userID: string;
      birth?: number;
      email?: string;
      englishName?: string;
      faceURL?: string;
      gender?: number;
      mobile?: string;
      nickname?: string;
      telephone?: string;
    };

    type UpdateUserDepartmentParams = {
      userID: string;
      departmentID: string;
      position: string;
      station: string;
      entryTime?: number;
      terminationTime?: number;
    };

    type MoveUserDepartmentParams = {
      moves: {
        currentDepartmentID?: string;
        departmentID: string;
        position?: string;
        userID: string;
      }[];
    };

    type SortDepartment = {
      departmentID: string;
      nextDepartmentID: string;
    };
  }

  declare namespace SplitUpload {
    interface CommonOptions {
      operationID: string;
      token: string;
    }
    interface UploadParams {
      hash: string;
      size: number;
      partSize: number;
      maxParts: number;
      cause: string;
      name: string;
      contentType: string;
    }
    interface ConfirmData {
      uploadID: string;
      parts: string[];
      cause: string;
      name: string;
      contentType: string;
    }
    interface UploadData {
      url: string;
      upload: Upload;
    }
    interface Upload {
      uploadID: string;
      partSize: number;
      sign: Sign;
    }
    interface Sign {
      url: string;
      query?: KeyForValueList[];
      header?: KeyForValueList[];
      parts: Part[];
    }
    interface Part {
      partNumber: number;
      url: string;
      query?: KeyForValueList[];
      header?: KeyForValueList[];
    }
    interface KeyForValueList {
      key: string;
      values: string[];
    }
  }
}
