#pragma once

#include <stdbool.h>
#include <stdint.h>

struct terminal;
struct wl_window;

bool tabs_is_active(const struct terminal *term);
void tabs_activate(struct terminal *term);
void tabs_select(struct terminal *term, unsigned index);
void tabs_step(struct terminal *term, int direction);
bool tabs_new(struct terminal *term);
void tabs_detach(struct terminal *term);
void tabs_close_window(struct wl_window *win);
bool tabs_resize(struct wl_window *win, int width, int height, uint8_t opts);
void tabs_refresh_layout(struct wl_window *win);
void tabs_mark_activity(struct terminal *term, bool bell);
