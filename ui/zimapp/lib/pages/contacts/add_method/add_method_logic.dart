import 'package:zim_sdk/zim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/add_by_search/add_by_search_logic.dart';
import 'package:openim/routes/app_navigator.dart';

class AddContactsMethodLogic extends GetxController {
  dynamic scan() => AppNavigator.startScan();

  dynamic addFriend() =>
      AppNavigator.startAddContactsBySearch(searchType: SearchType.user);

  dynamic createGroup() => AppNavigator.startCreateGroup(
      defaultCheckedList: [OpenIM.iMManager.userInfo]);

  dynamic addGroup() =>
      AppNavigator.startAddContactsBySearch(searchType: SearchType.group);
}
