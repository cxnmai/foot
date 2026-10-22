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
same(const struct fixture *a, const struct fixture *b)
{
    const struct terminal *x = &a->term, *y = &b->term;
    assert(x->grid->cursor.point.col == y->grid->cursor.point.col);
    assert(x->grid->cursor.point.row == y->grid->cursor.point.row);
    assert(x->grid->cursor.lcf == y->grid->cursor.lcf);
    assert(x->grid->cur_row == a->row_ptrs[x->grid->cursor.point.row]);
    assert(y->grid->cur_row == b->row_ptrs[y->grid->cursor.point.row]);
    assert(x->vt.last_printed == y->vt.last_printed);
    assert(memcmp(&x->vt.attrs, &y->vt.attrs, sizeof(x->vt.attrs)) == 0);
#if defined(FOOT_GRAPHEME_CLUSTERING)
    assert(x->vt.grapheme_state == y->vt.grapheme_state);
    assert(x->vt.codepoint_merging_ok == y->vt.codepoint_merging_ok);
#endif
    for (int r = 0; r < ROWS; r++) {
        assert(a->rows[r].dirty == b->rows[r].dirty);
        assert(a->rows[r].linebreak == b->rows[r].linebreak);
        assert(memcmp(a->cells[r], b->cells[r], sizeof(a->cells[r])) == 0);
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

int
main(void)
{
    struct fixture batch, reference;
    init(&batch, COLS, 0);
    init(&reference, COLS, 0);
    check_run(&batch, &reference, (const uint8_t *)"hello", 5, 5);
    return 0;
}
