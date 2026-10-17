// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Amoss contributors
#ifndef AMOSS_TOOLBAR_H
#define AMOSS_TOOLBAR_H

#include <stdbool.h>
#include <SDL3/SDL.h>

#define AMOSS_TOOLBAR_HEIGHT 44
struct sc_screen;
void amoss_toolbar_install(struct sc_screen *screen);
void amoss_toolbar_destroy(struct sc_screen *screen);
void amoss_toolbar_set_enabled(struct sc_screen *screen, bool enabled);
void amoss_toolbar_set_display_power(struct sc_screen *screen, bool on);
void amoss_toolbar_wake_mirror(struct sc_screen *screen);
bool amoss_toolbar_set_video_size(struct sc_screen *screen, int width, int height);
void amoss_toolbar_prepare_window(struct sc_screen *screen);
void amoss_toolbar_window_shown(struct sc_screen *screen);
int amoss_toolbar_height(SDL_Window *window);
bool amoss_toolbar_consumes_event(struct sc_screen *screen, const SDL_Event *event);

#endif
