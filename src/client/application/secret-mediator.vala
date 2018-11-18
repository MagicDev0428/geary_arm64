/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/** LibSecret password adapter. */
public class SecretMediator : Geary.CredentialsMediator, Object {

    private const string ATTR_LOGIN = "login";
    private const string ATTR_HOST = "host";
    private const string ATTR_PROTO = "proto";

    private static Secret.Schema schema = new Secret.Schema(
        GearyApplication.APP_ID,
        Secret.SchemaFlags.NONE,
        ATTR_LOGIN, Secret.SchemaAttributeType.STRING,
        ATTR_HOST, Secret.SchemaAttributeType.STRING,
        ATTR_PROTO, Secret.SchemaAttributeType.STRING,
        null
    );

    // See Bug 697681
    private static Secret.Schema compat_schema = new Secret.Schema(
        "org.gnome.keyring.NetworkPassword",
        Secret.SchemaFlags.NONE,
        "user", Secret.SchemaAttributeType.STRING,
        "domain", Secret.SchemaAttributeType.STRING,
        "object", Secret.SchemaAttributeType.STRING,
        "protocol", Secret.SchemaAttributeType.STRING,
        "port", Secret.SchemaAttributeType.INTEGER,
        "server", Secret.SchemaAttributeType.STRING,
        "authtype", Secret.SchemaAttributeType.STRING,
        null
    );

    private GearyApplication application;
    private Geary.Nonblocking.Mutex dialog_mutex = new Geary.Nonblocking.Mutex();


    public async SecretMediator(GearyApplication application,
                                GLib.Cancellable? cancellable)
        throws GLib.Error {
        this.application = application;
        yield check_unlocked(cancellable);
    }

    public virtual async bool load_token(Geary.AccountInformation account,
                                         Geary.ServiceInformation service,
                                         Cancellable? cancellable)
        throws GLib.Error {
        bool loaded = false;
        if (service.remember_password) {
            string? password = yield Secret.password_lookupv(
                SecretMediator.schema, new_attrs(service), cancellable
            );

            if (password == null) {
                password = yield migrate_old_password(service, cancellable);
            }

            if (password != null) {
                service.credentials =
                    service.credentials.copy_with_token(password);
                loaded = true;
            } else {
                debug(
                    "Unable to fetch libsecret password for %s: %s %s",
                    account.id,
                    service.protocol.to_string(),
                    service.credentials.user
                );
            }
        } else {
            loaded = yield prompt_token(account, service, cancellable);
        }
        return loaded;
    }

    public virtual async bool prompt_token(Geary.AccountInformation account,
                                           Geary.ServiceInformation service,
                                           GLib.Cancellable? cancellable)
        throws GLib.Error {
        // to prevent multiple dialogs from popping up at the same
        // time, use a nonblocking mutex to serialize the code
        int token = yield dialog_mutex.claim_async(null);

        // Ensure main window present to the window
        this.application.present();

        PasswordDialog password_dialog = new PasswordDialog(
            this.application.get_active_window(),
            account,
            service
        );
        bool result = password_dialog.run();

        dialog_mutex.release(ref token);

        if (result) {
            // password_dialog.password should never be null at this
            // point. It will only be null when password_dialog.run()
            // returns false, in which case we have already returned.
            service.credentials = service.credentials.copy_with_token(
                password_dialog.password
            );
            service.remember_password = password_dialog.remember_password;

            yield update_token(account, service, cancellable);

            account.information_changed();
        }
        return true;
    }

    public async void update_token(Geary.AccountInformation account,
                                   Geary.ServiceInformation service,
                                   Cancellable? cancellable)
        throws Error {
        if (service.remember_password) {
            try {
                yield do_store(service, service.credentials.token, cancellable);
            } catch (Error e) {
                debug(
                    "Unable to store libsecret password for %s: %s %s",
                    account.id,
                    service.protocol.to_string(),
                    service.credentials.user
                );
            }
        } else {
            yield clear_token(account, service, cancellable);
        }
    }

    public async void clear_token(Geary.AccountInformation account,
                                  Geary.ServiceInformation service,
                                  Cancellable? cancellable)
        throws Error {
        if (service.credentials != null) {
            yield Secret.password_clearv(SecretMediator.schema,
                                         new_attrs(service),
                                         cancellable);

            // Remove legacy formats
            // <= 0.11
            yield Secret.password_clear(
                compat_schema,
                cancellable,
                "user", get_legacy_user(service, account.primary_mailbox.address)
            );
            // <= 0.6
            yield Secret.password_clear(
                compat_schema,
                cancellable,
                "user", get_legacy_user(service, service.credentials.user)
            );
        }
    }

    // Ensure the default collection unlocked.  Try to unlock it since
    // the user may be running in a limited environment and it would
    // prevent us from prompting the user multiple times in one
    // session. See Bug 784300.
    private async void check_unlocked(Cancellable? cancellable)
    throws Error {
        Secret.Service service = yield Secret.Service.get(
            Secret.ServiceFlags.OPEN_SESSION, cancellable
        );
        Secret.Collection? collection = yield Secret.Collection.for_alias(
            service,
            Secret.COLLECTION_DEFAULT,
            Secret.CollectionFlags.NONE,
            cancellable
        );

        // For custom desktop setups, it is possible that the current
        // session has a service responding on DBus but no password
        // keyring. There's no much we can do in this case except just
        // check for the collection being null so we don't crash. See
        // Bug 795328.
        if (collection != null && collection.get_locked()) {
            List<Secret.Collection> to_lock = new List<Secret.Collection>();
            to_lock.append(collection);
            List<DBusProxy> unlocked;
            yield service.unlock(to_lock, cancellable, out unlocked);
            if (unlocked.length() != 0) {
                // XXX
            }
        }
    }

    private async void do_store(Geary.ServiceInformation service,
                                string password,
                                Cancellable? cancellable)
    throws Error {
        yield Secret.password_storev(
            SecretMediator.schema,
            new_attrs(service),
            Secret.COLLECTION_DEFAULT,
            "Geary %s password".printf(service.protocol.to_value()),
            password,
            cancellable
        );
    }

    private HashTable<string,string> new_attrs(Geary.ServiceInformation service) {
        HashTable<string,string> table = new HashTable<string,string>(
            str_hash, str_equal
        );
        table.insert(ATTR_PROTO, service.protocol.to_value());
        table.insert(ATTR_HOST, service.host);
        table.insert(ATTR_LOGIN, service.credentials.user);
        return table;
    }

    private async string? migrate_old_password(Geary.ServiceInformation service,
                                               GLib.Cancellable? cancellable)
        throws GLib.Error {
        // <= 0.11
        string user = get_legacy_user(service, service.credentials.user);
        string? password = yield Secret.password_lookup(
            compat_schema,
            cancellable,
            "user", user
        );

        if (password != null) {
            // Clear the old password
            yield Secret.password_clear(
                compat_schema,
                cancellable,
                "user", user
            );

            // Store it in the new format
            yield do_store(service, password, cancellable);
        }

        return password;
    }

    private string get_legacy_user(Geary.ServiceInformation service, string user) {
        switch (service.protocol) {
        case Geary.Protocol.IMAP:
            return "org.yorba.geary imap_username:" + user;
        case Geary.Protocol.SMTP:
            return "org.yorba.geary smtp_username:" + user;
        default:
            warning("Unknown service type");
            return "";
        }
    }

}
