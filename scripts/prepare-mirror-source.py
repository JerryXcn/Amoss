#!/usr/bin/env python3
"""Apply the small, reproducible Amoss UI integration to pristine scrcpy sources."""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parent.parent
original = root / "build/mirror-sources/scrcpy-5.0.1"
target = root / "build/mirror-client-src"
shutil.copytree(original, target, dirs_exist_ok=True)
modified = set()

def replace(relative, before, after, count=1):
    path = target / relative
    text = path.read_text()
    if text.count(before) != count:
        raise RuntimeError(f"Upstream source changed: {relative}: {before!r}")
    path.write_text(text.replace(before, after))
    modified.add(relative)

replace("app/meson.build", "src = [", "src = [\n    'src/amoss_controls.c',\n    'src/amoss_toolbar.c',")
replace("app/src/controller.c", '#include "controller.h"',
        '#include "controller.h"\n#include "amoss_controls.h"\n#include <stdlib.h>\n#include <string.h>')
replace("app/src/controller.c", '    // RESIZE_DISPLAY messages are handled separately',
        '    struct sc_control_msg app_msg;\n'
        '    const char *app_window = getenv("AMOSS_APP_WINDOW");\n'
        '    if (app_window && !strcmp(app_window, "1")) {\n'
        '        app_msg = *msg;\n'
        '        if (!amoss_controls_prepare_app_message(&app_msg)) { return false; }\n'
        '        msg = &app_msg;\n'
        '    }\n'
        '    // RESIZE_DISPLAY messages are handled separately')
replace("app/src/scrcpy.c", '#include "scrcpy.h"', '#include "scrcpy.h"\n#include "amoss_toolbar.h"')
replace("app/src/scrcpy.c", '            LOGW("Could not request \'set display power\'");\n        }',
        '            LOGW("Could not request \'set display power\'");\n'
        '        } else if (screen_initialized) {\n'
        '            amoss_toolbar_set_display_power(&s->screen, false);\n'
        '            const char *wake = getenv("AMOSS_WAKE_MIRROR");\n'
        '            if (wake && !strcmp(wake, "1")) {\n'
        '                amoss_toolbar_wake_mirror(&s->screen);\n'
        '            }\n        }')
replace("app/src/screen.c", '#include "screen.h"', '#include "screen.h"\n#include "amoss_toolbar.h"')
replace("app/src/screen.c", '    if (screen->window_aspect_ratio_lock) {',
        '    if (amoss_toolbar_set_video_size(screen, content_size.width, content_size.height)) {\n'
        '        return; // Native resizing excludes the fixed-height toolbar.\n    }\n\n'
        '    if (screen->window_aspect_ratio_lock) {')
replace("app/src/screen.c", '    screen->window_shown = true;\n    sc_sdl_show_window(screen->window);',
        '    screen->window_shown = true;\n    amoss_toolbar_prepare_window(screen);\n'
        '    sc_sdl_show_window(screen->window);\n'
        '    amoss_toolbar_window_shown(screen);')
replace("app/src/screen.c", '    sc_input_manager_init(&screen->im, &im_params);',
        '    sc_input_manager_init(&screen->im, &im_params);\n    amoss_toolbar_install(screen);')
replace("app/src/screen.c", '    SDL_DestroyWindow(screen->window);',
        '    amoss_toolbar_destroy(screen);\n    SDL_DestroyWindow(screen->window);', count=2)
replace("app/src/screen.c", '            screen->disconnected = true;',
        '            screen->disconnected = true;\n            amoss_toolbar_set_enabled(screen, false);')
replace("app/src/screen.c", 'sc_screen_handle_event(struct sc_screen *screen, const SDL_Event *event) {',
        'sc_screen_handle_event(struct sc_screen *screen, const SDL_Event *event) {\n'
        '    if (amoss_toolbar_consumes_event(screen, event)) { return; }')
replace("app/src/screen.c", '            uint16_t height = event->data2;',
        '            int footer = amoss_toolbar_height(screen->window);\n'
        '            uint16_t height = event->data2 > footer ? event->data2 - footer : 1;')
replace("app/src/screen.c", 'bounds->height = MAX(0, rect.h - DISPLAY_MARGINS);',
        'bounds->height = MAX(0, rect.h - DISPLAY_MARGINS - AMOSS_TOOLBAR_HEIGHT);')

replace("app/src/util/sdl.c", '#include "sdl.h"', '#include "sdl.h"\n#include "amoss_toolbar.h"')
replace("app/src/util/sdl.c", '    struct sc_size size = {',
        '    int footer = amoss_toolbar_height(window);\n'
        '    height = height > footer ? height - footer : 1;\n\n    struct sc_size size = {')
replace("app/src/util/sdl.c", 'SDL_SetWindowSize(window, size.width, size.height)',
        'SDL_SetWindowSize(window, size.width, size.height + amoss_toolbar_height(window))')

replace("app/src/input_manager.c", '#include "input_manager.h"',
        '#include "input_manager.h"\n#include "amoss_toolbar.h"')
replace("app/src/input_manager.c", '        LOGW("Could not request \'set screen power mode\'");\n    }',
        '        LOGW("Could not request \'set screen power mode\'");\n    } else {\n'
        '        amoss_toolbar_set_display_power(im->screen, on);\n    }')
# Touch coordinates are normalized against the full SDL window, including footer.
replace("app/src/input_manager.c", '    int32_t y = event->y * (int32_t) window_size.height;',
        '    int32_t y = event->y * ((int32_t) window_size.height + amoss_toolbar_height(im->screen->window));')

for name in ("amoss_controls.c", "amoss_controls.h", "amoss_toolbar.c", "amoss_toolbar.h"):
    shutil.copy2(root / "Integrations/Scrcpy" / name, target / "app/src" / name)
for relative in sorted(modified):
    path = target / relative
    marker = '# ' if path.suffix == '.build' else '// '
    path.write_text(marker + 'Modified by Amoss contributors, 2026: native controls, viewport and input integration.\n'
                    + marker + 'See AMOSS-MODIFICATIONS.txt. Original notices and Apache-2.0 license are retained.\n'
                    + path.read_text())
(target / "AMOSS-MODIFICATIONS.txt").write_text(
    "Amoss modifications (2026-10-17): native SwiftUI bottom toolbar, per-device "
    "system controls, display power toggle and video viewport reservation. "
    "Android server and protocol are unchanged. See the accompanying "
    "Integrations/Scrcpy sources and build scripts.\n\nModified upstream files:\n"
    + ''.join(f"- {name}\n" for name in sorted(modified)))
print(f"Prepared Amoss mirror sources: {target}")
