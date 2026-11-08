"""A source whose games are the ones on your account, read from inside its signed-in site (lutris-overlay: the patched
Battle.net, bnet_login, and Rockstar, rockstar.py; copied into the build with either). You sign in with Lutris's login
window; each reload signs in again the same way, unseen, so the list follows the account; if that fails, the last list
is kept. A service sets the site's pages (login_url, refresh_url, hand_over, _read_games: JavaScript that opens
hand_over?d=<JSON>), what they are (_games_page, _signin_page), _names (the games in that JSON), and its games
(ALIASES, GONE, _by_key, _game)"""

import json
import os
import re
import threading
import time
from gettext import gettext as _
from urllib.parse import parse_qs, urlparse

from gi.repository import GLib

from lutris.gui.dialogs import ErrorDialog
from lutris.gui.dialogs.webconnect_dialog import WebConnectDialog, WebKit2
from lutris.services.base import SERVICE_LOGIN, OnlineService
from lutris.util.log import logger


def name_key(name):
    return re.sub(r"[\W_]+", "", str(name or "").lower())


class SignInService(OnlineService):
    label = ""  # the site's name in messages
    owned_path = None  # the games on the account (kept: not a cache)
    hand_over = None
    _read_games = None
    refresh_url = None  # where an unseen sign-in starts (None: login_url)
    redirect_uris = []  # the games are handed over by _watch
    ALIASES = {}  # the account's names for games, by name_key, where _by_key's don't match
    GONE = set()  # games that left the store (still on the account): not Lutris's to list

    @property
    def credential_files(self):
        return [self.cookies_path, self.owned_path]

    def is_connected(self):
        return self.is_authenticated()

    def _games_page(self, url):
        """A signed-in page the games are read from"""
        raise NotImplementedError

    def _signin_page(self, url):
        """The site asking for the password (which nobody can type in an unseen view)"""
        raise NotImplementedError

    def _names(self, data):
        """The account's game names from the handed-over data, None if they aren't there"""
        raise NotImplementedError

    def _by_key(self):
        """Lutris's ids of each game, by name_key of its names"""
        raise NotImplementedError

    def _game(self, appid):
        raise NotImplementedError

    def _watch(self, view, finished, unseen=False):
        """Read the games once the view is on a signed-in page: finished(names), or finished(None) if they couldn't be
        read (unseen: or the site asks for the password). Called once"""
        called = []

        def finish(names):
            if not called:
                called.append(True)
                finished(names)

        def on_load(view, event):
            if event != WebKit2.LoadEvent.FINISHED:
                return
            url = view.get_uri() or ""
            logger.info("%s sign-in page: %s", self.label, url.split("?")[0])  # where it stopped, if it does
            if unseen and self._signin_page(url):
                finish(None)
            elif self._games_page(url):
                view.run_javascript(self._read_games, None, None)

        def on_request(view, resource, request):
            url = request.get_uri() or ""
            if url.startswith(self.hand_over):
                try:
                    names = self._names(json.loads((parse_qs(urlparse(url).query).get("d") or ["{}"])[0]))
                except Exception:  # noqa: BLE001 (not left on the hand-over page, or an unseen reload waiting 45 s)
                    logger.exception("%s: the handed-over games couldn't be read", self.label)
                    names = None
                finish(names)

        def on_failed(view, event, url, error):
            if unseen:  # offline, or the site down: not 45 s waiting
                finish(None)
            return False

        view.connect("load-changed", on_load)
        view.connect("resource-load-started", on_request)
        view.connect("load-failed", on_failed)
        return finish

    def _save(self, names):
        # Whole or not at all: a half-written list would be read as none
        with open(self.owned_path + ".tmp", "w", encoding="utf-8") as f:
            json.dump(names, f)
        os.replace(self.owned_path + ".tmp", self.owned_path)

    def login(self, parent=None):
        # Lutris's login window, without its "install the launcher first" step (signing in doesn't need it)
        dialog = WebConnectDialog(self, parent)

        def finished(names):
            self.is_login_in_progress = False
            dialog.destroy()
            if names is None:
                ErrorDialog(_("Signed in, but your %s games couldn't be read. Try connecting again.") % self.label,
                            parent=parent)
                return
            self._save(names)
            SERVICE_LOGIN.fire(self)

        self._watch(dialog.webview, finished)
        dialog.run()

    def _refresh(self, timeout=45):
        """Sign in again unseen and read the games (from a reload's worker thread); None if that didn't work"""
        if threading.current_thread() is threading.main_thread():
            return None
        done, result, views = threading.Event(), [], []

        def start():
            context = WebKit2.WebContext.new()
            WebKit2.CookieManager.set_persistent_storage(context.get_cookie_manager(), self.cookies_path,
                                                         WebKit2.CookiePersistentStorage(0))
            view = WebKit2.WebView.new_with_context(context)  # never shown (an offscreen window crashed: no GL)
            view.get_settings().set_user_agent(self.login_user_agent)
            views.append(view)  # kept until it's done

            def finished(names):
                result.append(names)
                views.remove(view)
                view.try_close()
                done.set()

            finish = self._watch(view, finished, unseen=True)
            view.load_uri(self.refresh_url or self.login_url)
            GLib.timeout_add_seconds(timeout, lambda: finish(None) or False)
            return False

        GLib.idle_add(start)
        done.wait(timeout + 10)
        return result[0] if result else None

    def load(self):
        # Not again right after signing in (the reload that follows it)
        try:
            fresh = time.time() - os.path.getmtime(self.owned_path) < 300
        except OSError:
            fresh = False
        names = None if fresh else self._refresh()
        if names is not None:
            self._save(names)
        else:
            if not fresh:
                logger.warning("%s: couldn't sign in again unseen, the last games list is kept: disconnect and connect"
                               " to update it", self.label)
            try:
                with open(self.owned_path, encoding="utf-8") as f:
                    names = [str(n) for n in json.load(f) if n is not None]  # (an odd entry: not sorted with the rest)
            except (OSError, TypeError, ValueError):
                return []
        by_key = self._by_key()
        owned, unknown = {}, []
        for name in names:
            key = name_key(name)
            ids = self.ALIASES.get(key) or by_key.get(key) or []
            for i in ids:
                owned[i] = True
            if not ids and key not in self.GONE:
                unknown.append(name)
        if unknown:
            logger.warning("%s games Lutris doesn't know: %s", self.label, ", ".join(sorted(set(unknown))))
        games = [self._game(i) for i in owned]
        for game in games:
            game.save()
        return games
