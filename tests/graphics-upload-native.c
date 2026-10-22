/* Deterministic geometry for engine tests; unexpected codec/reply calls fail. */
#include "../kitty-graphics.h"
#include <stdlib.h>

void kg_native_metrics(struct terminal *term, struct kg_metrics *out)
{
    *out = (struct kg_metrics){.columns = 133, .rows = 40,
        .cell_width = 9, .cell_height = 18, .scrollback_rows = 1000};
}
void kg_native_canvas(struct terminal *term, struct kg_canvas *out) { abort(); }
void kg_native_reply(struct terminal *term, const uint8_t *data, size_t size) { abort(); }
void kg_native_damage(struct terminal *term) {}
void kg_native_advance(struct terminal *term, uint32_t columns, uint32_t rows) {}
uint8_t *kg_native_png(const uint8_t *data, size_t size,
                       uint32_t *width, uint32_t *height) { abort(); }
bool kg_native_inflate(const uint8_t *data, size_t size,
                       uint8_t *out, size_t out_size) { abort(); }
void kg_native_paint(void *pix, const uint8_t *rgba, uint32_t width, uint32_t height,
                     int32_t x, int32_t y, int32_t target_width, int32_t target_height,
                     uint32_t source_x, uint32_t source_y,
                     uint32_t source_width, uint32_t source_height,
                     int32_t clip_x, int32_t clip_y, int32_t clip_width,
                     int32_t clip_height, bool linear) { abort(); }
