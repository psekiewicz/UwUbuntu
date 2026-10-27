"""Small helpers shared by the UwUbuntu apps (UwU Welcome, UwU Settings, Paw Updater)."""

import os
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk  # noqa: E402

LOGO = "/usr/share/pixmaps/uwubuntu-logo.png"
BACKGROUNDS = Path("/usr/share/backgrounds/uwubuntu")
CONFIG_DIR = Path(GLib.get_user_config_dir()) / "uwubuntu"
WELCOME_DONE = CONFIG_DIR / "welcome-done"
INSTALLER_DESKTOP = "/usr/share/applications/uwubuntu-installer.desktop"

# GNOME's accent-color enum, in the order Settings shows them
ACCENTS = ["blue", "teal", "green", "yellow", "orange", "red", "pink", "purple", "slate"]

# Animation extensions the image ships (see config/gnome-extensions.list)
ANIMATION_EXTENSIONS = [
    ("burn-my-windows@schneegans.github.com", "Burn My Windows",
     "Fancy effects when windows open and close"),
    ("compiz-windows-effect@hermes83.github.com", "Wobbly windows",
     "Windows go jelly-wobbly while you drag them"),
    ("compiz-alike-magic-lamp-effect@hermes83.github.com", "Magic lamp",
     "Windows get sucked into the dock when minimised"),
    ("blur-my-shell@aunetx", "Blur My Shell",
     "Frosted-glass top bar, dock and overview"),
]


def os_release():
    info = {}
    try:
        with open("/etc/os-release", encoding="utf-8") as f:
            for line in f:
                key, sep, value = line.strip().partition("=")
                if sep:
                    info[key] = value.strip('"')
    except OSError:
        pass
    return info


def logo_paintable():
    try:
        return Gdk.Texture.new_from_filename(LOGO)
    except GLib.Error:
        return None


def settings_for(schema_id, key=None):
    """Gio.Settings for schema_id, or None if the schema (or key) isn't installed."""
    source = Gio.SettingsSchemaSource.get_default()
    schema = source.lookup(schema_id, True) if source else None
    if schema is None or (key is not None and not schema.has_key(key)):
        return None
    return Gio.Settings.new(schema_id)


def is_live_session():
    return os.path.exists(INSTALLER_DESKTOP)


def launch_installer():
    app = Gio.DesktopAppInfo.new_from_filename(INSTALLER_DESKTOP)
    if app:
        app.launch([], None)


def extension_installed(uuid):
    for base in (Path(GLib.get_user_data_dir()), Path("/usr/share")):
        if (base / "gnome-shell" / "extensions" / uuid / "metadata.json").exists():
            return True
    return False


def welcome_shows_at_login():
    return not WELCOME_DONE.exists()


def set_welcome_shows_at_login(show):
    if show:
        WELCOME_DONE.unlink(missing_ok=True)
    else:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        WELCOME_DONE.touch()


def wallpapers():
    """(label, path) for every UwUbuntu wallpaper."""
    found = []
    for path in sorted(BACKGROUNDS.glob("*.png")):
        label = path.stem.replace("uwubuntu-", "").replace("-", " ").capitalize()
        found.append((label, str(path)))
    return found


class CommandRunner:
    """Run commands one after another, streaming their output line by line.

    on_line(text) is called for every output line; on_done(results) gets a list
    of (argv, exit_status, output) once the queue is empty or a command fails
    with stop_on_error set.
    """

    def __init__(self, on_line, on_done, stop_on_error=False):
        self.on_line = on_line
        self.on_done = on_done
        self.stop_on_error = stop_on_error
        self.queue = []
        self.results = []
        self.busy = False

    def run(self, commands):
        self.queue = [list(c) for c in commands]
        self.results = []
        self.busy = True
        self._next()

    def _next(self):
        failed = self.results and self.results[-1][1] != 0
        if not self.queue or (failed and self.stop_on_error):
            self.busy = False
            self.on_done(self.results)
            return
        argv = self.queue.pop(0)
        self.on_line("$ " + " ".join(argv))
        try:
            proc = Gio.Subprocess.new(
                argv, Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE)
        except GLib.Error as err:
            self.on_line(err.message)
            self.results.append((argv, 127, err.message))
            self._next()
            return
        stream = Gio.DataInputStream.new(proc.get_stdout_pipe())
        stream.read_line_async(GLib.PRIORITY_DEFAULT, None, self._on_line, (proc, argv, []))

    def _on_line(self, stream, result, data):
        proc, argv, lines = data
        try:
            line, _length = stream.read_line_finish_utf8(result)
        except GLib.Error:
            line = None
        if line is None:
            proc.wait_async(None, self._on_exit, (argv, lines))
            return
        line = line.rstrip("\r")
        lines.append(line)
        self.on_line(line)
        stream.read_line_async(GLib.PRIORITY_DEFAULT, None, self._on_line, data)

    def _on_exit(self, proc, result, data):
        argv, lines = data
        try:
            proc.wait_finish(result)
        except GLib.Error:
            pass
        status = proc.get_exit_status() if proc.get_if_exited() else -1
        self.results.append((argv, status, "\n".join(lines)))
        self._next()


def make_log_view():
    """A monospace, read-only log in a scroller; returns (scroller, append_fn)."""
    view = Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                        wrap_mode=Gtk.WrapMode.WORD_CHAR)
    view.set_top_margin(8)
    view.set_bottom_margin(8)
    view.set_left_margin(10)
    view.set_right_margin(10)
    scroller = Gtk.ScrolledWindow(child=view, min_content_height=160, vexpand=True)
    scroller.add_css_class("card")

    def scroll_to_end():
        adj = scroller.get_vadjustment()
        adj.set_value(adj.get_upper() - adj.get_page_size())
        return GLib.SOURCE_REMOVE

    def append(text):
        buf = view.get_buffer()
        buf.insert(buf.get_end_iter(), text + "\n")
        GLib.idle_add(scroll_to_end)

    return scroller, append


def status_page(title, description, icon_name=None, paintable=None, child=None):
    page = Adw.StatusPage(title=title, description=description)
    if paintable is not None:
        page.set_paintable(paintable)
    elif icon_name:
        page.set_icon_name(icon_name)
    if child is not None:
        page.set_child(child)
    return page
