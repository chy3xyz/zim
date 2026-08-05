/**
 * @name umi 的路由配置
 * @description 只支持 path,component,routes,redirect,wrappers,name,icon 的配置
 * @param path  path 只支持两种占位符配置，第一种是动态参数 :id 的形式，第二种是 * 通配符，通配符只能出现路由字符串的最后。
 * @param component 配置 location 和 path 匹配后用于渲染的 React 组件路径。可以是绝对路径，也可以是相对路径，如果是相对路径，会从 src/pages 开始找起。
 * @param routes 配置子路由，通常在需要为多个路径增加 layout 组件时使用。
 * @param redirect 配置路由跳转
 * @param wrappers 配置路由组件的包装组件，通过包装组件可以为当前的路由组件组合进更多的功能。 比如，可以用于路由级别的权限校验
 * @param name 配置路由的标题，默认读取国际化文件 menu.ts 中 menu.xxxx 的值，如配置 name 为 login，则读取 menu.ts 中 menu.login 的取值作为标题
 * @param icon 配置路由的图标，取值参考 https://ant.design/components/icon-cn， 注意去除风格后缀和大小写，如想要配置图标为 <StepBackwardOutlined /> 则取值应为 stepBackward 或 StepBackward，如想要配置图标为 <UserOutlined /> 则取值应为 user 或者 User
 * @doc https://umijs.org/docs/guides/routes
 */
export default [
  {
    layout: false,
    routes: [
      {
        name: 'login',
        path: '/login',
        component: './Login',
      },
      {
        component: './404',
      },
    ],
  },
  {
    path: '/dashboard',
    name: 'Dashboard',
    icon: 'LineChartOutlined',
    component: './Dashboard',
  },
  {
    path: '/chat',
    name: 'Chat',
    icon: 'MedicineBoxOutlined',
    routes: [
      {
        path: '/chat/user',
        name: 'User',
        routes: [
          {
            path: '/chat/user',
            redirect: '/chat/user/user_list',
          },
          {
            name: 'UserList',
            path: '/chat/user/user_list',
            component: './chat/user/UserList',
          },
          {
            name: 'BlockList',
            path: '/chat/user/block_list',
            component: './chat/user/BlockList',
          },
        ],
      },
      {
        path: '/chat/register',
        name: 'Register',
        routes: [
          {
            path: '/chat/register',
            redirect: '/chat/register/default_friends',
          },
          {
            name: 'DefaultFriends',
            path: '/chat/register/default_friends',
            component: './chat/register/DefaultFriends',
          },
          {
            name: 'DefaultGroup',
            path: '/chat/register/default_group',
            component: './chat/register/DefaultGroup',
          },
        ],
      },
      {
        path: '/chat/app',
        name: 'App',
        routes: [
          {
            path: '/chat/app',
            redirect: '/chat/app/allaw_register',
          },
          {
            name: 'AllawRegister',
            path: '/chat/app/allaw_register',
            component: './chat/app/AllawRegister',
          },
          {
            name: 'Version',
            path: '/chat/app/version',
            component: './chat/app/Version',
          },
        ],
      },
    ],
  },
  {
    path: '/im',
    name: 'IM',
    icon: 'MessageOutlined',
    routes: [
      {
        path: '/im/user',
        name: 'User',
        routes: [
          {
            path: '/im/user',
            redirect: '/im/user/user_list',
          },
          {
            name: 'UserList',
            path: '/im/user/user_list',
            component: './im/user/UserList',
          },
          {
            name: 'RelationList',
            path: '/im/user/relation_list',
            component: './im/user/RelationList',
            hideInMenu: true,
          },
        ],
      },
      {
        path: '/im/group',
        name: 'Group',
        routes: [
          {
            path: '/im/group',
            redirect: '/im/group/group_list',
          },
          {
            name: 'GroupList',
            path: '/im/group/group_list',
            component: './im/group/GroupList',
          },
          {
            name: 'GroupMember',
            path: '/im/group/group_member',
            component: './im/group/GroupMember',
            hideInMenu: true,
          },
        ],
      },
      {
        path: '/im/message',
        name: 'Message',
        routes: [
          {
            path: '/im/message',
            redirect: '/im/message/user_message',
          },
          {
            name: 'UserMassage',
            path: '/im/message/user_message',
            component: './im/message/UserMessage',
          },
          {
            name: 'GroupMessage',
            path: '/im/message/group_message',
            component: './im/message/GroupMessage',
          },
        ],
      },
      {
        path: '/im/log',
        name: 'Log',
        routes: [
          {
            path: '/im/log',
            redirect: '/im/log/log_list',
          },
          {
            name: 'LogList',
            path: '/im/log/log_list',
            component: './im/log/LogList',
          },
        ],
      },
      {
        path: '/im/notification',
        name: 'Notification',
        routes: [
          {
            path: '/im/notification',
            redirect: '/im/notification/account_list',
          },
          {
            name: 'AccountList',
            path: '/im/notification/account_list',
            component: './im/notification/AccountList',
          },
          {
            name: 'Publish',
            path: '/im/notification/publish',
            component: './im/notification/Publish',
          },
        ],
      },
    ],
  },
  {
    path: '/organization',
    name: 'Organization',
    icon: 'apartment',
    routes: [
      {
        path: '/organization',
        redirect: '/organization/manage',
      },
      {
        name: 'Manage',
        path: '/organization/manage',
        component: './organization/Manage',
      },
      {
        name: 'Edit',
        path: '/organization/edit',
        component: './organization/Edit',
      },
    ],
  },
  {
    path: '/profile',
    name: 'Profile',
    icon: 'Setting',
    routes: [
      {
        path: '/profile',
        redirect: '/profile/info',
      },
      {
        name: 'Info',
        path: '/profile/info',
        component: './profile/Info',
      },
      {
        name: 'Modify',
        path: '/profile/modify',
        component: './profile/Modify',
      },
    ],
  },
  {
    path: '/',
    redirect: '/chat/user/user_list',
  },
  {
    path: '*',
    layout: false,
    component: './404',
  },
];
