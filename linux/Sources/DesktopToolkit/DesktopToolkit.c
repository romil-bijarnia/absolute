#include "DesktopToolkit.h"
#include <gtk/gtk.h>
#include <gio/gdesktopappinfo.h>
#include <glib-unix.h>
#include <math.h>
#include <signal.h>

struct ALHost {
    GtkWidget *window, *root, *wallpaper, *stage, *notice, *launcher, *launcher_entry, *launcher_list, *dialog;
    GMainLoop *loop;
    ALActionCallback callback;
    void *context;
    GHashTable *roles;
    int wallpaper_kind, launcher_visible;
    guint timer, sigterm, sigint;
};

struct ALFilesView {
    ALHost *host;
    char *identifier;
    GtkWidget *frame, *title, *path, *search, *back, *forward, *hidden, *sort, *view, *info;
    GtkWidget *favorites, *scroll, *list, *status;
    GHashTable *roles, *entries;
    int grid, silent;
    double x, y, width, height, drag_x, drag_y, drag_width, drag_height;
};

typedef struct {
    ALHost *host;
    ALFilesView *view;
    int action;
    char *value;
} Binding;

static void emit(ALHost *host, int action, ALFilesView *view, const char *value, double a, double b) {
    if (view && view->silent) return;
    host->callback(host->context, action, view ? view->identifier : "", value ? value : "", a, b);
}

static Binding *binding(ALHost *host, ALFilesView *view, int action, const char *value) {
    Binding *b = g_new0(Binding, 1);
    b->host = host; b->view = view; b->action = action; b->value = g_strdup(value ? value : "");
    return b;
}

static void binding_free(gpointer data, GClosure *closure) {
    (void)closure;
    Binding *b = data;
    g_free(b->value); g_free(b);
}

static void clicked(GtkButton *button, gpointer data) {
    (void)button;
    Binding *b = data;
    emit(b->host, b->action, b->view, b->value, 0, 0);
}

static GtkWidget *label(const char *text, float alignment) {
    GtkWidget *w = gtk_label_new(text);
    gtk_label_set_xalign(GTK_LABEL(w), alignment);
    gtk_label_set_ellipsize(GTK_LABEL(w), PANGO_ELLIPSIZE_END);
    return w;
}

static GtkWidget *button(ALHost *host, ALFilesView *view, const char *text, const char *icon,
                         int action, const char *value, const char *role) {
    GtkWidget *w = icon ? gtk_button_new_from_icon_name(icon) : gtk_button_new_with_label(text);
    gtk_widget_set_tooltip_text(w, text);
    g_signal_connect_data(w, "clicked", G_CALLBACK(clicked), binding(host, view, action, value), binding_free, 0);
    if (role) g_hash_table_insert(view ? view->roles : host->roles, g_strdup(role), w);
    return w;
}

static void changed(GtkEditable *editable, gpointer data) {
    Binding *b = data;
    emit(b->host, b->action, b->view, gtk_editable_get_text(editable), 0, 0);
}

static void path_activated(GtkEntry *entry, gpointer data) {
    ALFilesView *view = data;
    emit(view->host, AL_NAVIGATE, view, gtk_editable_get_text(GTK_EDITABLE(entry)), 0, 0);
}

static void hidden_changed(GtkCheckButton *check, gpointer data) {
    ALFilesView *view = data;
    emit(view->host, AL_HIDDEN, view, "", gtk_check_button_get_active(check), 0);
}

static void sort_changed(GObject *object, GParamSpec *spec, gpointer data) {
    (void)spec;
    ALFilesView *view = data;
    emit(view->host, AL_SORT, view, "", gtk_drop_down_get_selected(GTK_DROP_DOWN(object)), 0);
}

static void wallpaper_draw(GtkDrawingArea *area, cairo_t *cr, int width, int height, gpointer data) {
    (void)area;
    ALHost *host = data;
    double colors[][6] = {
        {0.08, 0.32, 0.52, 0.01, 0.07, 0.20},
        {0.72, 0.35, 0.44, 0.10, 0.06, 0.25},
        {0.18, 0.42, 0.34, 0.02, 0.11, 0.14}
    };
    double *c = colors[host->wallpaper_kind];
    cairo_pattern_t *gradient = cairo_pattern_create_linear(width, 0, 0, height);
    cairo_pattern_add_color_stop_rgb(gradient, 0, c[0], c[1], c[2]);
    cairo_pattern_add_color_stop_rgb(gradient, 1, c[3], c[4], c[5]);
    cairo_set_source(cr, gradient); cairo_paint(cr); cairo_pattern_destroy(gradient);
    for (int i = 0; i < 4; i++) {
        double y = height * (0.38 + i * 0.11);
        cairo_move_to(cr, 0, y);
        cairo_curve_to(cr, width * 0.28, y + height * 0.48,
                       width * 0.54, y - height * 0.13, width, y + height * 0.39);
        cairo_line_to(cr, width, height); cairo_line_to(cr, 0, height); cairo_close_path(cr);
        cairo_set_source_rgba(cr, c[3] * 0.7, c[4] * 0.7, c[5] * 0.7, 0.18 + i * 0.04);
        cairo_fill(cr);
    }
}

static gboolean tick(gpointer data) {
    emit(data, AL_TICK, NULL, "", 0, 0);
    return G_SOURCE_CONTINUE;
}

static gboolean quit_signal(gpointer data) {
    al_host_quit(data);
    return G_SOURCE_CONTINUE;
}

static gboolean close_requested(GtkWindow *window, gpointer data) {
    (void)window;
    al_host_quit(data);
    return TRUE;
}

static gboolean key_pressed(GtkEventControllerKey *controller, guint key, guint code,
                            GdkModifierType modifiers, gpointer data) {
    (void)controller; (void)code;
    ALHost *host = data;
    if (key == GDK_KEY_Escape && (host->launcher_visible || host->dialog)) {
        emit(host, AL_DISMISS, NULL, "", 0, 0); return TRUE;
    }
    if (host->dialog) return FALSE;
    gboolean command = (modifiers & (GDK_CONTROL_MASK | GDK_SUPER_MASK)) != 0;
    if (command) {
        switch (gdk_keyval_to_lower(key)) {
        case GDK_KEY_k: emit(host, AL_LAUNCHER, NULL, "", 0, 0); return TRUE;
        case GDK_KEY_n: emit(host, AL_NEW_FILES, NULL, "", 0, 0); return TRUE;
        case GDK_KEY_i: emit(host, AL_INFO, NULL, "", 0, 0); return TRUE;
        case GDK_KEY_q: emit(host, AL_QUIT, NULL, "", 0, 0); return TRUE;
        case GDK_KEY_bracketleft: emit(host, AL_BACK, NULL, "", 0, 0); return TRUE;
        case GDK_KEY_bracketright: emit(host, AL_FORWARD, NULL, "", 0, 0); return TRUE;
        case GDK_KEY_Up: emit(host, AL_UP, NULL, "", 0, 0); return TRUE;
        case GDK_KEY_greater:
        case GDK_KEY_period:
            if (modifiers & GDK_SHIFT_MASK) { emit(host, AL_HIDDEN, NULL, "", -1, 0); return TRUE; }
            break;
        case GDK_KEY_d:
            if (modifiers & GDK_SHIFT_MASK) { emit(host, AL_SHOW_DESKTOP, NULL, "", 0, 0); return TRUE; }
            break;
        default: break;
        }
    }
    if (host->launcher_visible) {
        if (key == GDK_KEY_Down || key == GDK_KEY_Up) {
            GtkWidget *focus = gtk_root_get_focus(GTK_ROOT(host->window));
            if (focus && gtk_widget_is_ancestor(focus, host->launcher_list)) return FALSE;
            emit(host, AL_LAUNCHER_MOVE, NULL, "", key == GDK_KEY_Down ? 1 : -1, 0); return TRUE;
        }
        if (key == GDK_KEY_Return) { emit(host, AL_LAUNCHER_ACCEPT, NULL, "", 0, 0); return TRUE; }
    }
    GtkWidget *focus = gtk_root_get_focus(GTK_ROOT(host->window));
    if (key == GDK_KEY_space && (!focus || !GTK_IS_EDITABLE(focus))) {
        emit(host, AL_PREVIEW, NULL, "", 0, 0); return TRUE;
    }
    return FALSE;
}

ALHost *al_host_new(ALActionCallback callback, void *context) {
    gtk_init();
    ALHost *host = g_new0(ALHost, 1);
    host->callback = callback; host->context = context;
    host->roles = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
    host->loop = g_main_loop_new(NULL, FALSE);
    g_object_set(gtk_settings_get_default(), "gtk-application-prefer-dark-theme", TRUE, NULL);
    GtkCssProvider *css = gtk_css_provider_new();
    gtk_css_provider_load_from_string(css,
        "window { font-family: 'DejaVu Sans'; font-size: 13px; color: #ededf1; }"
        "button { border-radius: 7px; }"
        ".menubar { background: rgba(25,29,43,0.78); padding: 3px 16px; }"
        ".menubar button { background: transparent; border: none; box-shadow: none; padding: 3px 8px; }"
        ".desktop-window { background: #24272e; border: 1px solid #626673; border-radius: 13px; box-shadow: 0 12px 28px rgba(0,0,0,0.36); }"
        ".titlebar { background: #292c34; border-radius: 12px 12px 0 0; padding: 8px 13px; }"
        ".titlebar label { font-weight: bold; }"
        ".traffic { min-height: 16px; min-width: 16px; padding: 0; border-radius: 50%; border: none; color: rgba(0,0,0,0.65); font-size: 10px; box-shadow: none; }"
        ".red { background: #ff5f57; } .yellow { background: #febc2e; } .green { background: #28c840; }"
        ".toolbar { padding: 7px 12px; background: #24272e; }"
        ".toolbar button { padding: 4px 7px; }"
        ".favorites { background: #292c34; padding: 14px 8px; }"
        ".favorites button { background: transparent; box-shadow: none; border: none; padding: 8px; }"
        ".favorites label.heading { font-size: 11px; color: #969aa7; margin: 0 8px 5px; }"
        ".folder-icon { color: #35c8f5; }"
        ".file-list { background: #202329; padding: 12px; }"
        ".file-tile { padding: 11px 6px; border-radius: 8px; }"
        ".file-row { padding: 7px 9px; border-radius: 6px; }"
        ".file-selected { background: #255484; }"
        ".muted { color: #a5a9b5; }"
        ".status { color: #a5a9b5; font-size: 11px; padding: 7px 15px; }"
        ".dock { background: rgba(27,30,39,0.94); border: 1px solid #747985; border-radius: 20px; padding: 10px 13px; }"
        ".dock button { min-width: 49px; min-height: 49px; border-radius: 13px; padding: 5px; margin: 0 4px; }"
        ".dock-files { background: #24a9e4; } .dock-search { background: #a154ee; }"
        ".dock-terminal { background: #33363e; } .dock-home { background: #3d8dbb; } .dock-appearance { background: #535a69; }"
        ".modal-sheet { background: #2c3039; border: 1px solid #747b8b; border-radius: 15px; padding: 25px; box-shadow: 0 15px 35px rgba(0,0,0,0.50); }"
        ".launcher-row { padding: 9px 12px; border-radius: 8px; }"
        ".launcher-selected { background: #245d93; }"
        ".notice { color: #ffbf79; font-size: 11px; }");
    gtk_style_context_add_provider_for_display(gdk_display_get_default(), GTK_STYLE_PROVIDER(css),
                                               GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(css);
    host->window = gtk_window_new(); g_object_ref_sink(host->window);
    gtk_window_set_title(GTK_WINDOW(host->window), "Absolute Linux Desktop");
    gtk_window_set_default_size(GTK_WINDOW(host->window), 1440, 900);
    gtk_window_set_decorated(GTK_WINDOW(host->window), FALSE);
    g_signal_connect(host->window, "close-request", G_CALLBACK(close_requested), host);
    host->root = gtk_overlay_new(); gtk_window_set_child(GTK_WINDOW(host->window), host->root);
    host->wallpaper = gtk_drawing_area_new();
    gtk_widget_set_hexpand(host->wallpaper, TRUE); gtk_widget_set_vexpand(host->wallpaper, TRUE);
    gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(host->wallpaper), wallpaper_draw, host, NULL);
    gtk_overlay_set_child(GTK_OVERLAY(host->root), host->wallpaper);
    host->stage = gtk_fixed_new();
    gtk_widget_set_hexpand(host->stage, TRUE); gtk_widget_set_vexpand(host->stage, TRUE);
    gtk_overlay_add_overlay(GTK_OVERLAY(host->root), host->stage);
    GtkWidget *menu = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
    gtk_widget_add_css_class(menu, "menubar"); gtk_widget_set_valign(menu, GTK_ALIGN_START);
    gtk_box_append(GTK_BOX(menu), label("Absolute", 0));
    gtk_box_append(GTK_BOX(menu), button(host, NULL, "New Files", NULL, AL_NEW_FILES, "", "new-files"));
    gtk_box_append(GTK_BOX(menu), button(host, NULL, "Show Desktop", NULL, AL_SHOW_DESKTOP, "", "show-desktop"));
    gtk_box_append(GTK_BOX(menu), button(host, NULL, "Search Apps", NULL, AL_LAUNCHER, "", "search-apps"));
    host->notice = label("", 0); gtk_widget_add_css_class(host->notice, "notice");
    gtk_widget_set_hexpand(host->notice, TRUE); gtk_box_append(GTK_BOX(menu), host->notice);
    GtkWidget *edition = label("Absolute · Linux Preview", 1); gtk_widget_add_css_class(edition, "muted");
    gtk_box_append(GTK_BOX(menu), edition);
    gtk_overlay_add_overlay(GTK_OVERLAY(host->root), menu);
    GtkWidget *dock = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 3);
    gtk_widget_add_css_class(dock, "dock"); gtk_widget_set_halign(dock, GTK_ALIGN_CENTER);
    gtk_widget_set_valign(dock, GTK_ALIGN_END); gtk_widget_set_margin_bottom(dock, 18);
    const char *dock_names[] = {"Files", "Search Applications", "Terminal", "Home", "Change Wallpaper"};
    const char *dock_icons[] = {"folder-symbolic", "system-search-symbolic", "utilities-terminal-symbolic", "user-home-symbolic", "preferences-desktop-display-symbolic"};
    const char *dock_classes[] = {"dock-files", "dock-search", "dock-terminal", "dock-home", "dock-appearance"};
    const char *dock_roles[] = {"dock-files", "dock-search", "dock-terminal", "dock-home", "dock-wallpaper"};
    int dock_actions[] = {AL_SHOW_FILES, AL_LAUNCHER, AL_TERMINAL, AL_NAVIGATE, AL_WALLPAPER};
    for (int i = 0; i < 5; i++) {
        GtkWidget *w = button(host, NULL, dock_names[i], dock_icons[i], dock_actions[i], i == 3 ? g_get_home_dir() : "", dock_roles[i]);
        gtk_widget_add_css_class(w, dock_classes[i]);
        gtk_image_set_pixel_size(GTK_IMAGE(gtk_button_get_child(GTK_BUTTON(w))), 34);
        gtk_box_append(GTK_BOX(dock), w);
    }
    gtk_overlay_add_overlay(GTK_OVERLAY(host->root), dock);
    GtkEventController *keys = gtk_event_controller_key_new();
    gtk_event_controller_set_propagation_phase(keys, GTK_PHASE_CAPTURE);
    g_signal_connect(keys, "key-pressed", G_CALLBACK(key_pressed), host);
    gtk_widget_add_controller(host->window, keys);
    host->timer = g_timeout_add(100, tick, host);
    host->sigterm = g_unix_signal_add(SIGTERM, quit_signal, host);
    host->sigint = g_unix_signal_add(SIGINT, quit_signal, host);
    return host;
}

void al_host_run(ALHost *host) { gtk_window_present(GTK_WINDOW(host->window)); g_main_loop_run(host->loop); }
void al_host_quit(ALHost *host) { g_main_loop_quit(host->loop); }
void al_host_free(ALHost *host) {
    g_source_remove(host->timer); g_source_remove(host->sigterm); g_source_remove(host->sigint);
    gtk_window_destroy(GTK_WINDOW(host->window)); g_object_unref(host->window);
    g_main_loop_unref(host->loop); g_hash_table_destroy(host->roles); g_free(host);
}
void al_host_set_wallpaper(ALHost *host, const char *wallpaper) {
    host->wallpaper_kind = g_strcmp0(wallpaper, "dusk") == 0 ? 1 : g_strcmp0(wallpaper, "forest") == 0 ? 2 : 0;
    gtk_widget_queue_draw(host->wallpaper);
}
void al_host_set_notice(ALHost *host, const char *message) { gtk_label_set_text(GTK_LABEL(host->notice), message); }

static ALRect rect(ALHost *host, GtkWidget *widget) {
    ALRect result = {0};
    graphene_rect_t bounds;
    if (widget && gtk_widget_get_mapped(widget) && gtk_widget_compute_bounds(widget, host->root, &bounds)) {
        result = (ALRect){bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height, 1};
    }
    return result;
}
ALRect al_host_rect(ALHost *host, const char *role) {
    if (g_strcmp0(role, "desktop") == 0) return rect(host, host->root);
    return rect(host, g_hash_table_lookup(host->roles, role));
}
ALRect al_files_rect(ALFilesView *view, const char *role) {
    return rect(view->host, g_hash_table_lookup(view->roles, role));
}

static void drag_begin(GtkGestureDrag *gesture, double x, double y, gpointer data) {
    (void)gesture; (void)x; (void)y;
    ALFilesView *view = data; view->drag_x = view->x; view->drag_y = view->y;
    emit(view->host, AL_FOCUS, view, "", 0, 0);
}
static void drag_update(GtkGestureDrag *gesture, double x, double y, gpointer data) {
    (void)gesture;
    ALFilesView *view = data;
    double max_x = MAX(16, gtk_widget_get_width(view->host->stage) - view->width - 16);
    double max_y = MAX(45, gtk_widget_get_height(view->host->stage) - view->height - 105);
    view->x = CLAMP(view->drag_x + x, 16, max_x); view->y = CLAMP(view->drag_y + y, 45, max_y);
    gtk_fixed_move(GTK_FIXED(view->host->stage), view->frame, view->x, view->y);
}
static void drag_end(GtkGestureDrag *gesture, double x, double y, gpointer data) {
    drag_update(gesture, x, y, data);
    ALFilesView *view = data;
    emit(view->host, AL_MOVE, view, "", view->x, view->y);
}
static void resize_begin(GtkGestureDrag *gesture, double x, double y, gpointer data) {
    (void)gesture; (void)x; (void)y;
    ALFilesView *view = data; view->drag_width = view->width; view->drag_height = view->height;
    emit(view->host, AL_FOCUS, view, "", 0, 0);
}
static void resize_update(GtkGestureDrag *gesture, double x, double y, gpointer data) {
    (void)gesture;
    ALFilesView *view = data;
    view->width = CLAMP(view->drag_width + x, 620, MAX(620, gtk_widget_get_width(view->host->stage) - view->x - 16));
    view->height = CLAMP(view->drag_height + y, 360, MAX(360, gtk_widget_get_height(view->host->stage) - view->y - 105));
    gtk_widget_set_size_request(view->frame, view->width, view->height);
}
static void resize_end(GtkGestureDrag *gesture, double x, double y, gpointer data) {
    resize_update(gesture, x, y, data);
    ALFilesView *view = data;
    emit(view->host, AL_RESIZE, view, "", view->width, view->height);
}

ALFilesView *al_files_new(ALHost *host, const char *identifier) {
    ALFilesView *view = g_new0(ALFilesView, 1);
    view->host = host; view->identifier = g_strdup(identifier);
    view->roles = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
    view->entries = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
    view->grid = 1;
    view->frame = gtk_overlay_new(); gtk_widget_add_css_class(view->frame, "desktop-window");
    g_hash_table_insert(view->roles, g_strdup("window"), view->frame);
    GtkWidget *vertical = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_overlay_set_child(GTK_OVERLAY(view->frame), vertical);
    GtkWidget *titlebar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_widget_add_css_class(titlebar, "titlebar"); gtk_widget_set_size_request(titlebar, -1, 26);
    g_hash_table_insert(view->roles, g_strdup("titlebar"), titlebar);
    const char *traffic[] = {"×", "−", "+"}, *colors[] = {"red", "yellow", "green"}, *roles[] = {"close", "minimize", "maximize"};
    int actions[] = {AL_CLOSE, AL_MINIMIZE, AL_MAXIMIZE};
    for (int i = 0; i < 3; i++) {
        GtkWidget *w = button(host, view, traffic[i], NULL, actions[i], "", roles[i]);
        gtk_widget_add_css_class(w, "traffic"); gtk_widget_add_css_class(w, colors[i]);
        gtk_widget_set_valign(w, GTK_ALIGN_CENTER); gtk_widget_set_size_request(w, 16, 16);
        gtk_box_append(GTK_BOX(titlebar), w);
    }
    view->title = label("Files", 0.5); gtk_widget_set_hexpand(view->title, TRUE);
    gtk_box_append(GTK_BOX(titlebar), view->title);
    GtkWidget *spacer = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0); gtk_widget_set_size_request(spacer, 64, -1);
    gtk_box_append(GTK_BOX(titlebar), spacer);
    GtkGesture *drag = gtk_gesture_drag_new();
    g_signal_connect(drag, "drag-begin", G_CALLBACK(drag_begin), view);
    g_signal_connect(drag, "drag-update", G_CALLBACK(drag_update), view);
    g_signal_connect(drag, "drag-end", G_CALLBACK(drag_end), view);
    gtk_widget_add_controller(titlebar, GTK_EVENT_CONTROLLER(drag));
    gtk_box_append(GTK_BOX(vertical), titlebar);
    GtkWidget *toolbar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    gtk_widget_add_css_class(toolbar, "toolbar");
    view->back = button(host, view, "Back", "go-previous-symbolic", AL_BACK, "", "back");
    view->forward = button(host, view, "Forward", "go-next-symbolic", AL_FORWARD, "", "forward");
    gtk_box_append(GTK_BOX(toolbar), view->back); gtk_box_append(GTK_BOX(toolbar), view->forward);
    gtk_box_append(GTK_BOX(toolbar), button(host, view, "Enclosing Folder", "go-up-symbolic", AL_UP, "", "up"));
    view->path = gtk_entry_new(); gtk_widget_set_hexpand(view->path, TRUE);
    gtk_editable_set_width_chars(GTK_EDITABLE(view->path), 18);
    gtk_editable_set_max_width_chars(GTK_EDITABLE(view->path), 38);
    gtk_widget_set_tooltip_text(view->path, "Folder path — press Enter to navigate");
    g_signal_connect(view->path, "activate", G_CALLBACK(path_activated), view);
    g_hash_table_insert(view->roles, g_strdup("path"), view->path);
    gtk_box_append(GTK_BOX(toolbar), view->path);
    view->search = gtk_search_entry_new();
    gtk_widget_set_size_request(view->search, 165, -1);
    gtk_editable_set_width_chars(GTK_EDITABLE(view->search), 14);
    gtk_editable_set_max_width_chars(GTK_EDITABLE(view->search), 18);
    g_signal_connect_data(view->search, "search-changed", G_CALLBACK(changed),
                          binding(host, view, AL_FILTER, ""), binding_free, 0);
    g_hash_table_insert(view->roles, g_strdup("search"), view->search);
    gtk_box_append(GTK_BOX(toolbar), view->search);
    view->hidden = gtk_check_button_new_with_label("Hidden");
    g_signal_connect(view->hidden, "toggled", G_CALLBACK(hidden_changed), view);
    g_hash_table_insert(view->roles, g_strdup("hidden"), view->hidden);
    gtk_box_append(GTK_BOX(toolbar), view->hidden);
    const char *sorts[] = {"Name", "Modified", "Size", NULL};
    view->sort = gtk_drop_down_new_from_strings(sorts);
    g_signal_connect(view->sort, "notify::selected", G_CALLBACK(sort_changed), view);
    g_hash_table_insert(view->roles, g_strdup("sort"), view->sort);
    gtk_box_append(GTK_BOX(toolbar), view->sort);
    view->view = button(host, view, "Toggle List / Grid", "view-list-symbolic", AL_VIEW, "", "view");
    gtk_box_append(GTK_BOX(toolbar), view->view);
    view->info = button(host, view, "Get Info (Ctrl+I)", "dialog-information-symbolic", AL_INFO, "", "info");
    gtk_widget_set_sensitive(view->info, FALSE); gtk_box_append(GTK_BOX(toolbar), view->info);
    gtk_box_append(GTK_BOX(vertical), toolbar);
    GtkWidget *body = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0); gtk_widget_set_vexpand(body, TRUE);
    view->favorites = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    gtk_widget_set_size_request(view->favorites, 174, -1); gtk_widget_add_css_class(view->favorites, "favorites");
    GtkWidget *heading = label("FAVORITES", 0); gtk_widget_add_css_class(heading, "heading");
    gtk_box_append(GTK_BOX(view->favorites), heading);
    gtk_box_append(GTK_BOX(body), view->favorites);
    view->scroll = gtk_scrolled_window_new();
    g_hash_table_insert(view->roles, g_strdup("contents"), view->scroll);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(view->scroll), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
    gtk_widget_set_hexpand(view->scroll, TRUE); gtk_widget_set_vexpand(view->scroll, TRUE);
    gtk_box_append(GTK_BOX(body), view->scroll);
    gtk_box_append(GTK_BOX(vertical), body);
    view->status = label("", 0); gtk_widget_add_css_class(view->status, "status");
    gtk_box_append(GTK_BOX(vertical), view->status);
    GtkWidget *resize = label("◢", 0.5);
    gtk_widget_set_size_request(resize, 22, 22); gtk_widget_set_halign(resize, GTK_ALIGN_END);
    gtk_widget_set_valign(resize, GTK_ALIGN_END); gtk_widget_set_cursor_from_name(resize, "se-resize");
    g_hash_table_insert(view->roles, g_strdup("resize"), resize);
    GtkGesture *resizer = gtk_gesture_drag_new();
    g_signal_connect(resizer, "drag-begin", G_CALLBACK(resize_begin), view);
    g_signal_connect(resizer, "drag-update", G_CALLBACK(resize_update), view);
    g_signal_connect(resizer, "drag-end", G_CALLBACK(resize_end), view);
    gtk_widget_add_controller(resize, GTK_EVENT_CONTROLLER(resizer));
    gtk_overlay_add_overlay(GTK_OVERLAY(view->frame), resize);
    gtk_fixed_put(GTK_FIXED(host->stage), view->frame, 100, 80);
    return view;
}

void al_files_destroy(ALFilesView *view) {
    gtk_fixed_remove(GTK_FIXED(view->host->stage), view->frame);
    g_hash_table_destroy(view->roles); g_hash_table_destroy(view->entries);
    g_free(view->identifier); g_free(view);
}
void al_files_frame(ALFilesView *view, double x, double y, double width, double height, int visible) {
    view->x = x; view->y = y; view->width = width; view->height = height;
    gtk_widget_set_size_request(view->frame, width, height);
    gtk_fixed_move(GTK_FIXED(view->host->stage), view->frame, x, y);
    gtk_widget_set_visible(view->frame, visible);
}
void al_files_raise(ALFilesView *view) {
    GtkWidget *last = gtk_widget_get_last_child(view->host->stage);
    if (last != view->frame) gtk_widget_insert_after(view->frame, view->host->stage, last);
}
void al_files_location(ALFilesView *view, const char *title, const char *path, const char *filter,
                       int back, int forward, int hidden, int sort, int grid) {
    view->silent = 1;
    gtk_label_set_text(GTK_LABEL(view->title), title);
    if (g_strcmp0(gtk_editable_get_text(GTK_EDITABLE(view->path)), path))
        gtk_editable_set_text(GTK_EDITABLE(view->path), path);
    if (g_strcmp0(gtk_editable_get_text(GTK_EDITABLE(view->search)), filter))
        gtk_editable_set_text(GTK_EDITABLE(view->search), filter);
    gtk_widget_set_sensitive(view->back, back); gtk_widget_set_sensitive(view->forward, forward);
    gtk_check_button_set_active(GTK_CHECK_BUTTON(view->hidden), hidden);
    gtk_drop_down_set_selected(GTK_DROP_DOWN(view->sort), sort);
    view->grid = grid; view->silent = 0;
}
void al_files_favorite(ALFilesView *view, const char *text, const char *path, const char *icon) {
    GtkWidget *w = button(view->host, view, text, NULL, AL_NAVIGATE, path, NULL);
    GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
    GtkWidget *image = gtk_image_new_from_icon_name(icon);
    gtk_widget_add_css_class(image, "folder-icon"); gtk_image_set_pixel_size(GTK_IMAGE(image), 19);
    gtk_box_append(GTK_BOX(row), image); gtk_box_append(GTK_BOX(row), label(text, 0));
    gtk_button_set_child(GTK_BUTTON(w), row);
    gtk_box_append(GTK_BOX(view->favorites), w);
    g_hash_table_insert(view->roles, g_strdup_printf("favorite:%s", text), w);
}
void al_files_clear(ALFilesView *view) {
    GHashTableIter iterator; gpointer key, value;
    g_hash_table_iter_init(&iterator, view->entries);
    while (g_hash_table_iter_next(&iterator, &key, &value)) {
        char *role = g_strdup_printf("entry:%s", (char *)key);
        g_hash_table_remove(view->roles, role); g_free(role);
    }
    g_hash_table_remove_all(view->entries);
    if (view->grid) {
        view->list = gtk_flow_box_new();
        gtk_flow_box_set_selection_mode(GTK_FLOW_BOX(view->list), GTK_SELECTION_NONE);
        gtk_flow_box_set_min_children_per_line(GTK_FLOW_BOX(view->list), 1);
        gtk_flow_box_set_max_children_per_line(GTK_FLOW_BOX(view->list), 6);
        gtk_flow_box_set_column_spacing(GTK_FLOW_BOX(view->list), 10);
        gtk_flow_box_set_row_spacing(GTK_FLOW_BOX(view->list), 8);
        gtk_widget_set_valign(view->list, GTK_ALIGN_START);
    } else view->list = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    gtk_widget_add_css_class(view->list, "file-list");
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(view->scroll), view->list);
}
static void entry_pressed(GtkGestureClick *gesture, int presses, double x, double y, gpointer data) {
    (void)gesture; (void)x; (void)y;
    Binding *b = data;
    ALHost *host = b->host; ALFilesView *view = b->view; char *path = g_strdup(b->value);
    gtk_widget_grab_focus(gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(gesture)));
    emit(host, presses == 2 ? AL_OPEN : AL_SELECT, view, path, 0, 0);
    g_free(path);
}
void al_files_entry(ALFilesView *view, const char *path, const char *name, const char *kind,
                    const char *modified, const char *size, int folder) {
    GtkWidget *item = gtk_box_new(view->grid ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL, view->grid ? 7 : 12);
    gtk_widget_set_focusable(item, TRUE);
    gtk_widget_add_css_class(item, view->grid ? "file-tile" : "file-row");
    GtkWidget *image = gtk_image_new_from_icon_name(folder ? "folder-symbolic" : "text-x-generic-symbolic");
    gtk_image_set_pixel_size(GTK_IMAGE(image), view->grid ? 48 : 21);
    if (folder) gtk_widget_add_css_class(image, "folder-icon");
    gtk_box_append(GTK_BOX(item), image);
    GtkWidget *title = label(name, view->grid ? 0.5 : 0);
    gtk_label_set_max_width_chars(GTK_LABEL(title), view->grid ? 17 : 30);
    if (view->grid) {
        gtk_widget_set_size_request(item, 105, 96);
        gtk_label_set_wrap(GTK_LABEL(title), TRUE); gtk_label_set_lines(GTK_LABEL(title), 2);
        gtk_label_set_justify(GTK_LABEL(title), GTK_JUSTIFY_CENTER);
    } else { gtk_widget_set_hexpand(title, TRUE); gtk_widget_set_size_request(title, 125, -1); }
    gtk_box_append(GTK_BOX(item), title);
    if (!view->grid) {
        const char *texts[] = {kind, modified, size}; int widths[] = {85, 100, 75};
        for (int i = 0; i < 3; i++) {
            GtkWidget *detail = label(texts[i], i == 2 ? 1 : 0);
            gtk_widget_add_css_class(detail, "muted"); gtk_widget_set_size_request(detail, widths[i], -1);
            gtk_label_set_max_width_chars(GTK_LABEL(detail), 14); gtk_box_append(GTK_BOX(item), detail);
        }
    }
    gtk_widget_set_tooltip_text(item, path);
    GtkGesture *click = gtk_gesture_click_new();
    g_signal_connect_data(click, "pressed", G_CALLBACK(entry_pressed),
                          binding(view->host, view, AL_SELECT, path), binding_free, 0);
    gtk_widget_add_controller(item, GTK_EVENT_CONTROLLER(click));
    if (view->grid) gtk_flow_box_append(GTK_FLOW_BOX(view->list), item);
    else gtk_box_append(GTK_BOX(view->list), item);
    g_hash_table_insert(view->entries, g_strdup(path), item);
    g_hash_table_insert(view->roles, g_strdup_printf("entry:%s", path), item);
}
void al_files_selected(ALFilesView *view, const char *path) {
    GHashTableIter iterator; gpointer key, value;
    g_hash_table_iter_init(&iterator, view->entries);
    while (g_hash_table_iter_next(&iterator, &key, &value)) {
        if (g_strcmp0(key, path) == 0) gtk_widget_add_css_class(value, "file-selected");
        else gtk_widget_remove_css_class(value, "file-selected");
    }
    gtk_widget_set_sensitive(view->info, path && *path);
}
void al_files_status(ALFilesView *view, const char *message) { gtk_label_set_text(GTK_LABEL(view->status), message); }

void al_host_dismiss(ALHost *host) {
    if (host->dialog) {
        g_hash_table_remove(host->roles, "dialog"); g_hash_table_remove(host->roles, "dialog-close");
        g_hash_table_remove(host->roles, "dialog-reveal");
        gtk_overlay_remove_overlay(GTK_OVERLAY(host->root), host->dialog); host->dialog = NULL;
    }
    if (host->launcher) gtk_widget_set_visible(host->launcher, FALSE);
    host->launcher_visible = 0; gtk_widget_set_sensitive(host->stage, TRUE);
}
void al_host_dialog(ALHost *host, const char *title, const char *text, int can_reveal) {
    al_host_dismiss(host);
    host->dialog = gtk_box_new(GTK_ORIENTATION_VERTICAL, 18);
    gtk_widget_add_css_class(host->dialog, "modal-sheet");
    gtk_widget_set_size_request(host->dialog, 490, 350);
    gtk_widget_set_halign(host->dialog, GTK_ALIGN_CENTER); gtk_widget_set_valign(host->dialog, GTK_ALIGN_CENTER);
    GtkWidget *heading = label(title, 0); gtk_widget_add_css_class(heading, "title-2");
    gtk_box_append(GTK_BOX(host->dialog), heading);
    GtkWidget *scroll = gtk_scrolled_window_new(); gtk_widget_set_vexpand(scroll, TRUE);
    gtk_widget_set_size_request(scroll, 450, 235);
    GtkWidget *body = gtk_label_new(text); gtk_label_set_xalign(GTK_LABEL(body), 0); gtk_label_set_yalign(GTK_LABEL(body), 0);
    gtk_label_set_wrap(GTK_LABEL(body), TRUE); gtk_label_set_selectable(GTK_LABEL(body), TRUE);
    gtk_label_set_max_width_chars(GTK_LABEL(body), 62);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), body);
    gtk_box_append(GTK_BOX(host->dialog), scroll);
    GtkWidget *actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
    if (can_reveal) gtk_box_append(GTK_BOX(actions), button(host, NULL, "Show Containing Folder", NULL, AL_REVEAL, "", "dialog-reveal"));
    GtkWidget *spacer = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0); gtk_widget_set_hexpand(spacer, TRUE);
    gtk_box_append(GTK_BOX(actions), spacer);
    gtk_box_append(GTK_BOX(actions), button(host, NULL, "Done", NULL, AL_DISMISS, "", "dialog-close"));
    gtk_box_append(GTK_BOX(host->dialog), actions);
    gtk_widget_set_sensitive(host->stage, FALSE);
    gtk_overlay_add_overlay(GTK_OVERLAY(host->root), host->dialog);
    g_hash_table_insert(host->roles, g_strdup("dialog"), host->dialog);
}

static void launcher_activate(GtkListBox *list, GtkListBoxRow *row, gpointer data) {
    (void)list;
    ALHost *host = data;
    emit(host, AL_LAUNCHER_ACCEPT, NULL, g_object_get_data(G_OBJECT(row), "application-path"), 0, 0);
}
static void launcher_selected(GtkListBox *list, GtkListBoxRow *row, gpointer data) {
    (void)list;
    if (row) emit(data, AL_LAUNCHER_SELECT, NULL, "", gtk_list_box_row_get_index(row), 0);
}
void al_launcher_show(ALHost *host) {
    al_host_dismiss(host);
    if (!host->launcher) {
        host->launcher = gtk_box_new(GTK_ORIENTATION_VERTICAL, 16);
        gtk_widget_add_css_class(host->launcher, "modal-sheet");
        gtk_widget_set_size_request(host->launcher, 610, 435);
        gtk_widget_set_halign(host->launcher, GTK_ALIGN_CENTER); gtk_widget_set_valign(host->launcher, GTK_ALIGN_CENTER);
        gtk_box_append(GTK_BOX(host->launcher), label("Search Applications", 0));
        host->launcher_entry = gtk_search_entry_new();
        g_signal_connect_data(host->launcher_entry, "search-changed", G_CALLBACK(changed),
                              binding(host, NULL, AL_LAUNCHER_FILTER, ""), binding_free, 0);
        gtk_box_append(GTK_BOX(host->launcher), host->launcher_entry);
        host->launcher_list = gtk_list_box_new();
        gtk_list_box_set_selection_mode(GTK_LIST_BOX(host->launcher_list), GTK_SELECTION_SINGLE);
        gtk_list_box_set_activate_on_single_click(GTK_LIST_BOX(host->launcher_list), FALSE);
        g_signal_connect(host->launcher_list, "row-activated", G_CALLBACK(launcher_activate), host);
        g_signal_connect(host->launcher_list, "row-selected", G_CALLBACK(launcher_selected), host);
        GtkWidget *scroll = gtk_scrolled_window_new(); gtk_widget_set_vexpand(scroll, TRUE);
        gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), host->launcher_list);
        gtk_box_append(GTK_BOX(host->launcher), scroll);
        gtk_box_append(GTK_BOX(host->launcher), label("↑ ↓ to choose · Enter to launch · Esc to close", 0));
        gtk_overlay_add_overlay(GTK_OVERLAY(host->root), host->launcher);
        g_hash_table_insert(host->roles, g_strdup("launcher"), host->launcher);
        g_hash_table_insert(host->roles, g_strdup("launcher-search"), host->launcher_entry);
    }
    host->launcher_visible = 1; gtk_widget_set_visible(host->launcher, TRUE);
    gtk_widget_set_sensitive(host->stage, FALSE);
    gtk_editable_set_text(GTK_EDITABLE(host->launcher_entry), "");
    gtk_widget_grab_focus(host->launcher_entry);
}
void al_launcher_clear(ALHost *host) {
    if (!host->launcher_list) return;
    GtkWidget *child;
    while ((child = gtk_widget_get_first_child(host->launcher_list))) {
        const char *path = g_object_get_data(G_OBJECT(child), "application-path");
        if (path) {
            char *role = g_strdup_printf("launcher-entry:%s", path);
            g_hash_table_remove(host->roles, role); g_free(role);
        }
        gtk_list_box_remove(GTK_LIST_BOX(host->launcher_list), child);
    }
}
void al_launcher_entry(ALHost *host, const char *name, const char *path) {
    GtkWidget *row = gtk_list_box_row_new();
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 13); gtk_widget_add_css_class(box, "launcher-row");
    GDesktopAppInfo *info = g_desktop_app_info_new_from_filename(path);
    GIcon *icon = info ? g_app_info_get_icon(G_APP_INFO(info)) : NULL;
    GtkWidget *image = icon ? gtk_image_new_from_gicon(icon) : gtk_image_new_from_icon_name("application-x-executable-symbolic");
    gtk_image_set_pixel_size(GTK_IMAGE(image), 34); gtk_box_append(GTK_BOX(box), image);
    gtk_box_append(GTK_BOX(box), label(name, 0)); gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), box);
    g_object_set_data_full(G_OBJECT(row), "application-path", g_strdup(path), g_free);
    gtk_list_box_append(GTK_LIST_BOX(host->launcher_list), row);
    g_hash_table_insert(host->roles, g_strdup_printf("launcher-entry:%s", path), row);
    if (info) g_object_unref(info);
}
void al_launcher_selected(ALHost *host, int index) {
    if (!host->launcher_list) return;
    GtkListBoxRow *row = gtk_list_box_get_row_at_index(GTK_LIST_BOX(host->launcher_list), index);
    gtk_list_box_select_row(GTK_LIST_BOX(host->launcher_list), row);
}
void al_applications(ALApplicationCallback callback, void *context) {
    GList *apps = g_app_info_get_all();
    for (GList *node = apps; node; node = node->next) {
        GAppInfo *app = node->data;
        if (!G_IS_DESKTOP_APP_INFO(app) || !g_app_info_should_show(app)) continue;
        const char *path = g_desktop_app_info_get_filename(G_DESKTOP_APP_INFO(app));
        if (path) callback(context, g_app_info_get_display_name(app), path, g_app_info_get_id(app));
    }
    g_list_free_full(apps, g_object_unref);
}
int al_launch_application(const char *path) {
    GDesktopAppInfo *app = g_desktop_app_info_new_from_filename(path);
    if (!app) return 0;
    GError *error = NULL; gboolean success = g_app_info_launch(G_APP_INFO(app), NULL, NULL, &error);
    if (error) g_error_free(error); g_object_unref(app); return success;
}
int al_open_file(const char *path) {
    GFile *file = g_file_new_for_path(path); char *uri = g_file_get_uri(file);
    GError *error = NULL; gboolean success = g_app_info_launch_default_for_uri(uri, NULL, &error);
    if (error) g_error_free(error); g_free(uri); g_object_unref(file); return success;
}
void al_copy_text(ALHost *host, const char *text) {
    gdk_clipboard_set_text(gtk_widget_get_clipboard(host->window), text);
}
