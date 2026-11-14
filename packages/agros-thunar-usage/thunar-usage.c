/* Thunar: a bar in each window's status bar, beside the free-space text, showing how full the folder's drive is.
 * Each window follows its own folder (its tabs too), so each shows the drive it's on. Nothing but GTK's level bar,
 * coloured by the theme (the warning colour past 90%). Thunar's internals it relies on (a ThunarStatusbar in the
 * window, the window's "current-directory"): when one isn't there, no bar, nothing else changes */
#include <gtk/gtk.h>
#include <thunarx/thunarx.h>

typedef struct {
    GtkWidget *window;
    guint timer, gen;
    gboolean gone;
    GCancellable *pending;  // (the query not finished yet, its Query's: a tick waits for it)
} Usage;

typedef struct {
    GtkWidget *bar;
    guint gen;
    GCancellable *cancel;
} Query;

static void got_info(GObject *src, GAsyncResult *res, gpointer data) {
    Query *q = data;
    Usage *u = g_object_get_data(G_OBJECT(q->bar), "agros-usage");
    GFileInfo *info = g_file_query_filesystem_info_finish(G_FILE(src), res, NULL);
    if (u && !u->gone && q->gen == u->gen) {  // (an older query, finished after a newer one, dropped)
        guint64 size = info ? g_file_info_get_attribute_uint64(info, G_FILE_ATTRIBUTE_FILESYSTEM_SIZE) : 0;
        guint64 avail = info ? g_file_info_get_attribute_uint64(info, G_FILE_ATTRIBUTE_FILESYSTEM_FREE) : 0;
        if (size && avail <= size) {
            // (used as size - free: the same free space Thunar's text shows beside it)
            guint64 used = size - avail;
            double frac = (double)used / size;
            char *u_s = g_format_size(used), *s_s = g_format_size(size);
            char *tip = g_strdup_printf("%s of %s used (%.0f%%)", u_s, s_s, frac * 100);
            gtk_level_bar_set_value(GTK_LEVEL_BAR(q->bar), frac);
            gtk_widget_set_tooltip_text(q->bar, tip);
            g_free(u_s), g_free(s_s), g_free(tip);
        }
        gtk_widget_set_visible(q->bar, size && avail <= size);
    }
    if (u && u->pending == q->cancel) u->pending = NULL;
    if (info) g_object_unref(info);
    g_object_unref(q->cancel);
    g_object_unref(q->bar);
    g_free(q);
}

static void update(GtkWidget *bar) {
    Usage *u = g_object_get_data(G_OBJECT(bar), "agros-usage");
    GObject *dir = NULL;
    u->gen++;
    // (a change of folder: the one still asked about, on a drive that may hang, dropped for the new one)
    if (u->pending) g_cancellable_cancel(u->pending), u->pending = NULL;
    g_object_get(u->window, "current-directory", &dir, NULL);
    GFile *loc = dir && THUNARX_IS_FILE_INFO(dir) ? thunarx_file_info_get_location(THUNARX_FILE_INFO(dir)) : NULL;
    // Only folders on a drive: no size for the trash, recent files, network places
    if (loc && g_file_is_native(loc)) {
        Query *q = g_new(Query, 1);
        q->bar = g_object_ref(bar), q->gen = u->gen, q->cancel = u->pending = g_cancellable_new();
        g_file_query_filesystem_info_async(loc, G_FILE_ATTRIBUTE_FILESYSTEM_SIZE "," G_FILE_ATTRIBUTE_FILESYSTEM_FREE,
                                           G_PRIORITY_LOW, q->cancel, got_info, q);
    } else {
        gtk_widget_hide(bar);
    }
    if (loc) g_object_unref(loc);
    if (dir) g_object_unref(dir);
}

// Every 5 seconds while the window is on screen (files copied in or deleted), besides each change of folder; not while
// the last one hasn't answered (a hung network mount: they'd pile up in GIO's threads)
static gboolean tick(gpointer bar) {
    Usage *u = g_object_get_data(G_OBJECT(bar), "agros-usage");
    if (gtk_widget_get_mapped(u->window) && !u->pending) update(bar);
    return G_SOURCE_CONTINUE;
}

static void bar_destroyed(GtkWidget *bar, G_GNUC_UNUSED gpointer data) {
    Usage *u = g_object_get_data(G_OBJECT(bar), "agros-usage");
    if (u->timer) g_source_remove(u->timer), u->timer = 0;
    if (u->pending) g_cancellable_cancel(u->pending), u->pending = NULL;
    u->gone = TRUE;
}

static void find_statusbar(GtkWidget *w, gpointer found) {
    GType type = g_type_from_name("ThunarStatusbar");
    if (*(GtkWidget **)found) return;
    if (type && G_TYPE_CHECK_INSTANCE_TYPE(w, type)) *(GtkWidget **)found = w;
    else if (GTK_IS_CONTAINER(w)) gtk_container_foreach(GTK_CONTAINER(w), find_statusbar, found);
}

static void attach(GtkWidget *window) {
    GtkWidget *statusbar = NULL;
    if (g_object_get_data(G_OBJECT(window), "agros-usage-done")) return;
    g_object_set_data(G_OBJECT(window), "agros-usage-done", GINT_TO_POINTER(1));
    GParamSpec *p = g_object_class_find_property(G_OBJECT_GET_CLASS(window), "current-directory");
    if (!p || !g_type_is_a(p->value_type, G_TYPE_OBJECT) || !(p->flags & G_PARAM_READABLE)) return;
    gtk_container_foreach(GTK_CONTAINER(window), find_statusbar, &statusbar);
    if (!statusbar || !GTK_IS_BOX(statusbar)) return;

    GtkWidget *bar = gtk_level_bar_new();
    // Default offsets are a battery's (low is bad): here past 90% is, in the theme's warning colour ("low"). Adwaita's
    // and adw-gtk3's CSS paint every filled block in the accent colour after their .low rule, so .low is restated
    static GtkCssProvider *css;
    if (!css) {
        // (the theme's name for it: adw-gtk3's warning_bg_color, Adwaita's warning_color)
        GdkRGBA c;
        const char *name = gtk_style_context_lookup_color(gtk_widget_get_style_context(window), "warning_bg_color", &c)
                               ? "warning_bg_color" : "warning_color";
        char *rule = g_strdup_printf("levelbar.agros-usage block.low:not(.empty) "
                                     "{ background-color: @%s; border-color: @%s; }", name, name);
        css = gtk_css_provider_new();
        gtk_css_provider_load_from_data(css, rule, -1, NULL);
        g_free(rule);
        gtk_style_context_add_provider_for_screen(gtk_widget_get_screen(window), GTK_STYLE_PROVIDER(css),
                                                  GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    }
    gtk_style_context_add_class(gtk_widget_get_style_context(bar), "agros-usage");
    gtk_level_bar_remove_offset_value(GTK_LEVEL_BAR(bar), GTK_LEVEL_BAR_OFFSET_LOW);
    gtk_level_bar_remove_offset_value(GTK_LEVEL_BAR(bar), GTK_LEVEL_BAR_OFFSET_HIGH);
    gtk_level_bar_remove_offset_value(GTK_LEVEL_BAR(bar), GTK_LEVEL_BAR_OFFSET_FULL);
    gtk_level_bar_add_offset_value(GTK_LEVEL_BAR(bar), GTK_LEVEL_BAR_OFFSET_HIGH, 0.9);
    gtk_level_bar_add_offset_value(GTK_LEVEL_BAR(bar), GTK_LEVEL_BAR_OFFSET_LOW, 1.0);
    gtk_widget_set_size_request(bar, 120, -1);
    gtk_widget_set_valign(bar, GTK_ALIGN_CENTER);
    gtk_widget_set_margin_start(bar, 6);
    gtk_widget_set_margin_end(bar, 6);
    gtk_widget_set_no_show_all(bar, TRUE);
    gtk_box_pack_end(GTK_BOX(statusbar), bar, FALSE, FALSE, 0);

    Usage *u = g_new0(Usage, 1);
    u->window = window;
    g_object_set_data_full(G_OBJECT(bar), "agros-usage", u, g_free);
    g_signal_connect(bar, "destroy", G_CALLBACK(bar_destroyed), NULL);
    g_signal_connect_object(window, "notify::current-directory", G_CALLBACK(update), bar, G_CONNECT_SWAPPED);
    u->timer = g_timeout_add_seconds(5, tick, bar);
    update(bar);
}

static gboolean on_map(G_GNUC_UNUSED GSignalInvocationHint *hint, G_GNUC_UNUSED guint n, const GValue *params,
                       G_GNUC_UNUSED gpointer data) {
    GType type = g_type_from_name("ThunarWindow");
    GObject *w = g_value_get_object(&params[0]);
    if (type && G_TYPE_CHECK_INSTANCE_TYPE(w, type)) attach(GTK_WIDGET(w));
    return TRUE;
}

G_MODULE_EXPORT void thunar_extension_initialize(ThunarxProviderPlugin *plugin) {
    static gboolean done;
    // (resident: its hook and bars outlive the call that loaded it)
    thunarx_provider_plugin_set_resident(plugin, TRUE);
    if (done) return;
    done = TRUE;
    // Each Thunar window as it comes on screen (the first is still being made when this loads)
    g_signal_add_emission_hook(g_signal_lookup("map", GTK_TYPE_WIDGET), 0, on_map, NULL, NULL);
    GList *wins = gtk_window_list_toplevels();
    for (GList *l = wins; l; l = l->next) {
        GType type = g_type_from_name("ThunarWindow");
        if (type && G_TYPE_CHECK_INSTANCE_TYPE(l->data, type) && gtk_widget_get_mapped(l->data)) attach(l->data);
    }
    g_list_free(wins);
}

G_MODULE_EXPORT void thunar_extension_shutdown(void) {}

G_MODULE_EXPORT void thunar_extension_list_types(const GType **types, gint *n_types) {
    *types = NULL;
    *n_types = 0;
}
