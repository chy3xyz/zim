import component from './zh-CN/component';
import globalHeader from './zh-CN/globalHeader';
import menu from './zh-CN/menu';
import pages from './zh-CN/pages';
import pwa from './zh-CN/pwa';
import settingDrawer from './zh-CN/settingDrawer';
import chat from './zh-CN/chat';
import common from './zh-CN/common';
import message from './zh-CN/message';
import organization from './zh-CN/organization';
import app from './zh-CN/app';

export default {
  'navBar.lang': '语言',
  'layout.user.link.help': '帮助',
  'layout.user.link.privacy': '隐私',
  'layout.user.link.terms': '条款',

  'app.copyright.produced': 'OpenIM后台管理系统',
  ...pages,
  ...globalHeader,
  ...menu,
  ...settingDrawer,
  ...pwa,
  ...component,
  ...chat,
  ...common,
  ...message,
  ...organization,
  ...app,
};
