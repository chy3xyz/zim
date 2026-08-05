### OpenIM
A OpenIM flutter demo, only support android and ios.

### 当前项目运行环境：flutter stable 3.32.8, XCode: 26.1.1, Android Studio: Koala | 2024.1.1 Patch, JDK: 17

### 源码使用

#### 拿到代码后，执行以下脚本，主要是更新依赖，添加namespace等

```dart
  cd shell/
  ./flutter_pub_get.sh
```

##### 1，替换 app icon

- ###### 将你的应用的icon设计图放到launcher_icon文件夹中，命名为app-icon.png

- ###### 执行命令:

```dart
  flutter pub run flutter_launcher_icons:main
```

##### 2， 替换 app 的名称

- ###### Android：修改 openim/android/app/src/main/res/AndroidManifest.xm文件里 android:label的值

```xml
  <application
    android:icon="@mipmap/ic_launcher"
    android:label="您的应用名"
    android:requestLegacyExternalStorage="true"
    android:usesCleartextTraffic="true"
    tools:replace="android:label">
</application>
```
- ###### ios：用xcode打开工程修改应用名

##### 3，替换 openim/openim_common/lib/src/config.dart 文件里的服务器地址为自己的服务器地址

##### 4，连接并选择真机

##### 5，执行  melos pub_get

##### 6，执行 flutter run

##### 7, 打包
  1. 根目录依次执行以下命令：
      - flutter clean
      - melos pub_get
  2. 打包Android执行命令:
      - flutter build apk
  4. 打包iOS依次执行以下命令:
      - cd ios
      - rm -f Podfile.lock
      - rm -rf Pods
      - pod repo update
      - pod install
      - flutter build ipa

### Issues

##### 1，支持哪些平台？

答：因为sdk的原因demo目前只能运行在android跟ios设备上，如果要尝试桌面，请参考[desktop+mobile](https://github.com/std-s/open_im_sdk)

##### 2，android安装包debug可以运行但release启动白屏？

答：flutter的release包默认是开启了混淆，可以使用命令：flutter build release --no -shrink，如果此命令无效可如下操作

在android/app/build.gradle配置的release配置加入以下配置

```
release {
    minifyEnabled false
    useProguard false
    shrinkResources false
}
```

##### 3，代码必须混淆怎么办？

答：在混淆规则里加入以下规则

```
-keep class io.openim.**{*;}
-keep class open_im_sdk.**{*;}
-keep class open_im_sdk_callback.**{*;}
```

##### 4，android安装包不能安装在模拟器上？

答：因为Demo去掉了某些cpu架构，如果你想运行在模拟器上请按以下方式：

在android/build.gradle配置加入

```
ndk {
    abiFilters "arm64-v8a", "armeabi-v7a", "armeabi", "x86", "x86_64"
}
```

##### 5，ios构建release包报错

答：请将cpu架构设置为arm64，然后依次如下操作

- flutter clean
- flutter pub get
- cd ios
- rm -f Podfile.lock
- rm -rf Pods
- pod update
- flutter build ipa / Archive

![ios cpu](https://user-images.githubusercontent.com/7018230/155913400-6231329a-aee9-4082-8d24-a25baad55261.png)

##### 6，ios运行的最低版本号？

答：13.0
```
