// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Amoss contributors
#ifndef AMOSS_CONTROLS_H
#define AMOSS_CONTROLS_H

#include <stdbool.h>
#include "control_msg.h"

enum amoss_action {
    AMOSS_BACK,
    AMOSS_HOME,
    AMOSS_RECENTS,
    AMOSS_DISPLAY_OFF,
    AMOSS_DISPLAY_ON,
    AMOSS_WAKE_MIRROR,
};

typedef bool (*amoss_control_sink)(void *context, const struct sc_control_msg *msg);
bool amoss_controls_send(enum amoss_action action, amoss_control_sink sink, void *context);
bool amoss_controls_prepare_app_message(struct sc_control_msg *msg);

#endif
