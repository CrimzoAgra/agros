"""The grid split into collapsible "Installed" and "Not installed" sections, each a grid of its own over the same
store (dotfiles: ~/.local/share/lutris-overlay). The window sees one view: a path here is (section, path in it)"""

from gettext import gettext as _
from types import SimpleNamespace

from gi.repository import GLib, Gtk

from lutris import settings
from lutris.gui.views import COL_INSTALLED
from lutris.gui.views.base import GameView
from lutris.gui.views.grid import GameGridView


class SectionedGridView(Gtk.Viewport):
    __gsignals__ = GameView.__gsignals__

    def __init__(self, store, hide_text=False):
        super().__init__(shadow_type=Gtk.ShadowType.NONE)
        # Outside a scrolled window of its own a grid doesn't wrap: as many columns as fit the width, set on resize
        self._width = 0
        self.connect("size-allocate", self.on_size_allocate)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, visible=True)
        self.add(box)
        self.game_store = store
        self.service = store.service
        self._syncing = False
        self.sections = []
        for installed, title in ((True, _("Installed")), (False, _("Not installed"))):
            key = "section_%s_expanded" % ("installed" if installed else "uninstalled")
            expander = Gtk.Expander(expanded=settings.read_bool_setting(key, True), margin_start=12, margin_top=6)
            expander.connect("notify::expanded", lambda e, _p, k=key: settings.write_setting(k, e.get_expanded()))
            view = GameGridView(self._filtered(store, installed), hide_text=hide_text)
            view.connect("game-selected", self.on_section_selected)
            view.connect("game-activated", lambda _v, game_id: self.emit("game-activated", game_id))
            expander.add(view)
            box.pack_start(expander, False, False, 0)
            self.sections.append(SimpleNamespace(installed=installed, title=title, expander=expander, view=view))
        self._update_titles()

    @staticmethod
    def _filtered(store, installed):
        """What GameGridView needs of a GameStore, its list cut to installed or uninstalled games; a game moves
        section when it's installed or removed (the filter rechecks changed rows)"""
        model = store.store.filter_new()
        model.set_visible_func(lambda m, it, _data: bool(m.get_value(it, COL_INSTALLED)) == installed)
        return SimpleNamespace(store=model, service=store.service, service_media=store.service_media)

    def _update_titles(self, *_args):
        for s in self.sections:
            count = s.view.get_model().iter_n_children(None)
            s.expander.set_label("%s (%d)" % (s.title, count))
            s.expander.set_visible(count > 0)

    def on_size_allocate(self, _widget, allocation):
        if allocation.width != self._width:
            self._width = allocation.width
            GLib.idle_add(self._set_columns)  # a resize asked for during one is dropped

    def _set_columns(self):
        for s in self.sections:
            view = s.view
            media_width, media_height = self.game_store.service_media.size
            padding = 2 * view.get_item_padding()
            spacing = view.get_column_spacing()
            usable = self._width - s.expander.get_margin_start() - 2 * view.get_margin() + spacing
            # The nearest number of columns, the covers a little bigger or smaller to fill the row: no gap on the right
            columns = max(1, round(usable / (max(media_width, view.min_width) + padding + spacing)))
            width = max(view.min_width, usable // columns - spacing - padding)
            if view.image_renderer:
                view.image_renderer.set_expected_size(width, round(width * media_height / media_width))
            if view.text_renderer:
                view.text_renderer.set_width(width)
            if view.get_columns() != columns:
                view.set_columns(columns)
            view.queue_resize()
        return False

    def set_game_store(self, store):
        self.game_store = store
        self.service = store.service
        for s in self.sections:
            filtered = self._filtered(store, s.installed)
            s.view.set_game_store(filtered)
            filtered.store.connect("row-inserted", self._update_titles)
            filtered.store.connect("row-deleted", self._update_titles)
        self._update_titles()
        self._set_columns()  # the cover size may have changed (zoom)

    def on_section_selected(self, view, _items):
        # One selection across both sections: selecting in one clears the other
        if self._syncing:
            return
        if view.get_selected():
            self._syncing = True
            for s in self.sections:
                if s.view is not view:
                    s.view.unselect_all()
            self._syncing = False
        self.emit("game-selected", self.get_selected())

    @property
    def show_badges(self):
        return self.sections[0].view.show_badges

    @show_badges.setter
    def show_badges(self, value):
        for s in self.sections:
            s.view.show_badges = value

    def _first_open_view(self):
        for s in self.sections:
            if s.expander.get_visible() and s.expander.get_expanded():
                return s.view
        return self.sections[0].view

    def get_selected(self):
        return [(i, path) for i, s in enumerate(self.sections) for path in s.view.get_selected()]

    def set_selected(self, paths, scroll_into_view=False):
        paths = list(paths)
        for i, s in enumerate(self.sections):
            s.view.set_selected([p for j, p in paths if j == i], scroll_into_view)

    def get_game_id_for_path(self, path):
        return self.sections[path[0]].view.get_game_id_for_path(path[1])

    def get_path_for_game_id(self, game_id):
        for i, s in enumerate(self.sections):
            path = s.view.get_path_for_game_id(game_id)
            if path:
                return i, path
        return None

    # The search box's Down key: into the first open section
    def select_path(self, path):
        self._first_open_view().select_path(path)

    def set_cursor(self, path, cell, start_editing):
        self._first_open_view().set_cursor(path, cell, start_editing)

    def grab_focus(self):
        self._first_open_view().grab_focus()
