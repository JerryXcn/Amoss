// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Amoss contributors
// Amoss additions to the scrcpy client. Uses the existing per-device controller.
#include "amoss_controls.h"

// Keep application-window shortcuts on the virtual display. In particular,
// right-click must never wake the physical panel and HOME must not launch it.
bool
amoss_controls_prepare_app_message(struct sc_control_msg *msg) {
    switch (msg->type) {
        case SC_CONTROL_MSG_TYPE_BACK_OR_SCREEN_ON: {
            enum android_keyevent_action action = msg->back_or_screen_on.action;
            *msg = (struct sc_control_msg) {0};
            msg->type = SC_CONTROL_MSG_TYPE_INJECT_KEYCODE;
            msg->inject_keycode.action = action;
            msg->inject_keycode.keycode = AKEYCODE_BACK;
            return true;
        }
        case SC_CONTROL_MSG_TYPE_INJECT_KEYCODE:
            switch (msg->inject_keycode.keycode) {
                case AKEYCODE_HOME:
                case AKEYCODE_APP_SWITCH:
                case AKEYCODE_POWER:
                case AKEYCODE_SLEEP:
                case AKEYCODE_WAKEUP:
                case AKEYCODE_VOLUME_UP:
                case AKEYCODE_VOLUME_DOWN:
                case AKEYCODE_VOLUME_MUTE:
                    return false;
                default: return true;
            }
        case SC_CONTROL_MSG_TYPE_INJECT_TEXT:
        case SC_CONTROL_MSG_TYPE_INJECT_TOUCH_EVENT:
        case SC_CONTROL_MSG_TYPE_INJECT_SCROLL_EVENT:
        case SC_CONTROL_MSG_TYPE_GET_CLIPBOARD:
        case SC_CONTROL_MSG_TYPE_SET_CLIPBOARD:
        case SC_CONTROL_MSG_TYPE_START_APP:
        case SC_CONTROL_MSG_TYPE_RESET_VIDEO:
            return true;
        default: return false;
    }
}

bool
amoss_controls_send(enum amoss_action action, amoss_control_sink sink, void *context) {
    if (!sink) {
        return false;
    }
    struct sc_control_msg msg = {0};
    if (action == AMOSS_DISPLAY_OFF || action == AMOSS_DISPLAY_ON) {
        msg.type = SC_CONTROL_MSG_TYPE_SET_DISPLAY_POWER;
        msg.set_display_power.on = action == AMOSS_DISPLAY_ON;
        return sink(context, &msg);
    }
    switch (action) {
        case AMOSS_BACK: msg.inject_keycode.keycode = AKEYCODE_BACK; break;
        case AMOSS_HOME: msg.inject_keycode.keycode = AKEYCODE_HOME; break;
        case AMOSS_RECENTS: msg.inject_keycode.keycode = AKEYCODE_APP_SWITCH; break;
        // WAKEUP is idempotent: unlike POWER it never puts an awake device to sleep.
        // Send only after SET_DISPLAY_POWER(false), so the server keeps the panel off.
        case AMOSS_WAKE_MIRROR: msg.inject_keycode.keycode = AKEYCODE_WAKEUP; break;
        default: return false;
    }
    msg.type = SC_CONTROL_MSG_TYPE_INJECT_KEYCODE;
    msg.inject_keycode.action = AKEY_EVENT_ACTION_DOWN;
    if (!sink(context, &msg)) {
        return false;
    }
    msg.inject_keycode.action = AKEY_EVENT_ACTION_UP;
    return sink(context, &msg);
}
