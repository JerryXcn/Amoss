// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Amoss contributors
#include "amoss_toolbar.h"
#include "amoss_controls.h"
#include "screen.h"
#include "util/log.h"
#include <stdlib.h>

#define AMOSS_TOOLBAR_PROPERTY "amoss.native.toolbar"

// SwiftUI/AppKit bridge. All entry points run on scrcpy's main event thread.
extern void *amoss_native_install(void *window, void *context,
                                  bool (*action)(void *, int32_t));
extern void amoss_native_remove(void *toolbar);
extern void amoss_native_set_enabled(void *toolbar, bool enabled);
extern void amoss_native_set_display_power(void *toolbar, bool on);
extern void amoss_native_set_video_size(void *toolbar, int32_t width, int32_t height);
extern void amoss_native_prepare_window(void *toolbar);
extern void amoss_native_window_shown(void *toolbar);

struct amoss_toolbar {
    void *native;
    uint32_t video_buttons;
};

static struct amoss_toolbar *
toolbar_for(SDL_Window *window) {
    return SDL_GetPointerProperty(SDL_GetWindowProperties(window), AMOSS_TOOLBAR_PROPERTY, NULL);
}

static bool
send_message(void *context, const struct sc_control_msg *msg) {
    return sc_controller_push_msg(context, msg);
}

static bool
perform_action(void *context, int32_t action) {
    struct sc_screen *screen = context;
    if (screen->disconnected || !screen->controller) {
        return false;
    }
    bool ok = amoss_controls_send(action, send_message, screen->controller);
    if (!ok) {
        LOGW("Could not send Amoss system action");
    } else if (action == AMOSS_DISPLAY_OFF || action == AMOSS_DISPLAY_ON) {
        amoss_toolbar_set_display_power(screen, action == AMOSS_DISPLAY_ON);
    }
    return ok;
}

void
amoss_toolbar_install(struct sc_screen *screen) {
    if (!screen->video || screen->camera || !screen->controller) {
        return;
    }
    SDL_PropertiesID props = SDL_GetWindowProperties(screen->window);
    void *native_window = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
    if (!native_window) {
        return;
    }
    struct amoss_toolbar *toolbar = calloc(1, sizeof(*toolbar));
    if (toolbar) {
        toolbar->native = amoss_native_install(native_window, screen, perform_action);
        if (!SDL_SetPointerProperty(props, AMOSS_TOOLBAR_PROPERTY, toolbar)) {
            amoss_native_remove(toolbar->native);
            free(toolbar);
            return;
        }
        SDL_SetWindowMinimumSize(screen->window, 160, 160 + AMOSS_TOOLBAR_HEIGHT);
    }
}

void
amoss_toolbar_destroy(struct sc_screen *screen) {
    struct amoss_toolbar *toolbar = toolbar_for(screen->window);
    if (toolbar) {
        SDL_ClearProperty(SDL_GetWindowProperties(screen->window), AMOSS_TOOLBAR_PROPERTY);
        amoss_native_remove(toolbar->native);
        free(toolbar);
    }
}

int
amoss_toolbar_height(SDL_Window *window) {
    return toolbar_for(window) ? AMOSS_TOOLBAR_HEIGHT : 0;
}

void
amoss_toolbar_set_enabled(struct sc_screen *screen, bool enabled) {
    struct amoss_toolbar *toolbar = toolbar_for(screen->window);
    if (toolbar) {
        amoss_native_set_enabled(toolbar->native, enabled);
    }
}

void
amoss_toolbar_set_display_power(struct sc_screen *screen, bool on) {
    struct amoss_toolbar *toolbar = toolbar_for(screen->window);
    if (toolbar) {
        amoss_native_set_display_power(toolbar->native, on);
        LOGI("Amoss display power: %s", on ? "on" : "off");
    }
}

void
amoss_toolbar_wake_mirror(struct sc_screen *screen) {
    perform_action(screen, AMOSS_WAKE_MIRROR);
}

bool
amoss_toolbar_set_video_size(struct sc_screen *screen, int width, int height) {
    struct amoss_toolbar *toolbar = toolbar_for(screen->window);
    if (!toolbar) { return false; }
    amoss_native_set_video_size(toolbar->native, width, height);
    return true;
}

void
amoss_toolbar_prepare_window(struct sc_screen *screen) {
    struct amoss_toolbar *toolbar = toolbar_for(screen->window);
    if (toolbar) { amoss_native_prepare_window(toolbar->native); }
}

void
amoss_toolbar_window_shown(struct sc_screen *screen) {
    struct amoss_toolbar *toolbar = toolbar_for(screen->window);
    if (toolbar) { amoss_native_window_shown(toolbar->native); }
}

bool
amoss_toolbar_consumes_event(struct sc_screen *screen, const SDL_Event *event) {
    struct amoss_toolbar *toolbar = toolbar_for(screen->window);
    if (!toolbar) {
        return false;
    }
    int width, height;
    if (!SDL_GetWindowSize(screen->window, &width, &height)) {
        return false;
    }
    int video_height = height - AMOSS_TOOLBAR_HEIGHT;
    switch (event->type) {
        case SDL_EVENT_MOUSE_BUTTON_DOWN:
            if (event->button.y >= video_height) {
                return true;
            }
            toolbar->video_buttons |= SDL_BUTTON_MASK(event->button.button);
            return false;
        case SDL_EVENT_MOUSE_BUTTON_UP: {
            uint32_t mask = SDL_BUTTON_MASK(event->button.button);
            bool from_video = (toolbar->video_buttons & mask) != 0;
            toolbar->video_buttons &= ~mask;
            // Let a drag starting in the video release even over the toolbar.
            return !from_video;
        }
        case SDL_EVENT_MOUSE_MOTION:
            return event->motion.y >= video_height && !toolbar->video_buttons;
        case SDL_EVENT_MOUSE_WHEEL:
            return event->wheel.mouse_y >= video_height;
        default:
            return false;
    }
}
