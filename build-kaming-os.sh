#!/usr/bin/env bash
# Kaming OS 1.1 - сборщик ISO (Debian 13 "trixie" + XFCE в стиле macOS)
# Внутри: свой браузер, свои настройки (обои, темы, док, языки), Wine для .exe.
# Запускается GitHub Actions (build.yml) или вручную на Debian/Ubuntu (нужен root).
set -euo pipefail

if [ "$EUID" -ne 0 ]; then exec sudo bash "$0" "$@"; fi

echo "==> Установка инструментов сборки"
apt-get update
apt-get install -y live-build debootstrap xorriso squashfs-tools mtools dosfstools \
  grub-pc-bin grub-efi-amd64-bin imagemagick curl ca-certificates

WORK="$(pwd)/kaming-build"
mkdir -p "$WORK"
cd "$WORK"
lb clean --purge >/dev/null 2>&1 || true

echo "==> Конфигурация live-build"
lb config \
  --distribution trixie \
  --architectures amd64 \
  --archive-areas "main contrib non-free non-free-firmware" \
  --debian-installer none \
  --iso-application "Kaming OS" \
  --iso-publisher "Kaming" \
  --iso-volume "KAMING_OS" \
  --bootappend-live "boot=live components quiet username=kaming hostname=kaming-os" \
  --memtest none

mkdir -p config/package-lists config/hooks/live

mkdir -p "$(dirname "config/includes.chroot/usr/local/bin/kaming-browser")"
cat > "config/includes.chroot/usr/local/bin/kaming-browser" <<'KAMING_EOF_0'
#!/usr/bin/env python3
"""Kaming Browser: лёгкий браузер на WebKit (движок Safari) с вкладками, закладками и приватным режимом."""
import html
import json
import os
import subprocess
import sys
import time
import urllib.parse

# В виртуалках аппаратный композитинг WebKit часто даёт пустые страницы и лаги
os.environ.setdefault("WEBKIT_DISABLE_COMPOSITING_MODE", "1")
os.environ.setdefault("WEBKIT_DISABLE_DMABUF_RENDERER", "1")

sys.path.insert(0, "/usr/local/lib/kaming")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("WebKit2", "4.1")
from gi.repository import Gdk, GLib, Gtk, WebKit2  # noqa: E402

from kaming_i18n import t  # noqa: E402

CFG = os.path.expanduser("~/.config/kaming/browser.json")
ENGINES = {
    "DuckDuckGo": "https://duckduckgo.com/",
    "Google": "https://www.google.com/search",
    "Bing": "https://www.bing.com/search",
    "Ecosia": "https://www.ecosia.org/search",
}
DEFAULT = {
    "engine": "DuckDuckGo",
    "bookmarks": [
        {"title": "Wikipedia", "url": "https://www.wikipedia.org"},
        {"title": "YouTube", "url": "https://www.youtube.com"},
        {"title": "GitHub", "url": "https://github.com"},
        {"title": "OpenStreetMap", "url": "https://www.openstreetmap.org"},
    ],
    "history": [],
}


def load_cfg():
    try:
        with open(CFG, encoding="utf-8") as f:
            data = json.load(f)
        for k, v in DEFAULT.items():
            data.setdefault(k, v)
        return data
    except Exception:
        return json.loads(json.dumps(DEFAULT))


def save_cfg():
    try:
        os.makedirs(os.path.dirname(CFG), exist_ok=True)
        with open(CFG, "w", encoding="utf-8") as f:
            json.dump(CONFIG, f, ensure_ascii=False, indent=1)
    except Exception:
        pass


CONFIG = load_cfg()
WINDOWS = []


def is_virtual():
    try:
        r = subprocess.run(["systemd-detect-virt"], capture_output=True, text=True, timeout=3)
        return r.stdout.strip() not in ("", "none")
    except Exception:
        return False


VIRTUAL = is_virtual()


def to_url(text):
    text = text.strip()
    if not text:
        return None
    if text.startswith(("http://", "https://", "file://", "kaming://", "about:")):
        return text
    if " " not in text and ("." in text or text.startswith("localhost")):
        return "https://" + text
    base = ENGINES.get(CONFIG["engine"], ENGINES["DuckDuckGo"])
    return base + "?q=" + urllib.parse.quote_plus(text)


def start_page_html():
    esc = html.escape
    action = ENGINES.get(CONFIG["engine"], ENGINES["DuckDuckGo"])
    tiles = ""
    for b in CONFIG["bookmarks"][:12]:
        title = b.get("title") or b["url"]
        letter = esc((title.strip() or "?")[0].upper())
        tiles += (
            f'<a class="tile" href="{esc(b["url"], quote=True)}"><div class="ic">{letter}</div>'
            f'<span>{esc(title[:18])}</span></a>'
        )
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
:root{{--bg1:#4facfe;--bg2:#8e44ad;--card:rgba(255,255,255,.22);--fg:#fff}}
*{{box-sizing:border-box}}
body{{margin:0;min-height:100vh;font-family:Inter,system-ui,sans-serif;color:var(--fg);
background:linear-gradient(135deg,var(--bg1),var(--bg2));display:flex;flex-direction:column;align-items:center;padding-top:9vh}}
#clock{{font-size:76px;font-weight:200;letter-spacing:-2px}}
#date{{opacity:.85;margin-bottom:34px;font-size:18px}}
form{{width:min(560px,86vw)}}
input{{width:100%;padding:14px 20px;border-radius:14px;border:none;outline:none;font-size:17px;
background:var(--card);color:var(--fg);backdrop-filter:blur(8px)}}
input::placeholder{{color:rgba(255,255,255,.8)}}
h3{{margin:44px 0 14px;font-weight:500;opacity:.9}}
.grid{{display:flex;gap:22px;flex-wrap:wrap;justify-content:center;max-width:760px}}
.tile{{width:92px;text-align:center;color:var(--fg);text-decoration:none;font-size:13px}}
.ic{{width:64px;height:64px;margin:0 auto 8px;border-radius:16px;background:var(--card);
display:flex;align-items:center;justify-content:center;font-size:28px;font-weight:600}}
.tile:hover .ic{{background:rgba(255,255,255,.38)}}
</style></head><body>
<div id="clock"></div><div id="date"></div>
<form action="{esc(action, quote=True)}" method="get"><input name="q" autofocus autocomplete="off" placeholder="{esc(t('start_search'))}"></form>
<h3>{esc(t('favorites'))}</h3><div class="grid">{tiles}</div>
<script>
function tick(){{var d=new Date();
document.getElementById('clock').textContent=d.toLocaleTimeString([], {{hour:'2-digit',minute:'2-digit'}});
document.getElementById('date').textContent=d.toLocaleDateString([], {{weekday:'long',day:'numeric',month:'long'}});}}
tick();setInterval(tick,10000);
</script></body></html>"""


def error_page_html(uri, msg):
    esc = html.escape
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
body{{font-family:Inter,system-ui,sans-serif;display:flex;min-height:90vh;align-items:center;justify-content:center;
background:#f5f5f7;color:#1d1d1f}}
@media(prefers-color-scheme:dark){{body{{background:#1c1c1e;color:#f5f5f7}}}}
div{{text-align:center;max-width:560px;padding:20px}}h1{{font-weight:600}}p{{opacity:.7;word-break:break-all}}
</style></head><body><div><h1>{esc(t('load_failed'))}</h1><p>{esc(uri)}</p>
<p>{esc(t('check_connection'))}</p><p>{esc(msg)}</p></div></body></html>"""


# ---------- загрузки ----------
def unique_path(path):
    base, ext = os.path.splitext(path)
    n = 1
    while os.path.exists(path):
        path = f"{base} ({n}){ext}"
        n += 1
    return path


def on_decide_destination(download, suggested):
    folder = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD) or os.path.expanduser("~/Downloads")
    os.makedirs(folder, exist_ok=True)
    name = os.path.basename(suggested or "download") or "download"
    path = unique_path(os.path.join(folder, name))
    download.set_destination(GLib.filename_to_uri(path, None))
    return True


def on_download_finished(download):
    dest = download.get_destination() or ""
    name = os.path.basename(urllib.parse.unquote(dest))
    try:
        subprocess.Popen(["notify-send", "Kaming Browser", f"{t('downloaded')}: {name}"])
    except Exception:
        pass


def on_download_started(ctx, download):
    download.connect("decide-destination", on_decide_destination)
    download.connect("finished", on_download_finished)


_PRIVATE_CTX = None


def get_context(private):
    global _PRIVATE_CTX
    if private:
        if _PRIVATE_CTX is None:
            _PRIVATE_CTX = WebKit2.WebContext.new_ephemeral()
            _PRIVATE_CTX.connect("download-started", on_download_started)
        return _PRIVATE_CTX
    return WebKit2.WebContext.get_default()


# ---------- окно ----------
class BrowserWindow(Gtk.Window):
    def __init__(self, private=False):
        super().__init__(title=t("browser"))
        self.private = private
        self.ctx = get_context(private)
        self.set_default_size(1200, 780)
        self.set_icon_name("web-browser")
        self.set_wmclass("kaming-browser", "Kaming Browser")

        # --- заголовок в стиле Safari ---
        hb = Gtk.HeaderBar()
        hb.set_show_close_button(True)
        self.set_titlebar(hb)

        self.btn_back = self._icon_button("go-previous-symbolic", lambda *_: self.cur_view() and self.cur_view().go_back())
        self.btn_fwd = self._icon_button("go-next-symbolic", lambda *_: self.cur_view() and self.cur_view().go_forward())
        navbox = Gtk.Box(spacing=0)
        navbox.get_style_context().add_class("linked")
        navbox.pack_start(self.btn_back, False, False, 0)
        navbox.pack_start(self.btn_fwd, False, False, 0)
        hb.pack_start(navbox)

        self.entry = Gtk.Entry()
        self.entry.set_placeholder_text(t("search_or_url"))
        self.entry.set_width_chars(54)
        self.entry.set_alignment(0.5)
        self.entry.set_icon_from_icon_name(Gtk.EntryIconPosition.PRIMARY, "system-search-symbolic")
        self.entry.connect("activate", self.on_entry_activate)
        self.entry.connect("focus-in-event", lambda e, _: GLib.idle_add(e.select_region, 0, -1))
        hb.set_custom_title(self.entry)

        self.btn_menu = self._icon_button("open-menu-symbolic", self.on_menu)
        self.btn_new = self._icon_button("tab-new-symbolic", lambda *_: self.new_tab(None, focus_entry=True))
        self.btn_star = self._icon_button("non-starred-symbolic", self.on_star)
        self.btn_reload = self._icon_button("view-refresh-symbolic", self.on_reload)
        for b in (self.btn_menu, self.btn_new, self.btn_star, self.btn_reload):
            hb.pack_end(b)

        if private:
            hb.set_subtitle(t("private"))
            hb.set_title(t("browser"))

        # --- содержимое ---
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(vbox)

        self.searchbar = Gtk.SearchBar()
        self.find_entry = Gtk.SearchEntry()
        self.find_entry.set_width_chars(36)
        self.searchbar.add(self.find_entry)
        self.searchbar.connect_entry(self.find_entry)
        self.find_entry.connect("search-changed", self.on_find_changed)
        self.find_entry.connect("activate", self.on_find_next)
        self.find_entry.connect("stop-search", self.on_find_stop)
        vbox.pack_start(self.searchbar, False, False, 0)

        self.notebook = Gtk.Notebook()
        self.notebook.set_scrollable(True)
        self.notebook.set_show_border(False)
        self.notebook.connect("switch-page", self.on_switch_page)
        vbox.pack_start(self.notebook, True, True, 0)

        self.connect("key-press-event", self.on_key)
        self.connect("destroy", self.on_destroy)
        WINDOWS.append(self)

    # ----- вспомогательное -----
    def _icon_button(self, icon, cb):
        b = Gtk.Button.new_from_icon_name(icon, Gtk.IconSize.BUTTON)
        b.set_relief(Gtk.ReliefStyle.NONE)
        b.set_can_focus(False)
        b.connect("clicked", cb)
        return b

    def cur_view(self):
        n = self.notebook.get_current_page()
        return self.notebook.get_nth_page(n) if n >= 0 else None

    def on_destroy(self, *_):
        if self in WINDOWS:
            WINDOWS.remove(self)
        save_cfg()
        if not WINDOWS:
            Gtk.main_quit()

    # ----- вкладки -----
    def new_tab(self, url=None, related=None, focus_entry=False):
        if related is not None:
            view = WebKit2.WebView.new_with_related_view(related)
        else:
            view = WebKit2.WebView.new_with_context(self.ctx)
        st = view.get_settings()
        st.set_enable_smooth_scrolling(True)
        st.set_enable_developer_extras(True)
        st.set_javascript_can_open_windows_automatically(False)
        if VIRTUAL:
            st.set_hardware_acceleration_policy(WebKit2.HardwareAccelerationPolicy.NEVER)
        view.connect("notify::title", self.on_title)
        view.connect("notify::uri", self.on_uri)
        view.connect("notify::estimated-load-progress", self.on_progress)
        view.connect("load-changed", self.on_load_changed)
        view.connect("load-failed", self.on_load_failed)
        view.connect("create", self.on_create)
        view.show()

        label = Gtk.Label(label=t("new_tab"))
        label.set_ellipsize(3)  # END
        label.set_width_chars(16)
        label.set_max_width_chars(20)
        close = Gtk.Button.new_from_icon_name("window-close-symbolic", Gtk.IconSize.MENU)
        close.set_relief(Gtk.ReliefStyle.NONE)
        close.set_tooltip_text(t("close_tab"))
        close.connect("clicked", lambda *_: self.close_tab(view))
        box = Gtk.Box(spacing=4)
        box.pack_start(label, True, True, 0)
        box.pack_start(close, False, False, 0)
        box.show_all()
        view._tab_label = label

        idx = self.notebook.append_page(view, box)
        self.notebook.set_tab_reorderable(view, True)
        self.notebook.set_current_page(idx)
        self.notebook.set_show_tabs(self.notebook.get_n_pages() > 1)
        if related is None:
            self.load(view, url or "kaming://start")
        if focus_entry:
            self.entry.grab_focus()
        return view

    def close_tab(self, view):
        n = self.notebook.page_num(view)
        if n >= 0:
            self.notebook.remove_page(n)
        if self.notebook.get_n_pages() == 0:
            self.destroy()
        else:
            self.notebook.set_show_tabs(self.notebook.get_n_pages() > 1)

    def load(self, view, url):
        if url.startswith("kaming://"):
            view.load_html(start_page_html(), "kaming://start")
        else:
            view.load_uri(url)

    # ----- сигналы WebView -----
    def on_create(self, view, nav_action):
        new = self.new_tab(related=view)
        return new

    def on_title(self, view, _p):
        title = view.get_title() or ""
        uri = view.get_uri() or ""
        if not title:
            title = t("new_tab") if uri.startswith("kaming://") else uri
        view._tab_label.set_text(title)
        view._tab_label.set_tooltip_text(title)
        if view is self.cur_view():
            self.set_title(f"{title} — {t('browser')}" if title else t("browser"))

    def on_uri(self, view, _p):
        if view is self.cur_view():
            self.update_chrome(view)

    def on_progress(self, view, _p):
        if view is self.cur_view():
            p = view.get_estimated_load_progress()
            self.entry.set_progress_fraction(p if p < 1.0 else 0.0)

    def on_load_changed(self, view, event):
        if event == WebKit2.LoadEvent.FINISHED:
            uri = view.get_uri() or ""
            if not self.private and uri and not uri.startswith(("kaming://", "about:")):
                hist = CONFIG["history"]
                hist.append({"title": view.get_title() or uri, "url": uri, "t": int(time.time())})
                del hist[:-500]
        if view is self.cur_view():
            self.update_chrome(view)

    def on_load_failed(self, view, event, uri, error):
        view.load_alternate_html(error_page_html(uri, error.message), uri, uri)
        return True

    def on_switch_page(self, nb, page, num):
        GLib.idle_add(self.update_chrome, page)

    def update_chrome(self, view):
        if view is None:
            return False
        uri = view.get_uri() or ""
        shown = "" if uri.startswith("kaming://") else uri
        if not self.entry.has_focus():
            self.entry.set_text(shown)
        icon = "channel-secure-symbolic" if uri.startswith("https://") else "system-search-symbolic"
        self.entry.set_icon_from_icon_name(Gtk.EntryIconPosition.PRIMARY, icon)
        self.btn_back.set_sensitive(view.can_go_back())
        self.btn_fwd.set_sensitive(view.can_go_forward())
        starred = any(b["url"] == uri for b in CONFIG["bookmarks"])
        img = Gtk.Image.new_from_icon_name("starred-symbolic" if starred else "non-starred-symbolic", Gtk.IconSize.BUTTON)
        self.btn_star.set_image(img)
        loading = view.is_loading()
        rimg = Gtk.Image.new_from_icon_name("process-stop-symbolic" if loading else "view-refresh-symbolic", Gtk.IconSize.BUTTON)
        self.btn_reload.set_image(rimg)
        title = view.get_title() or ""
        self.set_title(f"{title} — {t('browser')}" if title else t("browser"))
        return False

    # ----- действия -----
    def on_entry_activate(self, entry):
        url = to_url(entry.get_text())
        view = self.cur_view()
        if url and view:
            self.load(view, url)
            view.grab_focus()

    def on_reload(self, *_):
        v = self.cur_view()
        if not v:
            return
        if v.is_loading():
            v.stop_loading()
        else:
            v.reload()

    def on_star(self, *_):
        v = self.cur_view()
        uri = v.get_uri() if v else None
        if not uri or uri.startswith("kaming://"):
            return
        marks = CONFIG["bookmarks"]
        found = [b for b in marks if b["url"] == uri]
        if found:
            marks.remove(found[0])
        else:
            marks.append({"title": v.get_title() or uri, "url": uri})
        save_cfg()
        self.update_chrome(v)

    def zoom(self, delta):
        v = self.cur_view()
        if not v:
            return
        if delta == 0:
            v.set_zoom_level(1.0)
        else:
            v.set_zoom_level(max(0.3, min(5.0, v.get_zoom_level() + delta)))

    def open_find(self):
        self.searchbar.set_search_mode(True)
        self.find_entry.grab_focus()

    def on_find_changed(self, entry):
        v = self.cur_view()
        if not v:
            return
        fc = v.get_find_controller()
        text = entry.get_text()
        if text:
            fc.search(text, WebKit2.FindOptions.CASE_INSENSITIVE | WebKit2.FindOptions.WRAP_AROUND, 100)
        else:
            fc.search_finish()

    def on_find_next(self, *_):
        v = self.cur_view()
        if v:
            v.get_find_controller().search_next()

    def on_find_stop(self, *_):
        v = self.cur_view()
        if v:
            v.get_find_controller().search_finish()
        self.searchbar.set_search_mode(False)

    def on_key(self, widget, ev):
        ctrl = ev.state & Gdk.ModifierType.CONTROL_MASK
        shift = ev.state & Gdk.ModifierType.SHIFT_MASK
        alt = ev.state & Gdk.ModifierType.MOD1_MASK
        k = Gdk.keyval_name(ev.keyval) or ""
        v = self.cur_view()
        if ctrl and not shift:
            if k in ("t", "T"):
                self.new_tab(None, focus_entry=True)
            elif k in ("w", "W"):
                v and self.close_tab(v)
            elif k in ("l", "L"):
                self.entry.grab_focus()
            elif k in ("r", "R"):
                v and v.reload()
            elif k in ("f", "F"):
                self.open_find()
            elif k in ("d", "D"):
                self.on_star()
            elif k in ("n", "N"):
                open_window(False)
            elif k in ("plus", "equal", "KP_Add"):
                self.zoom(0.1)
            elif k in ("minus", "KP_Subtract"):
                self.zoom(-0.1)
            elif k in ("0", "KP_0"):
                self.zoom(0)
            elif k == "Tab":
                n = self.notebook.get_n_pages()
                self.notebook.set_current_page((self.notebook.get_current_page() + 1) % n)
            else:
                return False
            return True
        if ctrl and shift and k in ("n", "N"):
            open_window(True)
            return True
        if alt and k == "Left":
            v and v.go_back()
            return True
        if alt and k == "Right":
            v and v.go_forward()
            return True
        if k == "F5":
            v and v.reload()
            return True
        if k == "Escape" and self.searchbar.get_search_mode():
            self.on_find_stop()
            return True
        return False

    # ----- меню -----
    def on_menu(self, btn):
        menu = Gtk.Menu()

        def item(label, cb, parent=menu):
            mi = Gtk.MenuItem(label=label)
            mi.connect("activate", lambda *_: cb())
            parent.append(mi)
            return mi

        item(t("new_window"), lambda: open_window(False))
        item(t("private_window"), lambda: open_window(True))
        menu.append(Gtk.SeparatorMenuItem())

        # закладки
        bm = Gtk.MenuItem(label=t("bookmarks"))
        sub = Gtk.Menu()
        for b in CONFIG["bookmarks"][:30]:
            item((b.get("title") or b["url"])[:50], lambda u=b["url"]: self.new_tab(u), sub)
        if not CONFIG["bookmarks"]:
            e = Gtk.MenuItem(label=t("empty"))
            e.set_sensitive(False)
            sub.append(e)
        bm.set_submenu(sub)
        menu.append(bm)

        # история
        hm = Gtk.MenuItem(label=t("history"))
        sub = Gtk.Menu()
        for h in reversed(CONFIG["history"][-20:]):
            item((h.get("title") or h["url"])[:50], lambda u=h["url"]: self.new_tab(u), sub)
        if not CONFIG["history"]:
            e = Gtk.MenuItem(label=t("empty"))
            e.set_sensitive(False)
            sub.append(e)
        else:
            sub.append(Gtk.SeparatorMenuItem())

            def clear():
                CONFIG["history"].clear()
                save_cfg()

            item(t("clear_history"), clear, sub)
        hm.set_submenu(sub)
        menu.append(hm)
        menu.append(Gtk.SeparatorMenuItem())

        item(t("find"), self.open_find)
        item(t("zoom_in"), lambda: self.zoom(0.1))
        item(t("zoom_out"), lambda: self.zoom(-0.1))
        item(t("zoom_reset"), lambda: self.zoom(0))
        menu.append(Gtk.SeparatorMenuItem())

        # поисковая система
        em = Gtk.MenuItem(label=t("search_engine"))
        sub = Gtk.Menu()
        group = None
        for name in ENGINES:
            ri = Gtk.RadioMenuItem.new_with_label_from_widget(group, name)
            group = group or ri
            ri.set_active(name == CONFIG["engine"])

            def chosen(w, n=name):
                if w.get_active():
                    CONFIG["engine"] = n
                    save_cfg()

            ri.connect("toggled", chosen)
            sub.append(ri)
        em.set_submenu(sub)
        menu.append(em)

        def open_dl():
            d = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD) or os.path.expanduser("~/Downloads")
            os.makedirs(d, exist_ok=True)
            subprocess.Popen(["xdg-open", d])

        item(t("open_downloads"), open_dl)
        menu.show_all()
        menu.popup_at_widget(btn, Gdk.Gravity.SOUTH_EAST, Gdk.Gravity.NORTH_EAST, None)


def open_window(private=False, urls=None):
    w = BrowserWindow(private)
    w.show_all()
    if urls:
        for u in urls:
            w.new_tab(to_url(u))
    else:
        w.new_tab(None, focus_entry=True)
    w.searchbar.set_search_mode(False)
    return w


def main():
    args = sys.argv[1:]
    private = "--private" in args
    urls = [a for a in args if not a.startswith("--")]
    ctx = WebKit2.WebContext.get_default()
    ctx.connect("download-started", on_download_started)
    css = Gtk.CssProvider()
    css.load_from_data(b"entry { border-radius: 9px; min-height: 26px; }")
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    open_window(private, urls or None)
    Gtk.main()


if __name__ == "__main__":
    main()
KAMING_EOF_0
chmod 755 "config/includes.chroot/usr/local/bin/kaming-browser"

mkdir -p "$(dirname "config/includes.chroot/usr/local/bin/kaming-settings")"
cat > "config/includes.chroot/usr/local/bin/kaming-settings" <<'KAMING_EOF_1'
#!/usr/bin/env python3
"""Kaming Settings: оформление, обои, док, экран, язык, клавиатура, Windows-программы, производительность."""
import glob
import os
import platform
import subprocess
import sys

sys.path.insert(0, "/usr/local/lib/kaming")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import GdkPixbuf, GLib, Gtk  # noqa: E402

import kaming_i18n as I  # noqa: E402
from kaming_i18n import t  # noqa: E402

WALL_DIR = "/usr/share/backgrounds/kaming"
DOCK_PATH = "net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/dock1/"
LAYOUTS = [("us", "English (US)"), ("ru", "Русский"), ("ua", "Українська"), ("pl", "Polski"),
           ("cn", "中文 / Chinese"), ("de", "Deutsch"), ("fr", "Français"), ("es", "Español")]


def run(cmd, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=kw.pop("timeout", 20), **kw)
    except Exception as e:  # noqa: BLE001
        class R:  # заглушка результата
            stdout = ""
            stderr = str(e)
            returncode = 1
        return R()


def spawn(cmd):
    try:
        subprocess.Popen(cmd)
    except Exception:
        pass


def xf(channel, prop, typ, val):
    if typ == "bool":
        val = "true" if val else "false"
    run(["xfconf-query", "-c", channel, "-p", prop, "--create", "-t", typ, "-s", str(val)])


def xf_get(channel, prop):
    return run(["xfconf-query", "-c", channel, "-p", prop]).stdout.strip()


def gset(key, val):
    run(["gsettings", "set", DOCK_PATH, key, str(val)])


def gget(key):
    return run(["gsettings", "get", DOCK_PATH, key]).stdout.strip().strip("'")


# ---------- действия ----------
def set_theme(dark):
    name = "WhiteSur-Dark" if dark else "WhiteSur-Light"
    xf("xsettings", "/Net/ThemeName", "string", name)
    xf("xsettings", "/Net/IconThemeName", "string", "WhiteSur-dark" if dark else "WhiteSur")
    xf("xfwm4", "/general/theme", "string", name)


def set_wallpaper(path):
    props = run(["xfconf-query", "-c", "xfce4-desktop", "-l"]).stdout.split()
    targets = [p for p in props if p.endswith("/last-image")]
    if not targets:
        targets = [f"/backdrop/screen0/{m}/workspace0/last-image" for m in ("monitor0", "monitorVirtual-1", "monitorVirtual1")]
    for p in targets:
        xf("xfce4-desktop", p, "string", path)
        xf("xfce4-desktop", p.replace("last-image", "image-style"), "int", 5)


def xrandr_info():
    output, modes = None, []
    for line in run(["xrandr"]).stdout.splitlines():
        if " connected" in line:
            if output:
                break
            output = line.split()[0]
        elif output and line.startswith("  ") and line.split():
            m = line.split()[0]
            if m not in modes:
                modes.append(m)
        elif output and modes and not line.startswith(" "):
            break
    return output, modes


def read_first(path, key):
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if line.startswith(key):
                    return line.split(":", 1)[1].strip() if ":" in line else line.split("=", 1)[1].strip().strip('"')
    except Exception:
        pass
    return "?"


class Settings(Gtk.Window):
    def __init__(self):
        super().__init__(title=t("settings"))
        self.set_default_size(880, 600)
        self.set_icon_name("preferences-system")
        hb = Gtk.HeaderBar()
        hb.set_show_close_button(True)
        hb.set_title(t("settings"))
        self.set_titlebar(hb)

        box = Gtk.Box()
        self.add(box)
        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        side = Gtk.StackSidebar()
        side.set_stack(self.stack)
        side.set_size_request(210, -1)
        box.pack_start(side, False, False, 0)
        box.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)
        box.pack_start(self.stack, True, True, 0)

        for key, builder in (
            ("appearance", self.page_appearance),
            ("wallpaper", self.page_wallpaper),
            ("dock", self.page_dock),
            ("display", self.page_display),
            ("language", self.page_language),
            ("keyboard", self.page_keyboard),
            ("windows_apps", self.page_windows),
            ("performance", self.page_performance),
            ("system", self.page_system),
            ("about", self.page_about),
        ):
            page = builder()
            sw = Gtk.ScrolledWindow()
            sw.add(page)
            self.stack.add_titled(sw, key, t(key))

    # ----- помощники -----
    def new_page(self, title):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        for m in ("top", "bottom", "start", "end"):
            getattr(page, f"set_margin_{m}")(24)
        lbl = Gtk.Label(xalign=0)
        lbl.set_markup(f"<span size='x-large' weight='bold'>{GLib.markup_escape_text(title)}</span>")
        page.pack_start(lbl, False, False, 0)
        return page

    def row(self, text, widget):
        r = Gtk.Box(spacing=12)
        lab = Gtk.Label(label=text, xalign=0)
        r.pack_start(lab, True, True, 0)
        r.pack_end(widget, False, False, 0)
        return r

    def note(self, text):
        lab = Gtk.Label(label=text, xalign=0)
        lab.set_line_wrap(True)
        lab.set_max_width_chars(70)
        lab.get_style_context().add_class("dim-label")
        return lab

    # ----- страницы -----
    def page_appearance(self):
        p = self.new_page(t("appearance"))
        cur = xf_get("xsettings", "/Net/ThemeName")
        combo = Gtk.ComboBoxText()
        combo.append("light", t("light"))
        combo.append("dark", t("dark"))
        combo.set_active_id("dark" if "Dark" in cur else "light")
        combo.connect("changed", lambda c: set_theme(c.get_active_id() == "dark"))
        p.pack_start(self.row(t("theme"), combo), False, False, 0)
        return p

    def page_wallpaper(self):
        p = self.new_page(t("wallpaper"))
        flow = Gtk.FlowBox()
        flow.set_selection_mode(Gtk.SelectionMode.NONE)
        flow.set_max_children_per_line(4)
        flow.set_min_children_per_line(2)
        flow.set_column_spacing(12)
        flow.set_row_spacing(12)
        files = sorted(glob.glob(os.path.join(WALL_DIR, "*.png")) + glob.glob(os.path.join(WALL_DIR, "*.jpg")))
        for f in files:
            try:
                pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(f, 190, 110, True)
            except Exception:
                continue
            btn = Gtk.Button()
            btn.add(Gtk.Image.new_from_pixbuf(pb))
            btn.set_tooltip_text(os.path.splitext(os.path.basename(f))[0])
            btn.connect("clicked", lambda _b, path=f: set_wallpaper(path))
            flow.add(btn)
        p.pack_start(flow, False, False, 0)
        choose = Gtk.Button(label=t("choose_file"))
        choose.connect("clicked", self.on_choose_wallpaper)
        p.pack_start(choose, False, False, 0)
        return p

    def on_choose_wallpaper(self, *_):
        dlg = Gtk.FileChooserDialog(title=t("wallpaper"), parent=self, action=Gtk.FileChooserAction.OPEN)
        dlg.add_buttons("_Cancel", Gtk.ResponseType.CANCEL, "_OK", Gtk.ResponseType.OK)
        flt = Gtk.FileFilter()
        flt.set_name("Images")
        flt.add_mime_type("image/png")
        flt.add_mime_type("image/jpeg")
        flt.add_mime_type("image/webp")
        dlg.add_filter(flt)
        pics = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES)
        if pics and os.path.isdir(pics):
            dlg.set_current_folder(pics)
        if dlg.run() == Gtk.ResponseType.OK:
            set_wallpaper(dlg.get_filename())
        dlg.destroy()

    def page_dock(self):
        p = self.new_page(t("dock"))
        pos = Gtk.ComboBoxText()
        for k in ("bottom", "left", "right"):
            pos.append(k, t(k))
        pos.set_active_id(gget("position") if gget("position") in ("bottom", "left", "right") else "bottom")
        pos.connect("changed", lambda c: gset("position", c.get_active_id()))
        p.pack_start(self.row(t("dock_position"), pos), False, False, 0)

        try:
            size = int(gget("icon-size") or 48)
        except ValueError:
            size = 48
        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 32, 96, 4)
        scale.set_value(size)
        scale.set_size_request(240, -1)
        scale.connect("value-changed", lambda s: gset("icon-size", int(s.get_value())))
        p.pack_start(self.row(t("dock_size"), scale), False, False, 0)

        zoom = Gtk.Switch()
        zoom.set_active(gget("zoom-enabled") != "false")
        zoom.connect("notify::active", lambda s, _p: gset("zoom-enabled", "true" if s.get_active() else "false"))
        p.pack_start(self.row(t("dock_zoom"), zoom), False, False, 0)
        return p

    def page_display(self):
        p = self.new_page(t("display"))
        output, modes = xrandr_info()
        if output and modes:
            combo = Gtk.ComboBoxText()
            for m in modes:
                combo.append(m, m)
            combo.set_active(0)
            p.pack_start(self.row(t("resolution"), combo), False, False, 0)
            btn = Gtk.Button(label=t("apply"))
            btn.connect("clicked", lambda *_: run(["xrandr", "--output", output, "--mode", combo.get_active_id()]))
            p.pack_start(btn, False, False, 0)
        sc = Gtk.ComboBoxText()
        for pct, dpi in (("100%", 96), ("125%", 120), ("150%", 144), ("200%", 192)):
            sc.append(str(dpi), pct)
        sc.set_active_id(xf_get("xsettings", "/Xft/DPI") if xf_get("xsettings", "/Xft/DPI") in ("96", "120", "144", "192") else "96")
        sc.connect("changed", lambda c: xf("xsettings", "/Xft/DPI", "int", c.get_active_id()))
        p.pack_start(self.row(t("scale"), sc), False, False, 0)
        return p

    def page_language(self):
        p = self.new_page(t("language"))
        combo = Gtk.ComboBoxText()
        for code in I.ORDER:
            combo.append(code, I.LANGS[code][0])
        combo.set_active_id(I.get_lang())
        p.pack_start(self.row(t("system_language"), combo), False, False, 0)
        btn = Gtk.Button(label=t("apply"))
        btn.connect("clicked", lambda *_: self.apply_language(combo.get_active_id()))
        p.pack_start(btn, False, False, 0)
        p.pack_start(self.note(t("lang_note")), False, False, 0)
        return p

    def apply_language(self, code):
        I.set_lang(code)
        run(["sudo", "-n", "/usr/local/sbin/kaming-set-locale", I.LANGS[code][1]])
        os.execv(sys.executable, [sys.executable] + sys.argv)  # перезапуск окна на новом языке

    def page_keyboard(self):
        p = self.new_page(t("keyboard"))
        p.pack_start(Gtk.Label(label=t("layouts"), xalign=0), False, False, 0)
        checks = {}
        for code, name in LAYOUTS:
            cb = Gtk.CheckButton(label=name)
            cb.set_active(code in ("us",))
            checks[code] = cb
            p.pack_start(cb, False, False, 0)

        def apply(*_):
            sel = [c for c, _n in LAYOUTS if checks[c].get_active()] or ["us"]
            layout = ",".join(sel)
            run(["setxkbmap", "-layout", layout, "-option", "grp:alt_shift_toggle"])
            d = os.path.expanduser("~/.config/autostart")
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "kaming-keyboard.desktop"), "w", encoding="utf-8") as f:
                f.write("[Desktop Entry]\nType=Application\nName=Keyboard layouts\n"
                        f"Exec=setxkbmap -layout {layout} -option grp:alt_shift_toggle\n")

        btn = Gtk.Button(label=t("apply"))
        btn.connect("clicked", apply)
        p.pack_start(btn, False, False, 0)
        p.pack_start(self.note(t("switch_hint")), False, False, 0)
        return p

    def page_windows(self):
        p = self.new_page(t("windows_apps"))
        p.pack_start(self.note(t("exe_hint")), False, False, 0)
        b1 = Gtk.Button(label=t("run_exe"))
        b1.connect("clicked", self.on_run_exe)
        b2 = Gtk.Button(label=t("wine_cfg"))
        b2.connect("clicked", lambda *_: spawn(["winecfg"]))
        b3 = Gtk.Button(label=t("runtimes"))
        b3.connect("clicked", lambda *_: spawn(["winetricks", "--gui"]))
        for b in (b1, b2, b3):
            p.pack_start(b, False, False, 0)
        return p

    def on_run_exe(self, *_):
        dlg = Gtk.FileChooserDialog(title=t("run_exe"), parent=self, action=Gtk.FileChooserAction.OPEN)
        dlg.add_buttons("_Cancel", Gtk.ResponseType.CANCEL, "_OK", Gtk.ResponseType.OK)
        flt = Gtk.FileFilter()
        flt.set_name("Windows")
        for pat in ("*.exe", "*.EXE", "*.msi", "*.MSI"):
            flt.add_pattern(pat)
        dlg.add_filter(flt)
        if dlg.run() == Gtk.ResponseType.OK:
            path = dlg.get_filename()
            if path.lower().endswith(".msi"):
                spawn(["wine", "msiexec", "/i", path])
            else:
                spawn(["wine", "start", "/unix", path])
        dlg.destroy()

    def page_performance(self):
        p = self.new_page(t("performance"))
        a = Gtk.Switch()
        a.set_active(xf_get("xsettings", "/Gtk/EnableAnimations") != "true")

        def anim(s, _p):
            off = s.get_active()
            xf("xsettings", "/Gtk/EnableAnimations", "bool", not off)
            if off:
                gset("zoom-enabled", "false")

        a.connect("notify::active", anim)
        p.pack_start(self.row(t("reduce_anim"), a), False, False, 0)

        c = Gtk.Switch()
        c.set_active(xf_get("xfwm4", "/general/use_compositing") != "true")
        c.connect("notify::active", lambda s, _p: xf("xfwm4", "/general/use_compositing", "bool", not s.get_active()))
        p.pack_start(self.row(t("lite_mode"), c), False, False, 0)
        p.pack_start(self.note(t("perf_hint")), False, False, 0)
        if self.is_live():
            b = Gtk.Button(label=t("install_now"))
            b.connect("clicked", lambda *_: spawn(["sudo", "-E", "calamares"]))
            p.pack_start(b, False, False, 0)
        return p

    @staticmethod
    def is_live():
        try:
            return "boot=live" in open("/proc/cmdline").read()
        except Exception:
            return False

    def page_system(self):
        p = self.new_page(t("system"))
        for key, cmd in (("network", ["nm-connection-editor"]),
                         ("sound", ["pavucontrol"]),
                         ("power", ["xfce4-power-manager-settings"])):
            b = Gtk.Button(label=t(key))
            b.connect("clicked", lambda _b, c=cmd: spawn(c))
            p.pack_start(b, False, False, 0)
        return p

    def page_about(self):
        p = self.new_page("Kaming OS")
        mem = read_first("/proc/meminfo", "MemTotal")
        try:
            mem_gb = f"{int(mem.split()[0]) / 1048576:.1f} GB"
        except Exception:
            mem_gb = "?"
        try:
            secs = int(float(open("/proc/uptime").read().split()[0]))
            up = f"{secs // 3600} h {secs % 3600 // 60} min"
        except Exception:
            up = "?"
        virt = run(["systemd-detect-virt"]).stdout.strip() or "none"
        info = [
            (t("version"), "Kaming OS 1.1"),
            (t("kernel"), platform.release()),
            (t("processor"), read_first("/proc/cpuinfo", "model name")),
            (t("memory"), mem_gb),
            (t("uptime"), up),
            (t("virtual"), t("no") if virt == "none" else virt),
        ]
        grid = Gtk.Grid(column_spacing=24, row_spacing=8)
        for i, (k, v) in enumerate(info):
            grid.attach(Gtk.Label(label=k, xalign=0), 0, i, 1, 1)
            val = Gtk.Label(label=v, xalign=0)
            val.set_selectable(True)
            grid.attach(val, 1, i, 1, 1)
        p.pack_start(grid, False, False, 0)
        if self.is_live():
            p.pack_start(self.note(t("live_note")), False, False, 0)
        return p


def main():
    win = Settings()
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
KAMING_EOF_1
chmod 755 "config/includes.chroot/usr/local/bin/kaming-settings"

mkdir -p "$(dirname "config/includes.chroot/usr/local/lib/kaming/kaming_i18n.py")"
cat > "config/includes.chroot/usr/local/lib/kaming/kaming_i18n.py" <<'KAMING_EOF_2'
"""Kaming OS: общие переводы для программ Kaming (en, ru, uk, zh, pl)."""
import json
import os

LANGS = {
    "en": ("English", "en_US.UTF-8"),
    "ru": ("Русский", "ru_RU.UTF-8"),
    "uk": ("Українська", "uk_UA.UTF-8"),
    "zh": ("中文（简体）", "zh_CN.UTF-8"),
    "pl": ("Polski", "pl_PL.UTF-8"),
}
ORDER = ["en", "ru", "uk", "zh", "pl"]
CONF = os.path.expanduser("~/.config/kaming/settings.json")


def _load():
    try:
        with open(CONF, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _save(data):
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    with open(CONF, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)


def _detect():
    code = _load().get("lang")
    if code in LANGS:
        return code
    env = (os.environ.get("LANG") or "en")[:2]
    return env if env in LANGS else "en"


_lang = _detect()


def get_lang():
    return _lang


def set_lang(code):
    global _lang
    if code in LANGS:
        _lang = code
        data = _load()
        data["lang"] = code
        _save(data)


# key: (en, ru, uk, zh, pl)
S = {
    # --- Настройки ---
    "settings": ("Settings", "Настройки", "Налаштування", "设置", "Ustawienia"),
    "appearance": ("Appearance", "Оформление", "Оформлення", "外观", "Wygląd"),
    "wallpaper": ("Wallpaper", "Обои", "Шпалери", "壁纸", "Tapeta"),
    "dock": ("Dock", "Док", "Док", "程序坞", "Dok"),
    "display": ("Display", "Экран", "Екран", "显示", "Ekran"),
    "language": ("Language", "Язык", "Мова", "语言", "Język"),
    "keyboard": ("Keyboard", "Клавиатура", "Клавіатура", "键盘", "Klawiatura"),
    "windows_apps": ("Windows apps", "Программы Windows", "Програми Windows", "Windows 程序", "Programy Windows"),
    "performance": ("Performance", "Производительность", "Продуктивність", "性能", "Wydajność"),
    "system": ("System", "Система", "Система", "系统", "System"),
    "about": ("About", "О системе", "Про систему", "关于", "O systemie"),
    "theme": ("Theme", "Тема", "Тема", "主题", "Motyw"),
    "light": ("Light", "Светлая", "Світла", "浅色", "Jasny"),
    "dark": ("Dark", "Тёмная", "Темна", "深色", "Ciemny"),
    "choose_file": ("Choose image…", "Выбрать картинку…", "Обрати зображення…", "选择图片…", "Wybierz obraz…"),
    "dock_position": ("Dock position", "Положение дока", "Положення дока", "程序坞位置", "Położenie doku"),
    "bottom": ("Bottom", "Снизу", "Знизу", "底部", "Dół"),
    "left": ("Left", "Слева", "Зліва", "左侧", "Lewo"),
    "right": ("Right", "Справа", "Справа", "右侧", "Prawo"),
    "dock_size": ("Icon size", "Размер значков", "Розмір значків", "图标大小", "Rozmiar ikon"),
    "dock_zoom": ("Zoom on hover", "Увеличение при наведении", "Збільшення при наведенні", "悬停放大", "Powiększenie po najechaniu"),
    "resolution": ("Resolution", "Разрешение", "Роздільна здатність", "分辨率", "Rozdzielczość"),
    "scale": ("Interface scale", "Масштаб интерфейса", "Масштаб інтерфейсу", "界面缩放", "Skala interfejsu"),
    "apply": ("Apply", "Применить", "Застосувати", "应用", "Zastosuj"),
    "system_language": ("System language", "Язык системы", "Мова системи", "系统语言", "Język systemu"),
    "lang_note": (
        "Kaming apps change immediately (the window restarts). Other programs switch after you log out and back in.",
        "Программы Kaming меняются сразу (окно перезапустится). Остальные программы переключатся после выхода и повторного входа.",
        "Програми Kaming змінюються одразу (вікно перезапуститься). Інші програми перемкнуться після виходу та повторного входу.",
        "Kaming 程序会立即切换（窗口将重启）。其他程序在注销并重新登录后切换。",
        "Programy Kaming zmieniają się od razu (okno uruchomi się ponownie). Pozostałe po wylogowaniu i ponownym zalogowaniu.",
    ),
    "layouts": ("Keyboard layouts", "Раскладки клавиатуры", "Розкладки клавіатури", "键盘布局", "Układy klawiatury"),
    "switch_hint": ("Switch layout: Alt + Shift", "Переключение: Alt + Shift", "Перемикання: Alt + Shift", "切换布局：Alt + Shift", "Przełączanie: Alt + Shift"),
    "run_exe": ("Run a Windows program (.exe / .msi)…", "Запустить программу Windows (.exe / .msi)…", "Запустити програму Windows (.exe / .msi)…", "运行 Windows 程序（.exe / .msi）…", "Uruchom program Windows (.exe / .msi)…"),
    "wine_cfg": ("Wine settings", "Настройки Wine", "Налаштування Wine", "Wine 设置", "Ustawienia Wine"),
    "runtimes": ("Install Windows components (winetricks)", "Установить компоненты Windows (winetricks)", "Встановити компоненти Windows (winetricks)", "安装 Windows 组件（winetricks）", "Zainstaluj składniki Windows (winetricks)"),
    "exe_hint": (
        "Double-click any .exe file to run it. Not every program works: many simple apps do, heavy games often don't.",
        "Двойной клик по .exe запускает программу. Работают не все программы: простые чаще работают, тяжёлые игры часто нет.",
        "Подвійний клік по .exe запускає програму. Працюють не всі програми: прості частіше, важкі ігри часто ні.",
        "双击 .exe 文件即可运行。并非所有程序都能运行：简单程序通常可以，大型游戏常常不行。",
        "Dwukrotne kliknięcie pliku .exe uruchamia program. Nie wszystko działa: proste programy zwykle tak, ciężkie gry często nie.",
    ),
    "reduce_anim": ("Reduce animations (faster)", "Меньше анимаций (быстрее)", "Менше анімацій (швидше)", "减少动画（更快）", "Mniej animacji (szybciej)"),
    "lite_mode": ("Lite mode: no window effects", "Лёгкий режим: без эффектов окон", "Легкий режим: без ефектів вікон", "精简模式：无窗口特效", "Tryb lekki: bez efektów okien"),
    "perf_hint": (
        "Tip: installing Kaming OS to a virtual disk is much faster than running from the ISO.",
        "Совет: установка Kaming OS на виртуальный диск работает намного быстрее, чем запуск с ISO.",
        "Порада: встановлення Kaming OS на віртуальний диск працює значно швидше, ніж запуск з ISO.",
        "提示：将 Kaming OS 安装到虚拟磁盘比直接从 ISO 运行快得多。",
        "Wskazówka: instalacja Kaming OS na dysku wirtualnym jest znacznie szybsza niż uruchamianie z ISO.",
    ),
    "install_now": ("Install Kaming OS…", "Установить Kaming OS…", "Встановити Kaming OS…", "安装 Kaming OS…", "Zainstaluj Kaming OS…"),
    "network": ("Network", "Сеть", "Мережа", "网络", "Sieć"),
    "sound": ("Sound", "Звук", "Звук", "声音", "Dźwięk"),
    "power": ("Power", "Питание", "Живлення", "电源", "Zasilanie"),
    "version": ("Version", "Версия", "Версія", "版本", "Wersja"),
    "kernel": ("Kernel", "Ядро", "Ядро", "内核", "Jądro"),
    "memory": ("Memory", "Память", "Пам'ять", "内存", "Pamięć"),
    "processor": ("Processor", "Процессор", "Процесор", "处理器", "Procesor"),
    "uptime": ("Uptime", "Время работы", "Час роботи", "运行时间", "Czas pracy"),
    "virtual": ("Virtual machine", "Виртуальная машина", "Віртуальна машина", "虚拟机", "Maszyna wirtualna"),
    "no": ("no", "нет", "ні", "否", "nie"),
    "live_note": (
        "You are running from the ISO (live mode). Install to disk for the best speed.",
        "Вы запустили систему с ISO (live-режим). Установите её на диск для лучшей скорости.",
        "Ви запустили систему з ISO (live-режим). Встановіть її на диск для кращої швидкості.",
        "您正从 ISO 运行（live 模式）。安装到磁盘可获得最佳速度。",
        "Uruchomiono z ISO (tryb live). Zainstaluj na dysku, aby było szybciej.",
    ),
    # --- Браузер ---
    "browser": ("Kaming Browser", "Браузер Kaming", "Браузер Kaming", "Kaming 浏览器", "Przeglądarka Kaming"),
    "new_tab": ("New Tab", "Новая вкладка", "Нова вкладка", "新标签页", "Nowa karta"),
    "new_window": ("New Window", "Новое окно", "Нове вікно", "新窗口", "Nowe okno"),
    "private_window": ("New Private Window", "Приватное окно", "Приватне вікно", "新建隐私窗口", "Nowe okno prywatne"),
    "private": ("Private", "Приватный режим", "Приватний режим", "隐私模式", "Tryb prywatny"),
    "search_or_url": ("Search or enter address", "Поиск или адрес сайта", "Пошук або адреса сайту", "搜索或输入网址", "Szukaj lub wpisz adres"),
    "bookmarks": ("Bookmarks", "Закладки", "Закладки", "书签", "Zakładki"),
    "history": ("History", "История", "Історія", "历史记录", "Historia"),
    "add_bookmark": ("Add bookmark", "Добавить в закладки", "Додати до закладок", "添加书签", "Dodaj zakładkę"),
    "remove_bookmark": ("Remove bookmark", "Убрать из закладок", "Прибрати із закладок", "移除书签", "Usuń zakładkę"),
    "find": ("Find on page", "Найти на странице", "Знайти на сторінці", "在页面中查找", "Znajdź na stronie"),
    "zoom_in": ("Zoom in", "Увеличить", "Збільшити", "放大", "Powiększ"),
    "zoom_out": ("Zoom out", "Уменьшить", "Зменшити", "缩小", "Pomniejsz"),
    "zoom_reset": ("Actual size", "Обычный размер", "Звичайний розмір", "实际大小", "Rozmiar rzeczywisty"),
    "search_engine": ("Search engine", "Поисковая система", "Пошукова система", "搜索引擎", "Wyszukiwarka"),
    "clear_history": ("Clear history", "Очистить историю", "Очистити історію", "清除历史记录", "Wyczyść historię"),
    "open_downloads": ("Open Downloads folder", "Открыть папку «Загрузки»", "Відкрити теку «Завантаження»", "打开下载文件夹", "Otwórz folder Pobrane"),
    "downloaded": ("Downloaded", "Скачано", "Завантажено", "已下载", "Pobrano"),
    "favorites": ("Favorites", "Избранное", "Обране", "收藏夹", "Ulubione"),
    "start_search": ("Search the web", "Поиск в интернете", "Пошук в інтернеті", "搜索网络", "Szukaj w internecie"),
    "empty": ("Empty", "Пусто", "Порожньо", "空", "Pusto"),
    "load_failed": ("Can't open this page", "Не удаётся открыть страницу", "Не вдається відкрити сторінку", "无法打开此页面", "Nie można otworzyć strony"),
    "check_connection": ("Check the address and your internet connection.", "Проверьте адрес и подключение к интернету.", "Перевірте адресу та підключення до інтернету.", "请检查网址和网络连接。", "Sprawdź adres i połączenie z internetem."),
    "close_tab": ("Close tab", "Закрыть вкладку", "Закрити вкладку", "关闭标签页", "Zamknij kartę"),
}


def t(key):
    row = S.get(key)
    if not row:
        return key
    return row[ORDER.index(_lang)]
KAMING_EOF_2
chmod 644 "config/includes.chroot/usr/local/lib/kaming/kaming_i18n.py"

mkdir -p "$(dirname "config/includes.chroot/usr/local/sbin/kaming-set-locale")"
cat > "config/includes.chroot/usr/local/sbin/kaming-set-locale" <<'KAMING_EOF_3'
#!/bin/bash
# Меняет язык системы. Допускает только разрешённые локали.
case "$1" in
  en_US.UTF-8|ru_RU.UTF-8|uk_UA.UTF-8|zh_CN.UTF-8|pl_PL.UTF-8) ;;
  *) echo "unsupported locale" >&2; exit 1 ;;
esac
update-locale LANG="$1" LANGUAGE="${1%%.*}:${1%%_*}"
KAMING_EOF_3
chmod 755 "config/includes.chroot/usr/local/sbin/kaming-set-locale"

mkdir -p "$(dirname "config/includes.chroot/etc/sudoers.d/kaming-settings")"
cat > "config/includes.chroot/etc/sudoers.d/kaming-settings" <<'KAMING_EOF_4'
%sudo ALL=(root) NOPASSWD: /usr/local/sbin/kaming-set-locale
KAMING_EOF_4
chmod 440 "config/includes.chroot/etc/sudoers.d/kaming-settings"

mkdir -p "$(dirname "config/includes.chroot/usr/share/applications/kaming-browser.desktop")"
cat > "config/includes.chroot/usr/share/applications/kaming-browser.desktop" <<'KAMING_EOF_5'
[Desktop Entry]
Type=Application
Name=Kaming Browser
Name[ru]=Браузер Kaming
Name[uk]=Браузер Kaming
Name[zh_CN]=Kaming 浏览器
Name[pl]=Przeglądarka Kaming
GenericName=Web Browser
Exec=kaming-browser %U
Icon=web-browser
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
StartupWMClass=Kaming Browser
Actions=private;

[Desktop Action private]
Name=New Private Window
Exec=kaming-browser --private
KAMING_EOF_5
chmod 644 "config/includes.chroot/usr/share/applications/kaming-browser.desktop"

mkdir -p "$(dirname "config/includes.chroot/usr/share/applications/kaming-settings.desktop")"
cat > "config/includes.chroot/usr/share/applications/kaming-settings.desktop" <<'KAMING_EOF_6'
[Desktop Entry]
Type=Application
Name=Kaming Settings
Name[ru]=Настройки Kaming
Name[uk]=Налаштування Kaming
Name[zh_CN]=Kaming 设置
Name[pl]=Ustawienia Kaming
Exec=kaming-settings
Icon=preferences-system
Terminal=false
Categories=Settings;System;
KAMING_EOF_6
chmod 644 "config/includes.chroot/usr/share/applications/kaming-settings.desktop"

mkdir -p "$(dirname "config/includes.chroot/usr/share/applications/wine-exe.desktop")"
cat > "config/includes.chroot/usr/share/applications/wine-exe.desktop" <<'KAMING_EOF_7'
[Desktop Entry]
Type=Application
Name=Windows Program (Wine)
Exec=wine start /unix %f
MimeType=application/x-ms-dos-executable;application/x-msdownload;application/vnd.microsoft.portable-executable;
NoDisplay=true
KAMING_EOF_7
chmod 644 "config/includes.chroot/usr/share/applications/wine-exe.desktop"

mkdir -p "$(dirname "config/includes.chroot/usr/share/applications/wine-msi.desktop")"
cat > "config/includes.chroot/usr/share/applications/wine-msi.desktop" <<'KAMING_EOF_8'
[Desktop Entry]
Type=Application
Name=Windows Installer (Wine)
Exec=wine msiexec /i %f
MimeType=application/x-msi;
NoDisplay=true
KAMING_EOF_8
chmod 644 "config/includes.chroot/usr/share/applications/wine-msi.desktop"

mkdir -p "$(dirname "config/includes.chroot/etc/skel/Desktop/install-kaming-os.desktop")"
cat > "config/includes.chroot/etc/skel/Desktop/install-kaming-os.desktop" <<'KAMING_EOF_9'
[Desktop Entry]
Type=Application
Name=Install Kaming OS
Name[ru]=Установить Kaming OS
Name[uk]=Встановити Kaming OS
Name[zh_CN]=安装 Kaming OS
Name[pl]=Zainstaluj Kaming OS
Exec=sudo -E calamares
Icon=system-software-install
Terminal=false
KAMING_EOF_9
chmod 755 "config/includes.chroot/etc/skel/Desktop/install-kaming-os.desktop"

mkdir -p "$(dirname "config/includes.chroot/etc/lightdm/lightdm.conf.d/50-kaming.conf")"
cat > "config/includes.chroot/etc/lightdm/lightdm.conf.d/50-kaming.conf" <<'KAMING_EOF_10'
[Seat:*]
autologin-user=kaming
autologin-user-timeout=0
user-session=xfce
KAMING_EOF_10
chmod 644 "config/includes.chroot/etc/lightdm/lightdm.conf.d/50-kaming.conf"

mkdir -p "$(dirname "config/includes.chroot/etc/os-release")"
cat > "config/includes.chroot/etc/os-release" <<'KAMING_EOF_11'
PRETTY_NAME="Kaming OS 1.1"
NAME="Kaming OS"
VERSION="1.1"
ID=kamingos
ID_LIKE=debian
HOME_URL="https://example.com"
KAMING_EOF_11
chmod 644 "config/includes.chroot/etc/os-release"

mkdir -p "$(dirname "config/includes.chroot/etc/skel/.config/autostart/plank.desktop")"
cat > "config/includes.chroot/etc/skel/.config/autostart/plank.desktop" <<'KAMING_EOF_12'
[Desktop Entry]
Type=Application
Name=Dock
Exec=plank
X-GNOME-Autostart-enabled=true
KAMING_EOF_12
chmod 644 "config/includes.chroot/etc/skel/.config/autostart/plank.desktop"

mkdir -p "$(dirname "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/10-browser.dockitem")"
cat > "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/10-browser.dockitem" <<'KAMING_EOF_13'
[PlankDockItemPreferences]
Launcher=file:///usr/share/applications/kaming-browser.desktop
KAMING_EOF_13
chmod 644 "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/10-browser.dockitem"

mkdir -p "$(dirname "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/20-files.dockitem")"
cat > "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/20-files.dockitem" <<'KAMING_EOF_14'
[PlankDockItemPreferences]
Launcher=file:///usr/share/applications/thunar.desktop
KAMING_EOF_14
chmod 644 "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/20-files.dockitem"

mkdir -p "$(dirname "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/30-settings.dockitem")"
cat > "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/30-settings.dockitem" <<'KAMING_EOF_15'
[PlankDockItemPreferences]
Launcher=file:///usr/share/applications/kaming-settings.desktop
KAMING_EOF_15
chmod 644 "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/30-settings.dockitem"

mkdir -p "$(dirname "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/40-calculator.dockitem")"
cat > "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/40-calculator.dockitem" <<'KAMING_EOF_16'
[PlankDockItemPreferences]
Launcher=file:///usr/share/applications/galculator.desktop
KAMING_EOF_16
chmod 644 "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/40-calculator.dockitem"

mkdir -p "$(dirname "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/50-editor.dockitem")"
cat > "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/50-editor.dockitem" <<'KAMING_EOF_17'
[PlankDockItemPreferences]
Launcher=file:///usr/share/applications/org.xfce.mousepad.desktop
KAMING_EOF_17
chmod 644 "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/50-editor.dockitem"

mkdir -p "$(dirname "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/60-terminal.dockitem")"
cat > "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/60-terminal.dockitem" <<'KAMING_EOF_18'
[PlankDockItemPreferences]
Launcher=file:///usr/share/applications/xfce4-terminal.desktop
KAMING_EOF_18
chmod 644 "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/60-terminal.dockitem"

mkdir -p "$(dirname "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/70-firefox.dockitem")"
cat > "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/70-firefox.dockitem" <<'KAMING_EOF_19'
[PlankDockItemPreferences]
Launcher=file:///usr/share/applications/firefox-esr.desktop
KAMING_EOF_19
chmod 644 "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/70-firefox.dockitem"

mkdir -p "$(dirname "config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml")"
cat > "config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" <<'KAMING_EOF_20'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="WhiteSur-Light"/>
    <property name="IconThemeName" type="string" value="WhiteSur"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Inter 10"/>
    <property name="CursorThemeName" type="string" value="WhiteSur-cursors"/>
    <property name="EnableAnimations" type="bool" value="false"/>
  </property>
  <property name="Xft" type="empty">
    <property name="Antialias" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="rgb"/>
  </property>
</channel>
KAMING_EOF_20
chmod 644 "config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"

mkdir -p "$(dirname "config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml")"
cat > "config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" <<'KAMING_EOF_21'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="WhiteSur-Light"/>
    <property name="button_layout" type="string" value="CHM|"/>
    <property name="title_alignment" type="string" value="center"/>
    <property name="use_compositing" type="bool" value="false"/>
    <property name="show_dock_shadow" type="bool" value="false"/>
    <property name="show_frame_shadow" type="bool" value="false"/>
  </property>
</channel>
KAMING_EOF_21
chmod 644 "config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"

mkdir -p "$(dirname "config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml")"
cat > "config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml" <<'KAMING_EOF_22'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorVirtual-1" type="empty">
        <property name="workspace0" type="empty">
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="/usr/share/backgrounds/kaming/Kaming-Blue.png"/>
        </property>
      </property>
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="/usr/share/backgrounds/kaming/Kaming-Blue.png"/>
        </property>
      </property>
    </property>
  </property>
</channel>
KAMING_EOF_22
chmod 644 "config/includes.chroot/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"

mkdir -p "$(dirname "config/includes.chroot/etc/skel/.config/mimeapps.list")"
cat > "config/includes.chroot/etc/skel/.config/mimeapps.list" <<'KAMING_EOF_23'
[Default Applications]
application/x-ms-dos-executable=wine-exe.desktop
application/x-msdownload=wine-exe.desktop
application/vnd.microsoft.portable-executable=wine-exe.desktop
application/x-msi=wine-msi.desktop
text/html=kaming-browser.desktop
x-scheme-handler/http=kaming-browser.desktop
x-scheme-handler/https=kaming-browser.desktop
KAMING_EOF_23
chmod 644 "config/includes.chroot/etc/skel/.config/mimeapps.list"

mkdir -p "$(dirname "config/hooks/live/0100-kaming.hook.chroot")"
cat > "config/hooks/live/0100-kaming.hook.chroot" <<'KAMING_EOF_24'
#!/bin/bash
set -x
export DEBIAN_FRONTEND=noninteractive
mk() { if command -v magick >/dev/null 2>&1; then magick "$@"; else convert "$@"; fi; }

# 1) 32-битные Windows-программы (большинство .exe именно 32-битные)
dpkg --add-architecture i386 || true
apt-get update || true
apt-get install -y wine32:i386 || true

# 2) Языки системы
for l in en_US ru_RU uk_UA zh_CN pl_PL; do
  sed -i "s/^# *\(${l}\.UTF-8 UTF-8\)/\1/" /etc/locale.gen
done
locale-gen || true
echo 'LANG=en_US.UTF-8' > /etc/default/locale

# 3) Тема, иконки и курсоры в стиле macOS (открытые, проект WhiteSur)
cd /tmp
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-gtk-theme.git || true
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-icon-theme.git || true
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-cursors.git || true
( cd WhiteSur-gtk-theme  && ./install.sh -d /usr/share/themes ) || true
( cd WhiteSur-icon-theme && ./install.sh -d /usr/share/icons ) || true
( cd WhiteSur-cursors    && ./install.sh ) || true
rm -rf /tmp/WhiteSur-*
ls /usr/share/themes | grep -i whitesur || echo "WARNING: WhiteSur theme not installed"

# 4) Обои
W=/usr/share/backgrounds/kaming
mkdir -p "$W"
mk -size 2560x1440 radial-gradient:'#6dd5fa-#2b32b2' "$W/Kaming-Blue.png" || true
mk -size 2560x1440 gradient:'#ff9966-#ff5e62'          "$W/Sunset.png"     || true
mk -size 2560x1440 gradient:'#134e5e-#71b280'          "$W/Forest.png"     || true
mk -size 2560x1440 gradient:'#0f0c29-#302b63'          "$W/Midnight.png"   || true
mk -size 2560x1440 gradient:'#00c6ff-#0072ff'          "$W/Aurora.png"     || true
mk -size 2560x1440 gradient:'#ee9ca7-#ffdde1'          "$W/Rose.png"       || true
mk -size 2560x1440 gradient:'#232526-#414345'          "$W/Graphite.png"   || true

# 5) Права и браузер по умолчанию
chmod +x /usr/local/bin/kaming-browser /usr/local/bin/kaming-settings /usr/local/sbin/kaming-set-locale
chmod 0440 /etc/sudoers.d/kaming-settings
update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/local/bin/kaming-browser 200 || true
update-alternatives --install /usr/bin/gnome-www-browser gnome-www-browser /usr/local/bin/kaming-browser 200 || true
update-desktop-database /usr/share/applications || true

# 6) Пользователь kaming (пароль live)
if ! id kaming >/dev/null 2>&1; then
  useradd -m -s /bin/bash -G sudo,audio,video,netdev,plugdev kaming
fi
echo "kaming:live" | chpasswd
mkdir -p /home/kaming
cp -rT /etc/skel /home/kaming
chown -R kaming:kaming /home/kaming
KAMING_EOF_24
chmod 755 "config/hooks/live/0100-kaming.hook.chroot"

mkdir -p "$(dirname "config/package-lists/kaming.list.chroot")"
cat > "config/package-lists/kaming.list.chroot" <<'KAMING_EOF_25'
# Рабочий стол
xfce4
xfce4-goodies
lightdm
lightdm-gtk-greeter
plank
network-manager
network-manager-gnome
pulseaudio
pavucontrol
dbus-x11
sudo
xfconf
libglib2.0-bin
x11-xserver-utils
x11-xkb-utils
libnotify-bin
zram-tools
# Тема и шрифты
fonts-inter
fonts-noto
fonts-noto-cjk
fonts-noto-color-emoji
gnome-themes-extra
sassc
libglib2.0-dev-bin
libxml2-utils
git
imagemagick
# Языки
locales
firefox-esr-l10n-ru
firefox-esr-l10n-uk
firefox-esr-l10n-zh-cn
firefox-esr-l10n-pl
# Для программ Kaming (браузер на WebKit, настройки на GTK)
python3
python3-gi
python3-gi-cairo
gir1.2-gtk-3.0
gir1.2-webkit2-4.1
# Программы
firefox-esr
galculator
mousepad
thunar
thunar-archive-plugin
xarchiver
xfce4-terminal
ristretto
evince
vlc
file-roller
# Windows-программы
wine
wine64
winetricks
zenity
# Виртуалки
open-vm-tools
open-vm-tools-desktop
spice-vdagent
qemu-guest-agent
# Установка на компьютер
calamares
calamares-settings-debian
# Драйверы и прошивки
firmware-linux
firmware-misc-nonfree
firmware-iwlwifi
firmware-realtek
firmware-atheros
KAMING_EOF_25
chmod 644 "config/package-lists/kaming.list.chroot"


echo "==> Сборка ISO (это долго, 20-60 минут)"
lb build 2>&1 | tee build.log

ISO="$(ls -1 *.iso | head -n1)"
mv "$ISO" ../kaming-os.iso
echo
echo "Готово: $(cd .. && pwd)/kaming-os.iso"
echo "Вход: пользователь kaming, пароль live"
