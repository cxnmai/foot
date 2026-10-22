#include "kitty-graphics.h"

#include <stdlib.h>
#include <pixman.h>

#include "srgb.h"
#include "util.h"

void
kg_native_paint(void *pix, const uint8_t *rgba, uint32_t width, uint32_t height,
                int32_t x, int32_t y, int32_t target_width, int32_t target_height,
                uint32_t source_x, uint32_t source_y,
                uint32_t source_width, uint32_t source_height,
                int32_t clip_x, int32_t clip_y, int32_t clip_width,
                int32_t clip_height, bool linear)
{
    if (rgba == NULL || width == 0 || height == 0 || width > 8192 || height > 8192 ||
        (uint64_t)width * height * 4 > 64u * 1024 * 1024 ||
        source_x >= width || source_y >= height ||
        source_width == 0 || source_width > width - source_x ||
        source_height == 0 || source_height > height - source_y ||
        target_width <= 0 || target_height <= 0 || clip_width <= 0 || clip_height <= 0)
        return;

    int64_t left = max((int64_t)x, (int64_t)clip_x);
    int64_t top = max((int64_t)y, (int64_t)clip_y);
    int64_t right = min((int64_t)x + target_width, (int64_t)clip_x + clip_width);
    int64_t bottom = min((int64_t)y + target_height, (int64_t)clip_y + clip_height);
    left = max(left, 0);
    top = max(top, 0);
    right = min(right, pixman_image_get_width(pix));
    bottom = min(bottom, pixman_image_get_height(pix));
    if (right <= left || bottom <= top)
        return;

    /* Convert straight sRGB RGBA into pixman's premultiplied channel format. */
    uint32_t *pixels = malloc((size_t)source_width * source_height * sizeof(*pixels));
    if (pixels == NULL)
        return;
    for (uint32_t row = 0; row < source_height; row++) {
        for (uint32_t col = 0; col < source_width; col++) {
            const uint8_t *p = &rgba[((size_t)(row + source_y) * width + col + source_x) * 4];
            uint32_t a = p[3], rgb = a << 24;
            for (unsigned channel = 0; channel < 3; channel++) {
                uint32_t value = linear ? srgb_decode_8_to_16(p[channel]) / 257 : p[channel];
                rgb |= (value * a / 255) << (16 - 8 * channel);
            }
            pixels[(size_t)row * source_width + col] = rgb;
        }
    }
    pixman_image_t *src = pixman_image_create_bits(
        PIXMAN_a8r8g8b8, source_width, source_height, pixels, source_width * 4);
    if (src == NULL) {
        free(pixels);
        return;
    }
    pixman_transform_t transform;
    pixman_transform_init_scale(&transform,
        pixman_double_to_fixed((double)source_width / target_width),
        pixman_double_to_fixed((double)source_height / target_height));
    pixman_image_set_transform(src, &transform);
    pixman_image_set_filter(src, PIXMAN_FILTER_BILINEAR, NULL, 0);
    pixman_image_set_repeat(src, PIXMAN_REPEAT_PAD);
    pixman_image_composite32(PIXMAN_OP_OVER, src, NULL, pix,
        left - x, top - y, 0, 0, left, top, right - left, bottom - top);
    pixman_image_unref(src);
    free(pixels);
}
