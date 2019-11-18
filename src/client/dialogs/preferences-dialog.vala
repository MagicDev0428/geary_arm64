/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Geary/preferences-dialog.ui")]
public class PreferencesDialog : Gtk.Dialog {

    [GtkChild]
    private Gtk.CheckButton autoselect;

    [GtkChild]
    private Gtk.CheckButton display_preview;

    [GtkChild]
    private Gtk.CheckButton three_pane_view;

    [GtkChild]
    private Gtk.CheckButton startup_notifications;

    [GtkChild]
    private Gtk.HeaderBar header;

    private Application.Client app;

    public PreferencesDialog(Gtk.Window parent, Application.Client app) {
        set_transient_for(parent);
        set_titlebar(this.header);
        this.app = app;

        Application.Configuration config = app.config;
        config.bind(Application.Configuration.AUTOSELECT_KEY, autoselect, "active");
        config.bind(Application.Configuration.DISPLAY_PREVIEW_KEY, display_preview, "active");
        config.bind(Application.Configuration.FOLDER_LIST_PANE_HORIZONTAL_KEY, three_pane_view, "active");
        config.bind(Application.Configuration.STARTUP_NOTIFICATIONS_KEY, startup_notifications, "active");
    }

    public new void run() {
        // Sync startup notification option with file state
        this.app.autostart.sync_with_config();

        base.run();
        destroy();
    }
}
