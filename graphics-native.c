#include "kitty-graphics.h"

#include <stdlib.h>
#include <png.h>
#include <zlib.h>

#include "grid.h"
#include "render.h"
#include "terminal.h"
#include "tabs.h"

void
kg_native_metrics(struct terminal *term, struct kg_metrics *out)
{
    *out = (struct kg_metrics){
        .columns = term->cols, .rows = term->rows,
        .cell_width = term->cell_width, .cell_height = term->cell_height,
        .cursor_col = term->grid->cursor.point.col,
        .cursor_row = term->grid->cursor.point.row,
        .screen = term->grid == &term->alt,
        .scrollback_rows = term->grid->num_rows - term->rows,
    };
}

void
kg_native_canvas(struct terminal *term, struct kg_canvas *out)
{
    *out = (struct kg_canvas){
        .width = term->width, .height = term->height,
        .cell_width = term->cell_width, .cell_height = term->cell_height,
        .margin_left = term->margins.left, .margin_top = term->margins.top,
        .columns = term->cols, .rows = term->rows,
        .screen = term->grid == &term->alt,
        .history_offset = (term->grid->offset - term->grid->view + term->grid->num_rows)
                          & (term->grid->num_rows - 1),
    };
}

void
kg_native_reply(struct terminal *term, const uint8_t *data, size_t size)
{
    term_to_slave(term, data, size);
}

void
kg_native_damage(struct terminal *term)
{
    /* A burst may move the same image thousands of times before a frame.
     * Invalidate underlying text once, when that frame is actually painted. */
    term->render.graphics_damage = true;
    render_refresh(term);
    tabs_mark_activity(term, false);
}

void
kg_native_advance(struct terminal *term, uint32_t columns, uint32_t rows)
{
    /* Placement precedes scrolling, so the engine scroll hook moves its anchor. */
    term_cursor_right(term, columns > (uint32_t)term->cols ? term->cols : columns);
    if (rows > 8192)
        rows = 8192;
    for (uint32_t i = 0; i < rows; i++)
        term_linefeed(term);
}

bool
kg_native_inflate(const uint8_t *data, size_t size, uint8_t *out, size_t out_size)
{
    if (size > 64u * 1024 * 1024 || out_size > 64u * 1024 * 1024)
        return false;
    uLong input = size;
    uLongf output = out_size;
    int status = uncompress2(out, &output, data, &input);
    return status == Z_OK && output == out_size && input == size;
}

uint8_t *
kg_native_png(const uint8_t *data, size_t size, uint32_t *width, uint32_t *height)
{
    png_image png = {.version = PNG_IMAGE_VERSION};
    if (size == 0 || size > 64u * 1024 * 1024 ||
        !png_image_begin_read_from_memory(&png, data, size))
        return NULL;
    uint64_t bytes = (uint64_t)png.width * png.height * 4;
    if (png.width == 0 || png.height == 0 || png.width > 8192 || png.height > 8192 ||
        bytes > 64u * 1024 * 1024) {
        png_image_free(&png);
        return NULL;
    }
    png.format = PNG_FORMAT_RGBA;
    uint8_t *pixels = malloc(bytes);
    if (pixels == NULL || !png_image_finish_read(&png, NULL, pixels, 0, NULL)) {
        free(pixels);
        png_image_free(&png);
        return NULL;
    }
    *width = png.width;
    *height = png.height;
    png_image_free(&png);
    return pixels;
}
