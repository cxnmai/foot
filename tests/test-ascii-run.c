/* Differential tests use the same scalar dispatch and grapheme reset as VT. */
#undef NDEBUG
#include <assert.h>
#include <string.h>

#include "../grid.h"

#define COLS 32
#define ROWS 4

struct fixture {
    struct terminal term;
    struct row rows[ROWS];
    struct row *row_ptrs[ROWS];
    struct cell cells[ROWS][COLS];
};

static void
init(struct fixture *f, int cols, int col)
{
    memset(f, 0, sizeof(*f));
    struct terminal *t = &f->term;
    t->cols = cols;
    t->rows = ROWS;
    t->auto_margin = true;
    t->scroll_region.end = ROWS;
    t->grid = &t->normal;
    t->normal = (struct grid){
        .num_rows = ROWS, .num_cols = cols, .rows = f->row_ptrs,
        .cur_row = &f->rows[0], .cursor.point.col = col,
    };
    t->vt.last_printed = U'!';
    t->vt.attrs = (struct attributes){
        .bold = true, .italic = true, .reverse = true, .underline = true,
        .fg_src = COLOR_RGB, .fg = 0x123456,
        .bg_src = COLOR_BASE256, .bg = 234,
    };
#if defined(FOOT_GRAPHEME_CLUSTERING)
    t->vt.grapheme_state = 17;
    t->vt.codepoint_merging_ok = false;
#endif
    for (int r = 0; r < ROWS; r++) {
        f->row_ptrs[r] = &f->rows[r];
        f->rows[r].cells = f->cells[r];
        for (int c = 0; c < COLS; c++) {
            f->cells[r][c].wc = CELL_SPACER;
            f->cells[r][c].attrs.clean = true;
            f->cells[r][c].attrs.selected = true;
        }
    }
    term_update_ascii_printer(t);
}

static void
scalar(struct terminal *t, uint8_t c)
{
    term_reset_grapheme_state(t);
    t->ascii_printer(t, c);
}

static void
same_ranges(const struct row_ranges *a, const struct row_ranges *b,
            enum row_range_type type)
{
    assert(a->count == b->count);
    for (int i = 0; i < a->count; i++) {
        const struct row_range *x = &a->v[i], *y = &b->v[i];
        assert(x->start == y->start && x->end == y->end);
        if (type == ROW_RANGE_URI) {
            assert(x->uri.id == y->uri.id);
            assert(strcmp(x->uri.uri, y->uri.uri) == 0);
        } else {
            assert(x->underline.style == y->underline.style);
            assert(x->underline.color_src == y->underline.color_src);
            assert(x->underline.color == y->underline.color);
        }
    }
}

static void
same(const struct fixture *a, const struct fixture *b)
{
    const struct terminal *x = &a->term, *y = &b->term;
    assert(x->grid->cursor.point.col == y->grid->cursor.point.col);
    assert(x->grid->cursor.point.row == y->grid->cursor.point.row);
    assert(x->grid->cursor.lcf == y->grid->cursor.lcf);
    assert(x->grid->cur_row == a->row_ptrs[x->grid->cursor.point.row]);
    assert(y->grid->cur_row == b->row_ptrs[y->grid->cursor.point.row]);
    assert(x->vt.last_printed == y->vt.last_printed);
    assert(x->ascii_printer == y->ascii_printer);
    assert(x->bits_affecting_ascii_printer.value == y->bits_affecting_ascii_printer.value);
    assert(x->charsets.selected == y->charsets.selected);
    assert(x->charsets.saved == y->charsets.saved);
    for (int i = 0; i < 4; i++)
        assert(x->charsets.set[i] == y->charsets.set[i]);
    assert(memcmp(&x->vt.attrs, &y->vt.attrs, sizeof(x->vt.attrs)) == 0);
#if defined(FOOT_GRAPHEME_CLUSTERING)
    assert(x->vt.grapheme_state == y->vt.grapheme_state);
    assert(x->vt.codepoint_merging_ok == y->vt.codepoint_merging_ok);
#endif
    for (int r = 0; r < ROWS; r++) {
        assert(a->rows[r].dirty == b->rows[r].dirty);
        assert(a->rows[r].linebreak == b->rows[r].linebreak);
        assert(memcmp(a->cells[r], b->cells[r], sizeof(a->cells[r])) == 0);
        const struct row_data *p = a->rows[r].extra, *q = b->rows[r].extra;
        assert((p == NULL) == (q == NULL));
        if (p != NULL) {
            same_ranges(&p->uri_ranges, &q->uri_ranges, ROW_RANGE_URI);
            same_ranges(&p->underline_ranges, &q->underline_ranges,
                        ROW_RANGE_UNDERLINE);
        }
    }
}

static void
check_run(struct fixture *batch, struct fixture *reference,
          const uint8_t *data, size_t len, size_t expected)
{
    assert(term_print_ascii_run(&batch->term, data, len) == expected);
    for (size_t i = 0; i < expected; i++)
        scalar(&reference->term, data[i]);
    same(batch, reference);
}

static void
test_input_boundaries(void)
{
    struct fixture batch, reference;
    for (unsigned byte = 0; byte <= 255; byte++) {
        for (size_t pos = 0; pos < 4; pos++) {
            uint8_t data[] = {' ', '~', 'A', 'z', '0', '!'};
            data[pos] = byte;
            for (size_t len = 0; len <= sizeof(data); len++) {
                for (int col = COLS - 4; col < COLS; col++) {
                    init(&batch, COLS, col);
                    init(&reference, COLS, col);
                    size_t n = 0;
                    while (n < len && n < (size_t)(COLS - col) &&
                           data[n] >= 0x20 && data[n] <= 0x7e)
                        n++;
                    check_run(&batch, &reference, data, len, n < 2 ? 0 : n);
                }
            }
        }
    }
    init(&batch, COLS, 0);
    init(&reference, COLS, 0);
    check_run(&batch, &reference, NULL, 0, 0);
}

static void
check_stream(struct fixture *batch, struct fixture *reference,
             const uint8_t *data, size_t len)
{
    for (size_t i = 0; i < len;) {
        size_t n = term_print_ascii_run(&batch->term, data + i, len - i);
        assert(n <= len - i);
        if (n == 0) {
            scalar(&batch->term, data[i]);
            n = 1;
        }
        for (size_t j = 0; j < n; j++)
            scalar(&reference->term, data[i + j]);
        same(batch, reference);
        i += n;
    }
}

static uint32_t
random_u32(void)
{
    static uint32_t state = 0x51a5c11;
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

static void
test_random_ascii_and_margins(void)
{
    struct fixture batch, reference;
    for (int iteration = 0; iteration < 2000; iteration++) {
        const int cols = 1 + random_u32() % COLS;
        const int col = random_u32() % cols;
        init(&batch, cols, col);
        init(&reference, cols, col);
        struct attributes attrs = {
            .bold = random_u32() & 1, .dim = random_u32() & 1,
            .italic = random_u32() & 1, .underline = random_u32() & 1,
            .strikethrough = random_u32() & 1, .blink = random_u32() & 1,
            .conceal = random_u32() & 1, .reverse = random_u32() & 1,
            .fg = random_u32() & 0xffffff, .fg_src = random_u32() % 4,
            .bg = random_u32() & 0xffffff, .bg_src = random_u32() % 4,
            .clean = random_u32() & 1, .selected = random_u32() & 1,
            .confined = random_u32() & 1, .url = random_u32() & 1,
        };
        batch.term.vt.attrs = reference.term.vt.attrs = attrs;
        batch.term.auto_margin = reference.term.auto_margin = random_u32() & 1;
        batch.term.grid->cursor.lcf = reference.term.grid->cursor.lcf =
            col == cols - 1 && (random_u32() & 1);
        uint8_t data[2 * COLS];
        for (size_t i = 0; i < sizeof(data); i++)
            data[i] = 0x20 + random_u32() % 95;
        check_stream(&batch, &reference, data, 2 * cols);
    }
    /* Exact right-margin fill, pending wrap, and disabled auto-wrap. */
    for (int wrap = 0; wrap <= 1; wrap++) {
        init(&batch, COLS, COLS - 2);
        init(&reference, COLS, COLS - 2);
        batch.term.auto_margin = reference.term.auto_margin = wrap;
        check_run(&batch, &reference, (const uint8_t *)"abcd", 4, 2);
        assert(batch.term.grid->cursor.lcf);
        check_run(&batch, &reference, (const uint8_t *)"cd", 2, 0);
        check_stream(&batch, &reference, (const uint8_t *)"cd", 2);
    }
}

static void
test_metadata_fallback(void)
{
    struct fixture batch, reference;
    for (int kind = 0; kind < 3; kind++) {
        init(&batch, COLS, 8);
        init(&reference, COLS, 8);
        struct fixture *fixtures[] = {&batch, &reference};
        for (int f = 0; f < 2; f++) {
            struct row *row = &fixtures[f]->rows[0];
            for (int col = 3; col < 21; col++) {
                if (kind != 1)
                    grid_row_uri_range_put(row, col, "https://example.org", 42);
                if (kind != 0)
                    grid_row_underline_range_put(row, col,
                        (struct underline_range_data){
                            .style = UNDERLINE_CURLY,
                            .color_src = COLOR_RGB, .color = 0xabcdef});
            }
        }
        const uint8_t data[] = "metadata";
        check_run(&batch, &reference, data, sizeof(data) - 1, 0);
        check_stream(&batch, &reference, data, sizeof(data) - 1);
        for (int f = 0; f < 2; f++)
            for (int r = 0; r < ROWS; r++)
                grid_row_reset_extra(&fixtures[f]->rows[r]);
    }
}

static void
test_generic_fallback(void)
{
    struct fixture batch, reference;
    const struct config conf = {.url.osc8_underline = OSC8_UNDERLINE_ALWAYS};
    for (int mode = 0; mode < 6; mode++) {
        init(&batch, COLS, 8);
        init(&reference, COLS, 8);
        struct fixture *fixtures[] = {&batch, &reference};
        for (int f = 0; f < 2; f++) {
            struct terminal *t = &fixtures[f]->term;
            t->conf = &conf;
            switch (mode) {
            case 0:
                t->insert_mode = t->bits_affecting_ascii_printer.insert_mode = true;
                break;
            case 1:
                t->charsets.set[G0] = CHARSET_GRAPHIC;
                t->bits_affecting_ascii_printer.charset = true;
                break;
            case 2:
                t->vt.underline.style = UNDERLINE_CURLY;
                t->bits_affecting_ascii_printer.underline_style = true;
                break;
            case 3:
                t->vt.underline.color_src = COLOR_RGB;
                t->vt.underline.color = 0x112233;
                t->bits_affecting_ascii_printer.underline_color = true;
                break;
            case 4:
                t->vt.osc8.uri = (char *)"https://example.org";
                t->vt.osc8.id = 123;
                t->bits_affecting_ascii_printer.osc8 = true;
                break;
            }
            term_update_ascii_printer(t);
            if (mode == 5) {
                t->charsets.set[G1] = CHARSET_GRAPHIC;
                term_single_shift(t, G1);
            }
        }
        const uint8_t data[] = "`q~ generic";
        check_run(&batch, &reference, data, sizeof(data) - 1, 0);
        check_stream(&batch, &reference, data, sizeof(data) - 1);
        for (int f = 0; f < 2; f++)
            for (int r = 0; r < ROWS; r++)
                grid_row_reset_extra(&fixtures[f]->rows[r]);
    }
}

int
main(void)
{
    test_input_boundaries();
    test_random_ascii_and_margins();
    test_metadata_fallback();
    test_generic_fallback();
    return 0;
}
