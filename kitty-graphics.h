#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

struct terminal;
struct kg_engine;

/* The protocol/store and placement policy are Zig; native hooks are C ABI only. */
struct kg_metrics {
    int32_t columns, rows, cell_width, cell_height;
    int32_t cursor_col, cursor_row;
    int32_t screen;                 /* 0 normal, 1 alternate */
    int32_t scrollback_rows;
};
struct kg_placement {
    const uint8_t *rgba;
    uint32_t image_width, image_height;
    int32_t col, row, screen, z;
    uint32_t columns, rows, x_offset, y_offset;
    uint32_t source_x, source_y, source_width, source_height;
};
struct kg_canvas {
    int32_t width, height, cell_width, cell_height;
    int32_t margin_left, margin_top, columns, rows;
    int32_t screen, history_offset;
};

struct kg_engine *kg_new(struct terminal *term);
void kg_free(struct kg_engine *engine);
void kg_begin(struct kg_engine *engine);
void kg_put(struct kg_engine *engine, uint8_t byte);
void kg_end(struct kg_engine *engine);
void kg_abort(struct kg_engine *engine);
void kg_scroll(struct kg_engine *engine, int32_t screen, int32_t top,
               int32_t bottom, int32_t rows, int32_t history_limit);
void kg_clear_screen(struct kg_engine *engine, int32_t screen);
void kg_reset(struct kg_engine *engine);
size_t kg_placement_count(struct kg_engine *engine);
bool kg_get_placement(struct kg_engine *engine, size_t index,
                      struct kg_placement *out);
void kg_render(struct kg_engine *engine, struct terminal *term, void *pix,
                bool foreground, bool linear);

void kg_native_metrics(struct terminal *term, struct kg_metrics *out);
void kg_native_canvas(struct terminal *term, struct kg_canvas *out);
void kg_native_reply(struct terminal *term, const uint8_t *data, size_t size);
void kg_native_damage(struct terminal *term);
void kg_native_advance(struct terminal *term, uint32_t columns, uint32_t rows);
/* Codecs return malloc-owned RGBA bytes; failure never returns partial output. */
uint8_t *kg_native_png(const uint8_t *data, size_t size,
                        uint32_t *width, uint32_t *height);
bool kg_native_inflate(const uint8_t *data, size_t size,
                        uint8_t *out, size_t out_size);
void kg_native_paint(void *pix, const uint8_t *rgba, uint32_t width, uint32_t height,
                     int32_t x, int32_t y, int32_t target_width, int32_t target_height,
                     uint32_t source_x, uint32_t source_y,
                     uint32_t source_width, uint32_t source_height,
                     int32_t clip_x, int32_t clip_y, int32_t clip_width,
                     int32_t clip_height, bool linear);
