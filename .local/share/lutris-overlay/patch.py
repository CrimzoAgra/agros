"""Applies the changes to a copy of Lutris made of links to the installed files (~/.local/bin/lutris builds it).
Usage: patch.py <installed lutris package> <copy's root, holding lutris/ and bin/>
       patch.py --list    the changes that can be turned off (Settings app, Features page; settings lutris.<name>)
An optional change (OPTIONAL) that no longer fits is left out, with a WARNING line; any other one (the Steam fix...)
fails the whole build: Lutris then starts unchanged"""

import json
import os
import pwd
import shutil
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))


class Miss(Exception):
    """A change's text (or its file) not found in this Lutris"""


def read(rel):
    """A file of the copy, empty if this Lutris no longer has it (a renamed file is text not found, not a crash)"""
    try:
        with open(os.path.join(pkg, rel), encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return ""


def edit(rel, old, new):
    """Replace the one occurrence of old in a file of the copy, which becomes a file of its own"""
    path = os.path.join(pkg, rel)
    if not os.path.exists(path):
        raise Miss(f"{rel}: file not found")
    text = read(rel)
    if text.count(old) != 1:
        raise Miss(f"{rel}: expected text not found once: {old.strip().splitlines()[0]}")
    os.remove(path)
    # Its cached bytecode is for the original
    cache = os.path.join(os.path.dirname(path), "__pycache__")
    for name in os.listdir(cache) if os.path.isdir(cache) else []:
        if name.startswith(os.path.basename(path)[:-3] + "."):
            os.remove(os.path.join(cache, name))
    with open(path, "w", encoding="utf-8") as f:
        f.write(text.replace(old, new))


# Grid: installed and uninstalled games in two collapsible sections (sections.py)
def sections():
    shutil.copy(os.path.join(here, "sections.py"), os.path.join(pkg, "gui/views/sections.py"))
    edit("gui/lutriswindow.py", "from lutris.gui.views.grid import GameGridView\n",
         "from lutris.gui.views.grid import GameGridView\nfrom lutris.gui.views.sections import SectionedGridView\n")
    edit("gui/lutriswindow.py", "self.current_view = GameGridView(", "self.current_view = SectionedGridView(")


# A Steam game installed: the uninstalled entry ~/.local/bin/lutris-library added for it gives way to the installed one.
# With both, Lutris's duplicate cleanup deletes the installed one (it keeps copies with playtime or without a config)
def steam_placeholder():
    edit("services/steam.py", """            configpath = write_game_config(lutris_game_id, game_config)
""", """            configpath = write_game_config(lutris_game_id, game_config)
            for placeholder in get_games(filters={"service": self.id, "service_id": appid, "installed": "0"}):
                if not placeholder["configpath"]:
                    # (its categories too: the installed one can get its id back, and with it "hidden")
                    sql.db_delete(settings.DB_PATH, "games_categories", "game_id", placeholder["id"])
                    sql.db_delete(settings.DB_PATH, "games", "id", placeholder["id"])
""")



# A store game uninstalled in Lutris (or marked so by a Steam sync while its drive wasn't mounted), then found installed
# again by its store's scan (Steam, Epic, EA, Battle.net): Lutris finds the old entry and stops, so it stays "not
# installed" for good. Now the old entry is installed again, its playtime and categories kept
def revive_installed():
    edit("database/games.py", "\n\ndef add_games_bulk(", """


def add_or_revive(existing, **game_data):  # lutris-overlay: revive_installed
    \"\"\"add_game, or the store's old uninstalled entry for it made installed again\"\"\"
    if not existing:
        return add_game(**game_data)
    sql.db_update(settings.DB_PATH, "games", game_data, {"id": existing["id"]})
    return existing["id"]


def add_games_bulk(""")
    for rel in ("services/steam.py", "services/egs.py", "services/ea_app.py", "services/battlenet.py"):
        edit(rel, "from lutris.database.games import add_game, ", "from lutris.database.games import add_game, add_or_revive, ")
        pad = "            " if rel.endswith("steam.py") else "        "
        ret = next((r for r in ("return\n", "return None\n") if f"{pad}if existing_game:\n{pad}    {r}" in read(rel)), "return\n")
        edit(rel, f"{pad}if existing_game:\n{pad}    {ret}", f"{pad}if existing_game and existing_game[\"installed\"]:\n{pad}    {ret}")
        edit(rel, "add_game(\n", "add_or_revive(existing_game,\n")


# Right-click: "Hide game from library" for uninstalled games too (Lutris offers it only for installed ones)
def hide_uninstalled():
    edit("game_actions.py", '"hide": any(g for g in self.games if g.is_installed and not g.is_hidden),',
         '"hide": any(g for g in self.games if g.is_db_stored and not g.is_hidden),')
    edit("game_actions.py", '"hide": game.is_installed and not game.is_hidden,',
         '"hide": game.is_db_stored and not game.is_hidden,')


# Games view: the store launchers (~/.local/bin/lutris-library's Launchers category) only under Launchers in the sidebar,
# not among the games. Launchers is a row of the sidebar's Library, below Uncategorized, not a user category
def launchers_apart():
    edit("gui/lutriswindow.py", """        category_game_ids = categories_db.get_game_ids_for_categories(included, excluded)
""", """        if category == "all":  # lutris-overlay: launchers_apart (lutris-library's category)
            excluded = excluded + ["Launchers"]
        category_game_ids = categories_db.get_game_ids_for_categories(included, excluded)
""")
    edit("gui/widgets/sidebar.py", """                self.get_sidebar_icon("tag-symbolic", ["poi-marker", "favorite-symbolic"]),
            )
        )
""", """                self.get_sidebar_icon("tag-symbolic", ["poi-marker", "favorite-symbolic"]),
            )
        )

        self.add(  # lutris-overlay: launchers_apart
            SidebarRow(
                "Launchers",
                "category",
                _("Launchers"),
                self.get_sidebar_icon("system-software-install-symbolic", ["applications-other-symbolic"]),
            )
        )
""")
    edit("gui/widgets/sidebar.py",
         """categories = [c for c in categories_db.get_categories() if not categories_db.is_reserved_category(c["name"])]""",
         """categories = [c for c in categories_db.get_categories() if not categories_db.is_reserved_category(c["name"])
                      and c["name"] != "Launchers"]  # lutris-overlay: launchers_apart (a Library row)""")


# ~/.local/bin/lutris-library's changes (store games added, the launchers listed, copies hidden) shown in an open Lutris
# at once: an action the script activates over D-Bus (org.freedesktop.Application.ActivateAction on net.lutris.Lutris,
# which Gtk exports for every action added here) that reads the library again, sidebar and view. Without it (plain
# Lutris, or this change left out) the changes show once Lutris restarts
def library_refresh():
    edit("gui/application.py", """        action = Gio.SimpleAction.new("quit")
        action.connect("activate", lambda *x: self.quit())
        self.add_action(action)
""", """        action = Gio.SimpleAction.new("quit")
        action.connect("activate", lambda *x: self.quit())
        self.add_action(action)
        # lutris-overlay: library_refresh (lutris-library's changes shown without a restart)
        action = Gio.SimpleAction.new("library-refresh")
        action.connect("activate", lambda *x: self.on_library_refresh())
        self.add_action(action)
""")
    # (before do_activate, by its name only: newer Lutris writes it "def do_activate(self) -> None:")
    edit("gui/application.py", """    def do_activate(self)""", """    def on_library_refresh(self):
        \"\"\"lutris-overlay: the window reads the library again (sidebar categories, the games shown)\"\"\"
        if self.window:
            self.window.sidebar.update_rows()
            self.window.update_store()

    def do_activate(self)""")


# Grid: in the Games view every cover fills the same box, cropped at the edges like Steam's library (Steam's covers are
# 2:3, Lutris's 3:4: they showed at different widths)
# Header bar, top right: one button that syncs every store Lutris shows in the sidebar (what each one's Reload does),
# the signed-in ones only. lutris-library then adds the new games as it does after any sync
def sync_all():
    edit("gui/lutriswindow.py", """    show_hidden_games_button: Gtk.ModelButton = GtkTemplate.Child()
""", """    show_hidden_games_button: Gtk.ModelButton = GtkTemplate.Child()
    right_header_box: Gtk.Box = GtkTemplate.Child()  # lutris-overlay: sync_all
""")
    edit("gui/lutriswindow.py", """        self.set_viewtype_icon(self.current_view_type)
""", """        self.set_viewtype_icon(self.current_view_type)

        sync_button = Gtk.Button.new_from_icon_name("view-refresh-symbolic", Gtk.IconSize.BUTTON)  # lutris-overlay: sync_all
        sync_button.set_tooltip_text(_("Sync all libraries"))
        sync_button.connect("clicked", self.on_sync_all_clicked)
        sync_button.show()
        self.right_header_box.pack_start(sync_button, False, False, 0)
        self.right_header_box.reorder_child(sync_button, 0)
""")
    edit("gui/lutriswindow.py", """    def on_busy_started(self):""", """    def on_sync_all_clicked(self, button):  # lutris-overlay: sync_all
        from lutris.services import get_enabled_services
        from lutris.services.base import AuthTokenExpiredError
        services = [s() for s in get_enabled_services().values()]
        services = [s for s in services if not s.online or s.is_authenticated()]
        if not services:
            return
        spinner = Gtk.Spinner(active=True, visible=True)
        icon = button.get_image()
        button.set_image(spinner)
        button.set_sensitive(False)
        left, failed = [len(services)], []

        def done(error, service):
            # Steam with a private profile always fails here (lutris-library adds its installed games anyway)
            if error and "profile is set to public" not in str(error):
                failed.append(f"{service.name}: " + (_("sign in again from the sidebar")
                              if isinstance(error, AuthTokenExpiredError) or "not authenticated" in str(error)
                              else str(error)))
            left[0] -= 1
            if not left[0]:
                button.set_image(icon)
                button.set_sensitive(True)
                if failed:  # one message for all of them, not a dialog each
                    # (plain text, uncut: Lutris's ErrorDialog cuts its text at 256 characters, markup and all)
                    dialog = Gtk.MessageDialog(transient_for=self, message_type=Gtk.MessageType.ERROR,
                                               buttons=Gtk.ButtonsType.OK, text=_("Some libraries didn't sync"),
                                               secondary_text="\\n".join(failed))
                    dialog.connect("response", lambda d, _r: d.destroy())
                    dialog.show()

        for service in services:
            service.start_reload(lambda error, s=service: done(error, s))

    def on_busy_started(self):""")


def same_size_covers():
    edit("gui/widgets/cellrenderers.py", """        media_height = media_path.height
""", """        media_height = media_path.height
        if self.is_library_view() and self._expected_width:
            # The view's cover size, not the source's (a Steam cover found as fallback is sized like Steam's)
            media_width, media_height = self._expected_width, self._expected_height
""")
    edit("gui/widgets/cellrenderers.py",
         "surface = self._get_cached_surface_by_path(widget, path, size=(media_width, media_height))",
         "surface = self._get_cached_surface_by_path(widget, path, size=(media_width, media_height),\n"
         "                                                       preserve_aspect_ratio=\"fill\" if self.is_library_view() else True)")
    edit("gui/widgets/cellrenderers.py", """        scale_factor = widget.get_scale_factor() if widget else 1
        try:
""", """        scale_factor = widget.get_scale_factor() if widget else 1
        try:
            if preserve_aspect_ratio == "fill":
                return _get_filled_surface_by_path(path, cell_size, scale_factor)
""")
    edit("gui/widgets/cellrenderers.py", """def _on_media_cached_invalidated() -> None:
""", """def _get_filled_surface_by_path(path, size, device_scale):
    \"\"\"Like get_scaled_surface_by_path, but filling the size exactly: scaled to cover it, centred, edges cropped\"\"\"
    from lutris.gui.widgets.utils import get_pixbuf_by_path

    pixbuf = get_pixbuf_by_path(path)
    if not pixbuf:
        return None
    width, height = round(size[0] * device_scale), round(size[1] * device_scale)
    scale = max(width / pixbuf.get_width(), height / pixbuf.get_height())
    surface = cairo.ImageSurface(cairo.Format.ARGB32, width, height)  # pylint:disable=no-member
    cr = cairo.Context(surface)  # pylint:disable=no-member
    cr.translate((width - pixbuf.get_width() * scale) / 2, (height - pixbuf.get_height() * scale) / 2)
    cr.scale(scale, scale)
    Gdk.cairo_set_source_pixbuf(cr, pixbuf, 0, 0)
    cr.paint()
    surface.set_device_scale(device_scale, device_scale)
    return surface


def _on_media_cached_invalidated() -> None:
""")



# Cover tiles shaped like box art (2:3, Steam's and SteamGridDB's 600x900), not Lutris's 3:4 that cut their top and
# bottom off. Lutris.net's 3:4 covers lose a little of their sides instead
def tall_covers():
    edit("services/base.py", """    size = (264, 352)
    file_patterns = ["%s.jpg", "%s.png"]""", """    size = (264, 396)  # lutris-overlay: tall_covers
    file_patterns = ["%s.jpg", "%s.png"]""")
    edit("services/base.py", """class LutrisCoverartMedium(LutrisCoverart):
    size = (176, 234)""", """class LutrisCoverartMedium(LutrisCoverart):
    size = (176, 264)  # lutris-overlay: tall_covers""")
    edit("services/battlenet.py", """    service = "battlenet"
    size = (176, 234)""", """    service = "battlenet"
    size = (176, 264)  # lutris-overlay: tall_covers""")
    if read("services/rockstar.py"):  # (rockstar_source's, when on)
        edit("services/rockstar.py", "    size = (176, 234)\n", "    size = (176, 264)  # lutris-overlay: tall_covers\n")


# Covers with rounded corners, in every view
def rounded_covers():
    edit("gui/widgets/cellrenderers.py", """                media_area.x = 0
                media_area.y = 0
""", """                media_area.x = 0
                media_area.y = 0

                surface_width, surface_height = get_surface_size(surface)
                radius = min(surface_width, surface_height) * 0.06
                cr.new_path()
                for corner, (x, y) in enumerate(((surface_width - radius, radius), (surface_width - radius, surface_height - radius),
                                                 (radius, surface_height - radius), (radius, radius))):
                    cr.arc(x, y, radius, (corner - 1) * 1.5708, corner * 1.5708)
                cr.close_path()
                cr.clip()
""")


# Started at login with LUTRIS_START_HIDDEN=1 (~/.config/caelestia/user/apps.lua): only its tray icon, no window. Once:
# opening Lutris later shows it. The tray icon is turned on for it (a fresh Lutris has it off): with no icon there'd be
# no way back to the window
def start_hidden():
    edit("gui/application.py", """            self.window.present()
            self.start_runtime_updates()
""", """            if os.environ.pop("LUTRIS_START_HIDDEN", None) == "1":
                if not self.has_tray_icon():
                    settings.write_setting("show_tray_icon", True)
                    self.set_tray_icon()
            else:
                self.window.present()
            self.start_runtime_updates()
""")


# A game stopping showed Lutris's window again (Lutris hides it for the game with "Minimize client when a game is
# launched", then shows it back): it stays closed, in the tray; open it from there or the launcher
def window_after_game():
    edit("gui/application.py", """        if self.window and settings.read_bool_setting("hide_client_on_game_start") and not self.quit_on_game_exit:
            self.window.show()  # Show launcher window""", """        if self.window and settings.read_bool_setting("hide_client_on_game_start") and not self.quit_on_game_exit:
            if not self.has_tray_icon():  # caelestia-overlay: not shown again, unless there's no tray icon to open it
                self.window.show()""")
    # A game from the launcher, the dock or the bar (lutris:rungameid/N) made the Lutris already in its tray quit when the
    # game ended: only a Lutris started just for the game does (no window yet). Newer Lutris checks its tray icon itself
    if "if not self.has_tray_icon() and (not self.window" in read("gui/application.py"):
        return
    for comment in ("# Force db_game to use game id", "# Force db_game to use game slug",
                    "# Installers can use game or installer slugs"):
        edit("gui/application.py", f"""                {comment}
                self.quit_on_game_exit = True
""", f"""                {comment}
                self.quit_on_game_exit = self.window is None
""")


# Lutris already running (in its tray): opening it again hands the launch to it, which ran its whole start-up again each
# time: the GPU checks (vulkaninfo, glxinfo: the desktop stalled while the GPU answered), the library checks, a scan of
# every game's folder. Once per run is enough
def startup_once():
    # From the log line to the end of the run_all_checks(...) line, indented under a once-only check (newer Lutris
    # versions pass run_all_checks arguments)
    text = read("gui/application.py")
    start = text.find('        logger.info("Starting Lutris %s", settings.VERSION)\n')
    checks = text.find("        run_all_checks(", start)
    end = text.find("\n", checks) + 1
    # (no run_all_checks: find(-1) would take the rest of the file into the block)
    if start < 0 or checks < 0 or end <= start:
        raise Miss("gui/application.py: start-up block not found")
    block = text[start:end]
    once = '        if not getattr(self, "_started", False):\n            self._started = True\n' + "".join(
        ("    " + line if line.strip() else line) for line in block.splitlines(True))
    edit("gui/application.py", block, once)


# Start-up runs vulkaninfo twice per graphics card (its name, its ID), which stalls the desktop while the GPU answers.
# Its answer only changes with a reboot: kept in the session's runtime folder, so only the first start (at login, hidden)
# asks. shortcut: a GPU plugged in or switched without a reboot isn't seen until then; delete the file to re-ask
def vulkaninfo_once():
    old = """        vulkaninfo_output_raw = system.read_process_output(
            ["/usr/bin/vulkaninfo", "--summary"], env=os.environ, error_result=None
        )
"""
    # Newer Lutris (master, 2026) rewrote this and runs it once per start: skipped there, not an error
    if old not in read("util/graphics/gpu.py"):
        return
    edit("util/graphics/gpu.py", old, """        cache = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/nonexistent", "lutris-vulkaninfo")
        try:
            with open(cache, encoding="utf-8") as f:
                vulkaninfo_output_raw = f.read()
        except OSError:
""" + "".join("    " + line for line in old.splitlines(True)) + """            if vulkaninfo_output_raw:
                try:
                    with open(cache, "w", encoding="utf-8") as f:
                        f.write(vulkaninfo_output_raw)
                except OSError:
                    pass
""")


# A program Lutris starts and forgets (a link opened in the browser, Steam's install page) stayed a zombie process once
# it ended, until Lutris happened to start another: now waited for in the background. Left out without a word where a
# newer Lutris changed that code
def reap_children():
    rel, old = "util/system.py", """        subprocess.Popen(  # pylint: disable=consider-using-with
            command, shell=shell, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=existing_env, cwd=cwd
        )
"""
    if old not in read(rel):
        return
    edit(rel, old, "        child = " + old.lstrip() +
         '        __import__("threading").Thread(target=child.wait, daemon=True).start()  # caelestia-overlay: no zombie\n')


# Flathub's Steam: Lutris looks for it only in data/Steam, where older versions of it kept their folder; newer ones keep
# it in .local/share/Steam (as steam-installed-games reads), so Lutris saw no Steam at all (no installed game, none
# added). Left out without a word where a newer Lutris changed that list
def flathub_steam():
    rel, old = "util/steam/config.py", """    "~/.var/app/com.valvesoftware.Steam/data/Steam",
"""
    if old not in read(rel):
        return
    edit(rel, old, old + '    "~/.var/app/com.valvesoftware.Steam/.local/share/Steam",  # caelestia-overlay: flathub_steam\n')


# Battle.net's source with the Battle.net app not installed in Lutris: its scan for installed games stopped with an error
# dialog on each reload (Ubisoft's just logs it). Logged and skipped now; left out where a newer Lutris changed that code
def bnet_not_installed():
    rel, old = "services/battlenet.py", """            raise RuntimeError("Battle.net is not installed in Lutris")
"""
    if old not in read(rel):
        return
    edit(rel, old, """            logger.warning("Battle.net is not installed in Lutris")  # caelestia-overlay: not an error dialog
            return
""")
    # lutris-library's Launchers entry for it, not installed: there, with no folder (a crash on None)
    edit(rel, """        if not bnet_game:
""", """        if not bnet_game or not bnet_game["directory"]:
""")


# Battle.net among Lutris's sources (sidebar, Games view): Lutris turns on only GOG, Epic, EA, Ubisoft and Steam, each
# at its start while still unset, so Battle.net never showed. It's one of them now; switched off in Lutris's
# preferences, it stays off (no longer unset)
def bnet_source():
    edit("services/__init__.py", 'DEFAULT_SERVICES = ["gog", "egs", "ea_app", "ubisoft", "steam"]',
         'DEFAULT_SERVICES = ["gog", "egs", "ea_app", "ubisoft", "steam", "battlenet"]  # caelestia-overlay: bnet_source')


# Rockstar Games among Lutris's sources, which has none (rockstar.py: its games, installed through the Rockstar Games
# Launcher; signin.py: the sign-in, shared with bnet_login), on by default like the others
def rockstar_source():
    shutil.copy(os.path.join(here, "signin.py"), os.path.join(pkg, "services/signin.py"))  # (bnet_login's too)
    shutil.copy(os.path.join(here, "rockstar.py"), os.path.join(pkg, "services/rockstar.py"))
    # (only the start of the line: Lutris's master has "def get_services() -> dict[...]:", and imports Battle.net's
    # service without BNET_ENABLED)
    edit("services/__init__.py", "\n\ndef get_services(", """
DEFAULT_SERVICES = DEFAULT_SERVICES + ["rockstar"]  # caelestia-overlay: rockstar_source


def get_services(""")
    edit("services/__init__.py", "from lutris.services.battlenet import ",
         "from lutris.services.rockstar import RockstarService  # caelestia-overlay: rockstar_source\n"
         "from lutris.services.battlenet import ")
    edit("services/__init__.py", """        "flathub": FlathubService,
""", """        "flathub": FlathubService,
        "rockstar": RockstarService,
""")


# Battle.net with a sign-in: Lutris's Battle.net source was its built-in list of every Blizzard game, owned or not. Now
# you sign in (Lutris's login window, the account site's own sign-in) and it lists the games on your account. The account
# site only answers its own pages, so the games are read from inside the signed-in page. Each reload signs in again the
# same way, unseen (Battle.net remembers the sign-in for a year), so the list follows the account; if that fails, the
# last list is kept (signin.py, shared with rockstar_source). Signing in doesn't need the Battle.net app
def bnet_login():
    rel = "services/battlenet.py"
    # Signed in without the Battle.net app, a game opened to install: the app's installer first (as Ubisoft's source
    # does), not an error (it looked the app up and found none). Lutris's master has install(self, db_game,
    # update=False), which hands a missing app to its base install: the installer is shown first there too
    head = next((h for h in ("    def install(self, db_game, update=False):\n", "    def install(self, db_game):\n")
                 if h in read(rel)), "    def install(self, db_game):\n")
    lookup = '        bnet_game = get_game_by_field(self.client_installer, "slug")\n'
    edit(rel, head + lookup, head + lookup + """        if not bnet_game or not self.is_launcher_installed():
            Gio.Application.get_default().show_lutris_installer_window(game_slug=self.client_installer)
            return
""")
    shutil.copy(os.path.join(here, "signin.py"), os.path.join(pkg, "services/signin.py"))  # (rockstar_source's too)
    edit(rel, "from lutris.services.base import BaseService\n",
         "from lutris.services.signin import SignInService, name_key  # caelestia-overlay: bnet_login\n")
    edit(rel, "class BattleNetService(BaseService):", "class BattleNetService(SignInService):")
    edit(rel, '    redirect_uris = ["https://lutris.net"]\n', "")  # (SignInService's: none)
    edit(rel, """    def load(self):
        games = [BattleNetGame.create(game) for game in GAME_IDS.values()]
        for game in games:
            game.save()
        return games
""", """    # caelestia-overlay: sign-in (bnet_login in ~/.local/share/lutris-overlay/patch.py, signin.py)
    label = "Battle.net"
    login_url = "https://account.battle.net/oauth2/authorization/account-settings"
    login_window_width = 480
    login_window_height = 700
    owned_path = os.path.join(settings.CACHE_DIR, "bnet-owned.json")
    hand_over = "https://account.battle.net/lutris-owned?"
    # On a signed-in account page: the page asks its own API for the games (signing in first if its session isn't up
    # yet) and hands them over by opening hand_over with them, caught by _watch before it loads
    _read_games = \"\"\"(async () => {
        const done = d => window.location.replace("https://account.battle.net/lutris-owned?d=" + encodeURIComponent(JSON.stringify(d)));
        try {
            const auth = await (await fetch("/api/", {method: "POST", credentials: "include"})).json();
            if (!auth.authenticated) { window.location.replace(auth.loginUri); return; }
            const xsrf = (document.cookie.match(/XSRF-TOKEN=([^;]+)/) || [])[1] || "";
            const get = async p => {
                const r = await fetch(p, {credentials: "include", headers: {"Accept": "application/json", "X-XSRF-TOKEN": xsrf}});
                if (!r.ok) throw new Error(`${p}: ${r.status}`); // not "no games": the last list is kept
                return r.json();
            };
            const subs = await get("/api/games-and-subs"), classic = await get("/api/classic-games");
            if (!Array.isArray(subs.gameAccounts)) throw new Error("no games list in the answer");
            done({names: [...(subs.gameAccounts || []), ...(classic.classicGames || [])].map(g => g.localizedGameName).filter(Boolean)});
        } catch (e) { done({error: String(e)}); }
    })();\"\"\"
    # The account site's names of games Lutris lists under another name, or not on their own
    ALIASES = {
        "overwatch": ["pro"], "warcraftiiireforged": ["w3"], "starcraftremastered": ["s1"], "starcraft": ["s1"],
        "worldofwarcraft": ["wow", "wow_classic", "wow_classic_era"], "diabloiii": ["d3"],
        "callofduty": ["codhq"], "callofdutywarzone": ["codhq"], "callofdutymodernwarfareiii": ["codhq"],
        "callofdutyblackops6": ["codhq"], "callofdutyblackops7": ["codhq"],
    }
    # Games that left Battle.net (still on the account): not Lutris's to list
    GONE = {"destiny2"}

    def _games_page(self, url):
        return url.startswith("https://account.battle.net/") and not any(
            part in url for part in ("/login", "/oauth2/", "/callback/", "lutris-owned"))

    def _signin_page(self, url):
        return "/login/" in url

    def _names(self, data):
        if not isinstance(data.get("names"), list):
            logger.error("Battle.net: the games list couldn't be read: %s", data.get("error"))
            return None
        return data["names"]

    def _by_key(self):
        return {name_key(g[1]): [g[0]] for g in GAME_IDS.values() if g[0] != "d3cn"}

    def _game(self, appid):
        return BattleNetGame.create(GAME_IDS[appid])
""")


# A source's own page left games out at random: it drops hidden games by checking each entry's own id against the
# library's hidden games, but a source entry's id counts in another table, so an entry whose number a hidden library game
# has (a hidden Ubisoft copy) went missing (all of Battle.net's). Checked by its library entry instead, none: not hidden.
# Each part left out without a word where a newer Lutris changed that code
def source_page_ids():
    for rel, old, new in (
        ("gui/lutriswindow.py", """        \"\"\"Inject lutris game information into a service game\"\"\"
        if lutris_game and service_game["appid"] == lutris_game["service_id"]:
""", """        \"\"\"Inject lutris game information into a service game\"\"\"
        matched = lutris_game and service_game["appid"] == lutris_game["service_id"]
        service_game["lutris_game_id"] = lutris_game["id"] if matched else None  # caelestia-overlay: source_page_ids
        if matched:
"""),
        ("search.py", """        def is_categorized(db_game):
            return db_game["id"] not in uncategorized_ids""", """        def is_categorized(db_game):
            return db_game.get("lutris_game_id", db_game["id"]) not in uncategorized_ids  # caelestia-overlay"""),
        ("search.py", """        def match_category(db_game):
            game_id = db_game["id"]""", """        def match_category(db_game):
            game_id = db_game.get("lutris_game_id", db_game["id"])  # caelestia-overlay: a source page's game"""),
        ("search.py", """        def is_in_category(db_game):
            game_id = db_game["id"]""", """        def is_in_category(db_game):
            game_id = db_game.get("lutris_game_id", db_game["id"])  # caelestia-overlay: a source page's game"""),
    ):
        if old in read(rel):
            edit(rel, old, new)


# Store icons Lutris lacks (Battle.net's: ~/.local/share/lutris-overlay/icons) found like its own, and a source icon
# from the icon theme (EA's) drawn at the size of the others in Preferences and the sidebar, not the file's (256 px)
def source_icons():
    for rel, old, new in (("gui/widgets/utils.py", """    for search_dir in search_directories:
        for ext in extensions:
            icon_path = os.path.join(settings.RUNTIME_DIR, search_dir, filename + ext)
            if os.path.exists(icon_path):
                return icon_path
    return None
""", f"""    for search_dir in search_directories:
        for ext in extensions:
            icon_path = os.path.join(settings.RUNTIME_DIR, search_dir, filename + ext)
            if os.path.exists(icon_path):
                return icon_path
    for ext in extensions:  # caelestia-overlay: source_icons
        icon_path = os.path.join({os.path.join(here, "icons")!r}, filename + ext)
        if os.path.exists(icon_path):
            return icon_path
    return None
"""), ("gui/widgets/scaled_image.py", """        else:
            if not has_stock_icon(fallback_stock_icon_name):""", """        elif fallback_stock_icon_name and (theme_icon := Gtk.IconTheme.get_default().lookup_icon(
                fallback_stock_icon_name, ICON_SIZE[1], 0)) and theme_icon.get_filename():
            # caelestia-overlay: source_icons (EA's 256 px one at the others' size)
            icon = ScaledImage.new_scaled_from_path(theme_icon.get_filename(), size=ICON_SIZE, scale_factor=scale_factor)
        else:
            if not has_stock_icon(fallback_stock_icon_name):""")):
        if old in read(rel):  # left out without a word where a newer Lutris changed that code
            edit(rel, old, new)


# Grid: the icon of the store a game comes from (Steam, EA, Ubisoft...) in its cover's bottom-right corner, in the
# Games view (a store's own view is all that store)
def store_icons():
    edit("gui/widgets/cellrenderers.py", """                    cr.paint_with_alpha(alpha)
                cr.restore()
""", """                    cr.paint_with_alpha(alpha)
                self._render_source(cr, widget, surface)
                cr.restore()
""")
    edit("gui/widgets/cellrenderers.py", """    def select_badge_metrics(self, surface, media_width, media_height):
""", """    _source_icon_paths = {}

    def _render_source(self, cr, widget, surface):
        if not self.is_library_view() or not self.game_id:
            return
        path = self._get_source_icon_path(self.game_id)
        width, height = get_surface_size(surface)
        size = round(min(width, height) * 0.2)
        icon = path and size >= 12 and self._get_cached_surface_by_path(widget, path, size=(size, size))
        if not icon:
            return
        # The store's icon in light grey with its logo cut out (Ubisoft's: just the logo), nothing behind it
        icon_width, icon_height = get_surface_size(icon)
        # The cover darkened towards its bottom-right corner, so the icon stands out on light covers
        shade = cairo.RadialGradient(width, height, 0, width, height, size * 2.6)  # pylint:disable=no-member
        shade.add_color_stop_rgba(0, 0, 0, 0, 0.7)
        shade.add_color_stop_rgba(0.5, 0, 0, 0, 0.45)
        shade.add_color_stop_rgba(1, 0, 0, 0, 0)
        cr.set_source(shade)
        cr.paint()
        cr.set_source_rgba(0.85, 0.85, 0.85, 0.9)
        cr.mask_surface(self._get_logo_mask(path, icon), width - icon_width - 6, height - icon_height - 6)

    _logo_masks = {}

    @staticmethod
    def _get_logo_mask(path, icon):
        # A store icon is a logo on a base of the other tone (Steam's white logo on a dark disc, GOG's dark letters on
        # a white box): which one is the logo, by icon name; for others, the tone covering less of it. The base with
        # the logo cut out is kept, except Ubisoft's, whose base is a white disc around the swirl: its logo
        masks = GridViewCellRendererImage._logo_masks
        key = (path, icon.get_width())
        if key not in masks:
            icon.flush()
            width, height, stride = icon.get_width(), icon.get_height(), icon.get_stride()
            data = bytes(icon.get_data())  # premultiplied B, G, R, A
            light, dark, shape = bytearray(width * height), bytearray(width * height), bytearray(width * height)
            for i in range(width * height):
                y, x = divmod(i, width)
                b, g, r, a = data[y * stride + x * 4:y * stride + x * 4 + 4]
                if a:
                    shape[i] = solid = min(255, a * 4)  # solid where the icon is see-through (GOG's box: 34%)
                    brightness = (r * 54 + g * 183 + b * 18) // a  # 0..255, alpha undone
                    light[i] = min(255, solid * max(0, brightness - 96) * 2 // 255)
                    dark[i] = min(255, solid * max(0, 160 - brightness) * 2 // 255)
            name = path.rsplit("/", 1)[-1].rsplit(".", 1)[0]
            tone = {"steam-client": "light", "egs": "light", "ea_app": "light", "ubisoft": "dark", "gog": "dark"}.get(name)
            if tone is None:
                tone = "light" if sum(v > 128 for v in light) < sum(v > 128 for v in dark) else "dark"
            values = light if tone == "light" else dark
            if name in ("battlenet", "rockstar", "ea_app"):
                values = shape  # just a logo, no base: the logo itself
            elif name != "ubisoft":
                values = bytes(max(0, s - v) for s, v in zip(shape, values))
            mask_stride = cairo.ImageSurface.format_stride_for_width(cairo.Format.A8, width)  # pylint:disable=no-member
            buffer = bytearray(mask_stride * height)
            for y in range(height):
                buffer[y * mask_stride:y * mask_stride + width] = values[y * width:(y + 1) * width]
            mask = cairo.ImageSurface.create_for_data(buffer, cairo.Format.A8, width, height, mask_stride)  # pylint:disable=no-member
            mask.set_device_scale(*icon.get_device_scale())
            masks[key] = mask
        return masks[key]

    @staticmethod
    def _get_source_icon_path(game_id):
        paths = GridViewCellRendererImage._source_icon_paths
        if game_id not in paths:
            from lutris.database.games import get_game_by_field
            from lutris.services import SERVICES

            service = SERVICES.get((get_game_by_field(game_id, "id") or {}).get("service") or "")
            path = None
            if service:
                # Lutris's own icons, else the icon theme's (EA has none in Lutris)
                path = get_runtime_icon_path(service.icon)
                info = None if path else Gtk.IconTheme.get_default().lookup_icon(service.icon, 64, 0)
                path = path or (info and info.get_filename())
            paths[game_id] = path
        return paths[game_id]

    def select_badge_metrics(self, surface, media_width, media_height):
""")
    # The sidebar's sources with the same icons, drawn the same way (Lutris looked them up in the icon theme by name,
    # which lacks EA's, Battle.net's and Rockstar's: a plain box for those)
    edit("gui/widgets/sidebar.py", """class ServiceSidebarRow(SidebarRow):
    def __init__(self, service):
        super().__init__(service.id, "service", service.name, LutrisSidebar.get_sidebar_icon(service.icon))
""", """def _store_icon(service):
    \"\"\"lutris-overlay: store_icons. The covers' corner icon of a source, at the sidebar's size (None: Lutris's)\"\"\"
    try:
        import cairo
        from gi.repository import Gdk, GdkPixbuf
        from lutris.gui.widgets.cellrenderers import GridViewCellRendererImage
        from lutris.gui.widgets.utils import get_runtime_icon_path

        path = get_runtime_icon_path(service.icon)
        info = None if path else Gtk.IconTheme.get_default().lookup_icon(service.icon, 64, 0)
        path = path or (info and info.get_filename())
        if not path:
            return None
        scale, size = 2, Gtk.IconSize.lookup(Gtk.IconSize.MENU)[2]  # (drawn at twice the size: sharp on HiDPI)
        pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_size(path, size * scale, size * scale)
        icon = Gdk.cairo_surface_create_from_pixbuf(pixbuf, scale, None)
        mask = GridViewCellRendererImage._get_logo_mask(path, icon)
        out = cairo.ImageSurface(cairo.Format.ARGB32, pixbuf.get_width(), pixbuf.get_height())  # pylint:disable=no-member
        out.set_device_scale(scale, scale)
        cr = cairo.Context(out)  # pylint:disable=no-member
        cr.set_source_rgba(0.85, 0.85, 0.85, 0.9)
        cr.mask_surface(mask, 0, 0)
        return Gtk.Image.new_from_surface(out)
    except Exception:  # noqa: BLE001 (an icon, never worth an error)
        return None


class ServiceSidebarRow(SidebarRow):
    def __init__(self, service):
        super().__init__(service.id, "service", service.name,
                         _store_icon(service) or LutrisSidebar.get_sidebar_icon(service.icon))
""")


# Changes that can be turned off, by setting name, with their label in the Settings app. The others are always on: the
# Steam fix keeps installed games from being deleted, starting hidden only happens when asked (at login), and the
# start-up once is a plain fix
OPTIONAL = {
    "sections": "Installed and not installed games in two collapsible sections",
    "store_icons": "Each game's store icon on its cover",
    "rounded_covers": "Covers with rounded corners",
    "same_size_covers": "Every cover the same size (Steam's cropped at the edges)",
    "tall_covers": "Covers shaped like box art (2:3), not cut at the top and bottom",
    "hide_uninstalled": "\"Hide game from library\" for games that aren't installed too",
    "revive_installed": "Store games uninstalled in Lutris and installed again show as installed",
    "sync_all": "A button at the top right that syncs every store's library",
    "launchers_apart": "Store launchers only under Launchers in the sidebar, not among the games",
    "window_after_game": "The window doesn't come back when a game closes, and Lutris stays in its tray",
    "bnet_login": "Battle.net: sign in, and only the games on your account",
    "bnet_source": "Battle.net among Lutris's sources (Lutris leaves it off)",
    "rockstar_source": "Rockstar Games among Lutris's sources (Lutris has none)",
}
# For the dotfiles' own scripts, not offered in the Settings app: one that no longer fits is left out like an optional
# change (the script then makes do), not the whole build
PLUMBING = {
    "library_refresh": "An open Lutris shows lutris-library's changes at once (else once it restarts)",
}
if sys.argv[1:] == ["--list"]:
    print(json.dumps([{"id": k, "label": v} for k, v in OPTIONAL.items()]))
    sys.exit(0)
src, root = sys.argv[1:]
pkg = os.path.join(root, "lutris")
# By the account's home, as in ~/.local/share/caelestia-overlay/patch.py (DOTS_SETTINGS: another settings command, for
# tests/lutris-overlay.sh)
cli = os.environ.get("DOTS_SETTINGS") or f"{pwd.getpwuid(os.getuid()).pw_dir}/.local/bin/dots-settings"
try:
    values = json.loads(subprocess.run([cli, "values"], capture_output=True, text=True).stdout)
except (OSError, ValueError):
    values = {}
changes = [c for c in (sections, steam_placeholder, hide_uninstalled, launchers_apart, same_size_covers, start_hidden, startup_once,
                        vulkaninfo_once, rounded_covers, store_icons, window_after_game, reap_children, flathub_steam, library_refresh, sync_all, revive_installed,
                        bnet_not_installed, bnet_source, rockstar_source, bnet_login, source_page_ids, source_icons, tall_covers) if values.get(f"lutris.{c.__name__}") is not False]
while True:
    try:
        for change in changes:
            change()
        break
    except (Miss, FileNotFoundError) as e:  # (a folder a change copies a file into, gone)
        if change.__name__ not in OPTIONAL and change.__name__ not in PLUMBING:
            sys.exit(str(e))
        # Left out, and the copy made again without it: its edits so far would be half a change
        print(f"WARNING: {(OPTIONAL | PLUMBING)[change.__name__]}: {e}")
        changes.remove(change)
        shutil.rmtree(pkg)
        subprocess.run(["cp", "-as", src, pkg], check=True)
