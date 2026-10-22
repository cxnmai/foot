#include "tabs.h"

#include <math.h>
#include <stdlib.h>
#include <sys/timerfd.h>

#include "config.h"
#include "ime.h"
#include "render.h"
#include "terminal.h"
#include "wayland.h"

bool
 tabs_is_active(const struct terminal *term)
{
    return term->window != NULL && term->window->term == term &&
           !term->window->closing && !term->shutdown.in_progress;
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
tabs_activate(struct terminal *next)
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
    render_refresh(next);
}
