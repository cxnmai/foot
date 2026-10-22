#include "tab-bridge.h"

#include <math.h>
#include <stdlib.h>
#include <sys/timerfd.h>

#include "config.h"
#include "ime.h"
#include "render.h"
#include "terminal.h"
#include "wayland.h"

bool
foot_tab_is_active(const struct terminal *term)
{
    return term->window != NULL && term->window->term == term &&
           !term->window->closing && !term->shutdown.in_progress;
}

struct wl_window *
foot_tab_window(struct terminal *term) { return term->window; }

struct terminal *
foot_tab_active(struct wl_window *win) { return win->term; }

size_t
foot_tab_count(struct wl_window *win) { return tll_length(win->tabs); }

struct terminal *
foot_tab_at(struct wl_window *win, size_t index)
{
    tll_foreach(win->tabs, it) {
        if (index-- == 0)
            return it->item;
    }
    return NULL;
}

bool
foot_tab_is_live(struct terminal *term) { return !term->shutdown.in_progress; }

bool
foot_tab_window_ready(struct wl_window *win)
{
    return win->is_configured && !win->closing;
}

const char *
foot_tab_title(struct terminal *term)
{
    return term->window_title != NULL ? term->window_title : "foot";
}

bool
foot_tab_activity(struct terminal *term) { return term->tab_activity; }

bool
foot_tab_bell(struct terminal *term) { return term->tab_bell; }

void
foot_tab_options(const struct terminal *term, struct foot_tab_options *out)
{
    const struct config *conf = term->conf;
    *out = (struct foot_tab_options){
        .enabled = conf->tab_bar.enabled,
        .min_tabs = conf->tab_bar.min_tabs,
        .style = conf->tab_bar.style,
        .position = conf->tab_bar.position,
        .background = conf->tab_bar.background,
        .active_foreground = conf->tab_bar.active_foreground,
        .active_background = conf->tab_bar.active_background,
        .inactive_foreground = conf->tab_bar.inactive_foreground,
        .inactive_background = conf->tab_bar.inactive_background,
        .active_font_style = conf->tab_bar.active_font_style,
        .inactive_font_style = conf->tab_bar.inactive_font_style,
        .max_title_length = conf->tab_bar.max_title_length,
        .padding = conf->tab_bar.padding,
        .title_template = conf->tab_bar.title_template,
        .active_title_template = conf->tab_bar.active_title_template,
        .separator = conf->tab_bar.separator,
        .cell_width = term->cell_width,
        .cell_height = term->cell_height,
        .width = term->width,
        .height = term->height,
        .alpha = term->colors.alpha,
    };
}

static void
hide_surface(struct wayl_sub_surface *surf)
{
    if (surf->surface.surf != NULL) {
        wl_surface_attach(surf->surface.surf, NULL, 0, 0);
        wl_surface_commit(surf->surface.surf);
    }
}

static void
transfer_focus(struct terminal *old, struct terminal *next)
{
    tll_foreach(old->wl->seats, it) {
        struct seat *seat = &it->item;
        if (seat->ime_focus == old) {
            ime_disable(seat);
            ime_reset_pending(seat);
            ime_reset_preedit(seat);
            seat->ime_focus = next;
            ime_enable(seat);
            ime_update_cursor_rect(seat);
        }
        if (seat->kbd_focus == old) {
            if (!seat->kbd.repeat.dont_re_repeat)
                timerfd_settime(seat->kbd.repeat.fd, 0, &(struct itimerspec){0}, NULL);
            if (seat->kbd.xkb_compose_state != NULL)
                xkb_compose_state_reset(seat->kbd.xkb_compose_state);
            seat->kbd_focus = next;
        }
        if (seat->mouse_focus == old) {
            seat->mouse_focus = next;
            next->active_surface = old->active_surface;
            tll_free(seat->mouse.buttons);
            seat->mouse.count = 0;
            seat->mouse.aggregated[0] = seat->mouse.aggregated[1] = 0;
            seat->mouse.aggregated_120[0] = seat->mouse.aggregated_120[1] = 0;
            fdm_del(old->fdm, old->selection.auto_scroll.fd);
            old->selection.auto_scroll.fd = -1;
        }
        if (seat->touch.surface != NULL &&
            wl_surface_get_user_data(seat->touch.surface) == old->window)
        {
            seat->touch.surface = NULL;
            seat->touch.state = TOUCH_STATE_IDLE;
        }
    }
    term_kbd_focus_out(old);
    tll_foreach(next->wl->seats, it) {
        if (it->item.kbd_focus == next)
            term_kbd_focus_in(next);
        if (it->item.mouse_focus == next)
            term_xcursor_update_for_seat(next, &it->item);
    }
}

void
foot_tab_activate_native(struct terminal *next)
{
    struct wl_window *win = next->window;
    struct terminal *old = win->term;
    if (old == next)
        return;

    render_wait_for_preapply_damage(old);
    hide_surface(&win->search);
    hide_surface(&win->overlay);
    hide_surface(&win->scrollback_indicator);
    tll_foreach(win->urls, it) {
        wayl_win_subsurface_destroy(&it->item.surf);
        tll_remove(win->urls, it);
    }
    const bool focused = old->visual_focus;
    term_visual_focus_out(old);
    win->term = next;
    transfer_focus(old, next);
    next->tab_activity = next->tab_bell = false;
    if (focused)
        term_visual_focus_in(next);
    if (win->closing || next->shutdown.in_progress)
        return;
    wayl_win_alpha_changed(win);
    render_refresh_title(next);
    render_refresh_app_id(next);
    render_refresh_icon(next);
    term_damage_view(next);
    term_damage_margins(next);
    render_refresh_csd(next);
    render_refresh_search(next);
    render_refresh_urls(next);
    term_disable_app_sync_updates(next);
    render_refresh(next);
}

struct terminal *
foot_tab_spawn(struct terminal *term)
{
    struct config *conf = config_clone(term->conf);
    struct terminal *next = term_init(
        conf, term->fdm, term->reaper, term->wl, term->foot_exe, term->cwd,
        NULL, NULL, 0, NULL, NULL, NULL, NULL, term->window);
    if (next == NULL) {
        config_free(conf);
        free(conf);
        return NULL;
    }
    next->owned_conf = conf;
    return next;
}

bool
foot_tab_resize_one(struct terminal *term, int width, int height, uint8_t opts)
{
    if (term->window->term != term) {
        float old_scale = term->scale;
        bool scaled = term_update_scale(term);
        bool fonts = term_font_dpi_changed(term, old_scale);
        term_font_subpixel_changed(term);
        if (scaled || fonts)
            opts |= RESIZE_FORCE;
    }
    return render_resize(term, width, height, opts);
}

void
foot_tab_save_size(struct wl_window *win)
{
    win->content_width = roundf(win->term->width / win->term->scale);
    win->content_height = roundf(win->term->height / win->term->scale);
}

void
foot_tab_content_size(struct wl_window *win, int *width, int *height)
{
    *width = win->content_width;
    *height = win->content_height;
}

void
foot_tab_close_begin(struct wl_window *win)
{
    win->closing = true;
}

void
foot_tab_shutdown(struct terminal *term)
{
    term_shutdown(term);
}

void
foot_tab_remove(struct terminal *term)
{
    struct wl_window *win = term->window;
    if (win == NULL)
        return;
    render_wait_for_preapply_damage(term);
    tll_foreach(win->tabs, it) {
        if (it->item == term) {
            tll_remove(win->tabs, it);
            break;
        }
    }
}

void
foot_tab_destroy_window(struct terminal *term)
{
    term->window->closing = true;
    wayl_win_destroy(term->window);
}

void
foot_tab_finish_detach(struct terminal *term)
{
    term->window = NULL;
    tll_foreach(term->wl->seats, it) {
        if (it->item.kbd_focus == term)
            it->item.kbd_focus = NULL;
        if (it->item.mouse_focus == term)
            it->item.mouse_focus = NULL;
        if (it->item.ime_focus == term) {
            ime_disable(&it->item);
            ime_reset_pending(&it->item);
            ime_reset_preedit(&it->item);
            it->item.ime_focus = NULL;
        }
    }
}

void
foot_tab_mark_activity(struct terminal *term, bool bell)
{
    if (term->window == NULL || term->window->term == term)
        return;
    bool changed = bell ? !term->tab_bell : !term->tab_activity;
    if (bell)
        term->tab_bell = true;
    else
        term->tab_activity = true;
    if (changed)
        render_refresh(term->window->term);
}
