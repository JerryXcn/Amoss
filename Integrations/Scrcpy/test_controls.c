// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Amoss contributors
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "amoss_controls.h"

struct receiver {
    uint8_t packets[4][16];
    size_t sizes[4];
    size_t count;
    bool disconnected;
};

static bool
receive(void *context, const struct sc_control_msg *msg) {
    struct receiver *receiver = context;
    if (receiver->disconnected) {
        return false;
    }
    uint8_t encoded[SC_CONTROL_MSG_MAX_SIZE];
    size_t size = sc_control_msg_serialize(msg, encoded);
    assert(size <= 16 && receiver->count < 4);
    memcpy(receiver->packets[receiver->count], encoded, size);
    receiver->sizes[receiver->count++] = size;
    return true;
}

static void
navigation_press_is_complete(enum amoss_action action, uint8_t android_code) {
    struct receiver device = {0};
    assert(amoss_controls_send(action, receive, &device));
    const uint8_t down[14] = {0, 0, 0, 0, 0, android_code, 0, 0, 0, 0, 0, 0, 0, 0};
    const uint8_t up[14] = {0, 1, 0, 0, 0, android_code, 0, 0, 0, 0, 0, 0, 0, 0};
    assert(device.count == 2);
    assert(device.sizes[0] == 14 && device.sizes[1] == 14);
    assert(!memcmp(device.packets[0], down, 14));
    assert(!memcmp(device.packets[1], up, 14));
}

int main(void) {
    struct sc_control_msg app_message = {0};
    app_message.type = SC_CONTROL_MSG_TYPE_SET_DISPLAY_POWER;
    assert(!amoss_controls_prepare_app_message(&app_message));
    app_message.type = SC_CONTROL_MSG_TYPE_INJECT_KEYCODE;
    app_message.inject_keycode.keycode = AKEYCODE_HOME;
    assert(!amoss_controls_prepare_app_message(&app_message));
    app_message.inject_keycode.keycode = AKEYCODE_POWER;
    assert(!amoss_controls_prepare_app_message(&app_message));
    app_message.inject_keycode.keycode = AKEYCODE_7;
    assert(amoss_controls_prepare_app_message(&app_message));
    app_message.type = SC_CONTROL_MSG_TYPE_BACK_OR_SCREEN_ON;
    app_message.back_or_screen_on.action = AKEY_EVENT_ACTION_UP;
    assert(amoss_controls_prepare_app_message(&app_message));
    assert(app_message.type == SC_CONTROL_MSG_TYPE_INJECT_KEYCODE);
    assert(app_message.inject_keycode.keycode == AKEYCODE_BACK);
    assert(app_message.inject_keycode.action == AKEY_EVENT_ACTION_UP);
    app_message.type = SC_CONTROL_MSG_TYPE_SET_CLIPBOARD;
    assert(amoss_controls_prepare_app_message(&app_message));
    navigation_press_is_complete(AMOSS_BACK, 4);
    navigation_press_is_complete(AMOSS_HOME, 3);
    navigation_press_is_complete(AMOSS_RECENTS, 187);
    navigation_press_is_complete(AMOSS_WAKE_MIRROR, 224);

    struct receiver first = {0}, second = {0};
    assert(amoss_controls_send(AMOSS_DISPLAY_OFF, receive, &first));
    assert(first.count == 1 && second.count == 0);
    assert(first.sizes[0] == 2);
    assert(first.packets[0][0] == 10 && first.packets[0][1] == 0);
    assert(amoss_controls_send(AMOSS_DISPLAY_ON, receive, &second));
    assert(second.count == 1 && first.count == 1);
    assert(second.packets[0][0] == 10 && second.packets[0][1] == 1);

    // Startup queues panel-off before WAKEUP, never the POWER toggle.
    assert(amoss_controls_send(AMOSS_WAKE_MIRROR, receive, &first));
    assert(first.count == 3);
    assert(first.packets[0][0] == 10 && first.packets[0][1] == 0);
    assert(first.packets[1][5] == 224 && first.packets[2][5] == 224);

    second.disconnected = true;
    assert(!amoss_controls_send(AMOSS_HOME, receive, &second));
    assert(second.count == 1);
    assert(!amoss_controls_send(99, receive, &first));
    assert(first.count == 3);
    puts("PASS: application-window input isolation; navigation and WAKEUP key pairs; panel-off before wake; display power without locking; per-session routing; disconnected/invalid action rejection.");
}
