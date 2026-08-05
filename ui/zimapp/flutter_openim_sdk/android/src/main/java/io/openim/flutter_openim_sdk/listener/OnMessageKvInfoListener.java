package io.openim.flutter_openim_sdk.listener;

import io.openim.flutter_openim_sdk.util.CommonUtil;

public class OnMessageKvInfoListener implements open_im_sdk_callback.OnMessageKvInfoListener {

    // Aggregated kv after calculation, computed total count, determined if it
    // includes self
    @Override
    public void onMessageKvInfoChanged(String s) {
        CommonUtil.emitEvent("messageKvInfoListener", "onMessageKvInfoChanged", s);
    }
}
