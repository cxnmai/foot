#pragma once

#include <stdbool.h>

struct terminal;

int tab_bar_height(const struct terminal *term);
int tab_bar_height_for_size(const struct terminal *term, int available_height);
int tab_bar_y(const struct terminal *term);
void tab_bar_render(struct terminal *term, void *pix, bool srgb);
struct terminal *tab_bar_hit_test(struct terminal *term, int x, int y);
