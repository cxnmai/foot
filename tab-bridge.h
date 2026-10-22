#pragma once

/* Narrow C ABI: Zig owns tab policy/layout; C adapts existing foot internals. */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

struct terminal;
struct wl_window;

enum foot_tab_resize_options {
    FOOT_TAB_RESIZE_FORCE = 1 << 0,
    FOOT_TAB_RESIZE_BY_CELLS = 1 << 1,
    FOOT_TAB_RESIZE_KEEP_GRID = 1 << 2,
};

struct foot_tab_options {
    bool enabled;
    uint32_t min_tabs;
    uint32_t style;       /* 0 fade, 1 separator */
    uint32_t position;    /* 0 top, 1 bottom */
    uint32_t background;
    uint32_t active_foreground;
    uint32_t active_background;
    uint32_t inactive_foreground;
    uint32_t inactive_background;
    uint32_t active_font_style;
    uint32_t inactive_font_style;
    uint32_t max_title_length;
    uint32_t padding;
    const char *title_template;
    const char *active_title_template;
    const char *separator;
    int cell_width;
    int cell_height;
    int width;
    int height;
    uint16_t alpha;
};

struct wl_window *foot_tab_window(struct terminal *term);
struct terminal *foot_tab_active(struct wl_window *win);
size_t foot_tab_count(struct wl_window *win);
struct terminal *foot_tab_at(struct wl_window *win, size_t index);
bool foot_tab_is_live(struct terminal *term);
bool foot_tab_is_active(const struct terminal *term);
bool foot_tab_window_ready(struct wl_window *win);
void foot_tab_options(const struct terminal *term, struct foot_tab_options *out);
const char *foot_tab_title(struct terminal *term);
bool foot_tab_activity(struct terminal *term);
bool foot_tab_bell(struct terminal *term);
void foot_tab_activate_native(struct terminal *term);
struct terminal *foot_tab_spawn(struct terminal *term);
bool foot_tab_resize_one(struct terminal *term, int width, int height, uint8_t opts);
void foot_tab_save_size(struct wl_window *win);
void foot_tab_content_size(struct wl_window *win, int *width, int *height);
void foot_tab_close_begin(struct wl_window *win);
void foot_tab_shutdown(struct terminal *term);
void foot_tab_remove(struct terminal *term);
void foot_tab_destroy_window(struct terminal *term);
void foot_tab_finish_detach(struct terminal *term);
void foot_tab_mark_activity(struct terminal *term, bool bell);

/* Drawing primitives operate on pixman_image_t *, opaque to Zig. */
int foot_tab_char_width(uint32_t codepoint);
void foot_tab_fill(void *pix, int x, int y, int width, int height,
                   uint32_t rgb, uint16_t alpha, bool srgb);
void foot_tab_glyph(void *pix, struct terminal *term, uint32_t style,
                    uint32_t codepoint, int x, int y, int clip_x, int clip_width,
                    uint32_t foreground, bool srgb);
