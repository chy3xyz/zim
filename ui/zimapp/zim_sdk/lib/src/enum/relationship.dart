class AllowType {
  static const black = 0;
  static const friend = 1;
}

enum AddFriendPermission {
  allow(0), // 0: Allow to be added as a friend (requires approval)
  allowNoReview(1), // 1: Allow to be added as a friend (no approval needed)
  deny(2); // 2: Do not allow to be added as a friend

  final int value;

  const AddFriendPermission(this.value);
}
