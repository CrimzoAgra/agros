/* Thunar: "Set as wallpaper" in a picture's right-click menu, through Caelestia (caelestia wallpaper -f: the picture
 * and the colours made from it). Thunar's own plugin for it knows only Xfce's and GNOME's desktops, so did nothing here
 * (agros-noextract.conf leaves it out). Only the pictures Caelestia takes (its is_valid_image: by their extension) */
#include <gtk/gtk.h>
#include <thunarx/thunarx.h>

typedef struct { GObject parent; } AgrosWallpaper;
typedef struct { GObjectClass parent; } AgrosWallpaperClass;

static void menu_provider_init(ThunarxMenuProviderIface *iface);
THUNARX_DEFINE_TYPE_WITH_CODE(AgrosWallpaper, agros_wallpaper, G_TYPE_OBJECT,
                              THUNARX_IMPLEMENT_INTERFACE(THUNARX_TYPE_MENU_PROVIDER, menu_provider_init))

static void agros_wallpaper_class_init(G_GNUC_UNUSED AgrosWallpaperClass *klass) {}
static void agros_wallpaper_init(G_GNUC_UNUSED AgrosWallpaper *self) {}

/* Caelestia's own list (caelestia/utils/wallpaper.py, is_valid_image) */
gboolean agros_wallpaper_takes(const char *path) {
    static const char *const ext[] = {".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff", ".gif"};
    const char *dot = path ? strrchr(path, '.') : NULL;
    if (!dot || strchr(dot, '/')) return FALSE;
    for (guint i = 0; i < G_N_ELEMENTS(ext); i++)
        if (!g_ascii_strcasecmp(dot, ext[i])) return TRUE;
    return FALSE;
}

static void set_wallpaper(G_GNUC_UNUSED ThunarxMenuItem *item, const char *path) {
    const char *argv[] = {"caelestia", "wallpaper", "-f", path, NULL};
    GError *err = NULL;
    if (!g_spawn_async(NULL, (char **)argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, &err)) {
        g_warning("Set as wallpaper: %s", err->message);
        g_error_free(err);
    }
}

static GList *file_menu_items(G_GNUC_UNUSED ThunarxMenuProvider *provider, G_GNUC_UNUSED GtkWidget *window,
                              GList *files) {
    if (!files || files->next) return NULL;  // (one picture: a wallpaper is one)
    GFile *loc = thunarx_file_info_get_location(files->data);
    char *path = g_file_get_path(loc);  // (a file on a drive only: Caelestia reads it from there)
    g_object_unref(loc);
    if (!agros_wallpaper_takes(path) || !g_file_test(path, G_FILE_TEST_IS_REGULAR)) {
        g_free(path);
        return NULL;
    }
    ThunarxMenuItem *item = thunarx_menu_item_new("AgrOS::set-wallpaper", "Set as wallpaper",
                                                  "Make this picture the desktop's wallpaper",
                                                  "preferences-desktop-wallpaper");
    g_signal_connect_data(item, "activate", G_CALLBACK(set_wallpaper), path, (GClosureNotify)(void (*)(void))g_free, 0);
    return g_list_append(NULL, item);
}

static void menu_provider_init(ThunarxMenuProviderIface *iface) { iface->get_file_menu_items = file_menu_items; }

static GType types[1];

G_MODULE_EXPORT void thunar_extension_initialize(ThunarxProviderPlugin *plugin) {
    agros_wallpaper_register_type(plugin);
    types[0] = agros_wallpaper_get_type();
}

G_MODULE_EXPORT void thunar_extension_shutdown(void) {}

G_MODULE_EXPORT void thunar_extension_list_types(const GType **list, gint *n) {
    *list = types;
    *n = G_N_ELEMENTS(types);
}
