"""Rockstar Games among Lutris's sources (lutris-overlay's rockstar_source; Lutris has none), like the patched Battle.net
one (bnet_login; the sign-in both share is signin.py): you sign in with Lutris's login window (Rockstar's own sign-in page) and it lists the games on your
account. Rockstar has no public API: the games are read from inside the signed-in site, the way its own account pages
read them (a bearer token from /auth/ping-bearer.json, then Social Club's account/googleTagManagerSetupData, whose
gamesOwned the site sends to its analytics). Each reload signs in again unseen; if that fails the last list is kept.
Installing a game adds it on the Rockstar Games Launcher's Wine prefix and opens the launcher, where you install and play
it; without the launcher, Lutris's install of the launcher opens first (it's under Launchers too)"""

import json
import os
import re
from gettext import gettext as _

from gi.repository import Gio

from lutris import settings
from lutris.config import LutrisConfig, write_game_config
from lutris.database import sql
from lutris.database.games import add_game, get_game_by_field
from lutris.services.service_game import ServiceGame
from lutris.services.service_media import ServiceMedia
from lutris.services.signin import SignInService, name_key
from lutris.util.log import logger

# id: (name, lutris.net slug, for its cover)
GAMES = {
    "gta5": ("Grand Theft Auto V", "grand-theft-auto-v"),
    "gta5e": ("Grand Theft Auto V Enhanced", "grand-theft-auto-v-enhanced"),
    "rdr2": ("Red Dead Redemption 2", "red-dead-redemption-2"),
    "rdr": ("Red Dead Redemption", "red-dead-redemption"),
    "rdo": ("Red Dead Online", "red-dead-online"),
    "gta4": ("Grand Theft Auto IV: The Complete Edition", "grand-theft-auto-iv"),
    "gta3de": ("Grand Theft Auto: III - The Definitive Edition", "grand-theft-auto-iii-the-definitive-edition"),
    "gtavcde": ("Grand Theft Auto: Vice City - The Definitive Edition", "grand-theft-auto-vice-city-the-definitive-edition"),
    "gtasade": ("Grand Theft Auto: San Andreas - The Definitive Edition",
                "grand-theft-auto-san-andreas-the-definitive-edition"),
    "lanoire": ("L.A. Noire", "la-noire"),
    "lanoirevr": ("L.A. Noire: The VR Case Files", "la-noire-the-vr-case-files"),
    "mp3": ("Max Payne 3", "max-payne-3"),
    "bully": ("Bully: Scholarship Edition", "bully-scholarship-edition"),
}
# The account's names for them (gamesOwned's), by name_key, where they aren't the id or the name above
ALIASES = {
    "gtav": ["gta5"], "grandtheftautov": ["gta5"], "gtavenhanced": ["gta5e"], "gtaonline": ["gta5"],
    "reddeadredemption2": ["rdr2"], "reddeadonline": ["rdo"], "reddeadredemption": ["rdr"],
    "gtaiv": ["gta4"], "grandtheftautoiv": ["gta4"], "gtaivcompleteedition": ["gta4"],
    "gtatrilogy": ["gta3de", "gtavcde", "gtasade"], "gtathetrilogy": ["gta3de", "gtavcde", "gtasade"],
    "gtatrilogythedefinitiveedition": ["gta3de", "gtavcde", "gtasade"],
    "lanoirethevrcasefiles": ["lanoirevr"], "lanoirevr": ["lanoirevr"], "maxpayne3": ["mp3"],
    "bullyscholarshipedition": ["bully"], "bully": ["bully"],
}


class RockstarCover(ServiceMedia):
    service = "rockstar"
    size = (176, 234)
    file_patterns = ["%s.jpg"]
    dest_path = os.path.join(settings.CACHE_DIR, "rockstar/coverart")
    api_field = "coverart"


class RockstarGame(ServiceGame):
    service = "rockstar"
    runner = "wine"

    @classmethod
    def create(cls, appid, name, slug):
        game = cls()
        game.appid, game.name, game.slug = appid, name, slug
        game.details = json.dumps({"id": appid, "name": name, "slug": slug,
                                   "coverart": "https://lutris.net/games/cover/%s.jpg" % slug})
        return game


class RockstarService(SignInService):
    id = "rockstar"
    name = _("Rockstar Games")
    label = "Rockstar"
    icon = "rockstar"
    runner = "wine"
    medias = {"coverart": RockstarCover}
    default_format = "coverart"
    client_installer = "rockstar-games-launcher"
    login_url = "https://signin.rockstargames.com/connect/authorize/rsg?returnUrl=%2Faccount"
    login_window_width = 480
    login_window_height = 720
    cookies_path = os.path.join(settings.CACHE_DIR, ".rockstar.auth")
    cache_path = None
    refresh_url = "https://www.rockstargames.com/account"
    owned_path = os.path.join(settings.CACHE_DIR, "rockstar-owned.json")  # the account's games (kept: not a cache)
    hand_over = "https://www.rockstargames.com/lutris-owned?"
    # On a signed-in www page: a bearer token (none: not signed in, to the sign-in page), then the account's data from
    # Social Club's API as the site's own account pages ask for it, handed over by opening hand_over (caught by _watch)
    _read_games = """(async () => {
        const done = d => window.location.replace("https://www.rockstargames.com/lutris-owned?d=" + encodeURIComponent(JSON.stringify(d)));
        try {
            const ping = await (await fetch("/auth/ping-bearer.json", {method: "POST", credentials: "include"})).json();
            if (!ping.bearerToken) { window.location.replace("%s"); return; }
            const r = await fetch("https://scapi.rockstargames.com/account/googleTagManagerSetupData", {headers: {
                "Authorization": "Bearer " + ping.bearerToken, "Content-Type": "application/json",
                "X-Requested-With": "XMLHttpRequest", "X-Lang": "en-US"}});
            const text = await r.text();
            if (!r.ok) throw new Error(r.status + " " + text.slice(0, 300));
            done({data: JSON.parse(text)});
        } catch (e) { done({error: String(e)}); }
    })();""" % login_url
    ALIASES = ALIASES  # (the module's)

    @staticmethod
    def owned_names(data):
        """gamesOwned from the account data, wherever it sits, as a list of names (a list, or one string of them)"""
        found = []

        def walk(value):
            if isinstance(value, dict):
                for key, item in value.items():
                    if key == "gamesOwned":
                        found.append(item)
                    else:
                        walk(item)
            elif isinstance(value, list):
                for item in value:
                    walk(item)

        walk(data)
        if not found:
            return None
        names = []
        for value in found:
            if isinstance(value, str):
                names += [n for n in re.split(r"[|,;]", value) if n.strip()]
            elif isinstance(value, list):
                names += [n if isinstance(n, str) else (n.get("name") or n.get("title") or n.get("id")) for n in value
                          if isinstance(n, (str, dict))]
        return [str(n).strip() for n in names if n]  # (an id may be a number)

    def _games_page(self, url):
        return url.startswith("https://www.rockstargames.com/") and "lutris-owned" not in url

    def _signin_page(self, url):
        return url.startswith("https://signin.rockstargames.com/signin")

    def _names(self, data):
        names = self.owned_names(data.get("data")) if "data" in data else None
        if names is None:
            logger.error("Rockstar: the games list couldn't be read: %s",
                         data.get("error") or "no gamesOwned in %s" % json.dumps(data.get("data"))[:500])
        return names

    def _by_key(self):
        return {name_key(i): [i] for i in GAMES} | {name_key(n): [i] for i, (n, _slug) in GAMES.items()}

    def _game(self, appid):
        return RockstarGame.create(appid, *GAMES[appid])

    def install(self, db_game, update=False):
        launcher = get_game_by_field(self.client_installer, "slug")
        if not launcher or not launcher["installed"]:
            Gio.Application.get_default().show_lutris_installer_window(game_slug=self.client_installer)
            return None
        installer_slug = db_game["slug"] + "-" + self.id
        existing = get_game_by_field(installer_slug, "installer_slug")
        if existing and existing["installed"]:
            return existing["id"]
        # shortcut: playing it opens the launcher (press Play there), not the game itself: the launcher's
        # -launchTitleInFolder needs each game's install folder, unchecked here; upgrade with a test on an owned game
        config = LutrisConfig(game_config_id=launcher["configpath"]).game_level
        game = dict(
            name=db_game["name"],
            runner=launcher["runner"],
            slug=db_game["slug"],
            directory=launcher["directory"],
            installed=1,
            installer_slug=installer_slug,
            configpath=write_game_config(installer_slug, config),
            service=self.id,
            service_id=db_game["appid"],
            platform="Windows",
        )
        if existing:  # uninstalled in Lutris earlier: that entry installed again (its playtime kept)
            sql.db_update(settings.DB_PATH, "games", game, {"id": existing["id"]})
            return existing["id"]
        return add_game(**game)  # (Lutris runs the id returned: the launcher opens)
