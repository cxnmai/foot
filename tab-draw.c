#include "tab-bridge.h"

#include <wchar.h>
#include <pixman.h>
#include <fcft/fcft.h>

#include "terminal.h"
#include "srgb.h"
#include "util.h"

static pixman_color_t
color(uint32_t rgb, uint16_t alpha, bool srgb)
{
    uint16_t channels[3];
    for (size_t i = 0; i < 3; i++) {
        uint8_t value = rgb >> (16 - 8 * i);
        uint16_t linear = srgb ? srgb_decode_8_to_16(value) : value * 257u;
        channels[i] = (uint32_t)linear * alpha / 65535;
    }
    return (pixman_color_t){channels[0], channels[1], channels[2], alpha};
}

int
foot_tab_char_width(uint32_t codepoint)
{
    return wcwidth(codepoint);
}

void
foot_tab_fill(void *pix, int x, int y, int width, int height,
              uint32_t rgb, uint16_t alpha, bool srgb)
{
    if (width <= 0 || height <= 0)
        return;
    pixman_color_t clr = color(rgb, alpha, srgb);
    pixman_image_t *src = pixman_image_create_solid_fill(&clr);
    if (src == NULL)
        return;
    pixman_image_composite32(PIXMAN_OP_SRC, src, NULL, pix,
                             0, 0, 0, 0, x, y, width, height);
    pixman_image_unref(src);
}

void
foot_tab_glyph(void *pix, struct terminal *term, uint32_t style,
               uint32_t codepoint, int x, int y, int clip_x, int clip_width,
               uint32_t foreground, bool srgb)
{
    struct fcft_font *font = term->fonts[style < 4 ? style : 0];
    if (font == NULL)
        font = term->fonts[0];
    const struct fcft_glyph *g = fcft_rasterize_char_utf32(font, codepoint, FCFT_SUBPIXEL_NONE);
    if (g == NULL)
        return;
    int gx = x + term->font_x_ofs + g->x;
    int gy = y + term->font_baseline - g->y;
    int left = max(gx, clip_x), top = max(gy, y);
    int right = min(gx + g->width, clip_x + clip_width);
    int bottom = min(gy + g->height, y + term->cell_height);
    if (right <= left || bottom <= top)
        return;
    pixman_color_t fg = color(foreground, 0xffff, srgb);
    pixman_image_t *src = pixman_image_create_solid_fill(&fg);
    if (src == NULL)
        return;
    pixman_image_composite32(PIXMAN_OP_OVER,
        g->is_color_glyph ? g->pix : src, g->is_color_glyph ? NULL : g->pix, pix,
        g->is_color_glyph ? left - gx : 0, g->is_color_glyph ? top - gy : 0,
        left - gx, top - gy, left, top, right - left, bottom - top);
    pixman_image_unref(src);
}
