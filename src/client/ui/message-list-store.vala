/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MessageListStore : Gtk.TreeStore {
    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.ENVELOPE | Geary.Email.Field.PROPERTIES;
    
    public const Geary.Email.Field WITH_PREVIEW_FIELDS =
        Geary.Email.Field.ENVELOPE | Geary.Email.Field.PROPERTIES | Geary.Email.Field.PREVIEW;
    
    public enum Column {
        MESSAGE_DATA,
        MESSAGE_OBJECT,
        N_COLUMNS;
        
        public static Column[] all() {
            return {
                MESSAGE_DATA,
                MESSAGE_OBJECT
            };
        }
        
        public static Type[] get_types() {
            return {
                typeof (FormattedMessageData), // MESSAGE_DATA
                typeof (Geary.Conversation)    // MESSAGE_OBJECT
            };
        }
        
        public string to_string() {
            switch (this) {
                case MESSAGE_DATA:
                    return "data";
                case MESSAGE_OBJECT:
                    return "envelope";
                
                default:
                    assert_not_reached();
            }
        }
    }
    
    public MessageListStore() {
        set_column_types(Column.get_types());
        set_default_sort_func(sort_by_date);
        set_sort_column_id(TreeSortable.DEFAULT_SORT_COLUMN_ID, Gtk.SortType.DESCENDING);
    }
    
    // The Email should've been fetched with REQUIRED_FIELDS.
    public void append_conversation(Geary.Conversation conversation) {
        Gtk.TreeIter iter;
        append(out iter, null);
        
        Gee.SortedSet<Geary.Email>? pool = conversation.get_pool_sorted(compare_email);
        
        if (pool != null && pool.size > 0)
            set(iter,
                Column.MESSAGE_DATA, new FormattedMessageData.from_email(pool.first(), pool.size, 
                    conversation.is_unread()),
                Column.MESSAGE_OBJECT, conversation
            );
    }
    
    // Updates a converstaion.
    // only_update_flags: if true, we'll only update the read/unread status
    public void update_conversation(Geary.Conversation conversation, bool only_update_flags = false) {
        debug("update conversation. is unread: %s", conversation.is_unread() ? "yes" : "no");
        Gtk.TreeIter iter;
        if (!find_conversation(conversation, out iter)) {
            // Unknown conversation, attempt to append it.
            append_conversation(conversation);
            
            return;
        }
        
        Gee.SortedSet<Geary.Email>? pool = conversation.get_pool_sorted(compare_email);
        if (pool == null) {
            // empty conversation, remove from store
            remove_conversation(conversation);
            
            return;
        }
        
        Geary.Email preview = pool.first();
        
        FormattedMessageData? existing = null;
        get(iter, Column.MESSAGE_DATA, out existing);
        
        // Update preview if text or unread status changed.
        if (existing != null && existing.is_unread != conversation.is_unread()) {
            existing.is_unread = conversation.is_unread();
            set(iter, Column.MESSAGE_DATA, existing);
        }
        
        if (!only_update_flags && (existing == null || !existing.email.id.equals(preview.id))) {
            set(iter, Column.MESSAGE_DATA, new FormattedMessageData.from_email(preview, pool.size,
                conversation.is_unread()));
        }
    }
    
    public void remove_conversation(Geary.Conversation conversation) {
        Gtk.TreeIter iter;
        if (!find_conversation(conversation, out iter)) {
            // unknown, nothing to do here
            return;
        }
        
        remove(iter);
    }
    
    public bool has_conversation(Geary.Conversation conversation) {
        int count = get_count();
        for (int ctr = 0; ctr < count; ctr++) {
            if (conversation == get_conversation_at_index(ctr))
                return true;
        }
        
        return false;
    }
    
    public Geary.Conversation? get_conversation_at_index(int index) {
        return get_conversation_at(new Gtk.TreePath.from_indices(index, -1));
    }
    
    public Geary.Email? get_email_for_preview(int index, out Geary.Conversation? conversation) {
        conversation = get_conversation_at_index(index);
        if (conversation == null)
            return null;
        
        Gee.SortedSet<Geary.Email>? pool = conversation.get_pool_sorted(compare_email);
        if (pool == null)
            return null;
        
        // If it exists, return oldest unread message.
        foreach (Geary.Email email in pool)
            if (email.properties.email_flags.is_unread())
                return email;
        
        // All e-mail was read, so return the newest one.
        return pool.last();
    }
    
    public void set_preview_for_conversation(Geary.Conversation conversation, Geary.Email email) {
        Gtk.TreeIter iter;
        if (!find_conversation(conversation, out iter)) {
            debug("Unable to find conversation for preview %s", email.id.to_string());
            
            return;
        }
        
        set(iter, Column.MESSAGE_DATA, new FormattedMessageData.from_email(email, 
            conversation.get_usable_count(), conversation.is_unread()));
    }
    
    public int get_count() {
        return iter_n_children(null);
    }
    
    public Geary.Conversation? get_conversation_at(Gtk.TreePath path) {
       Gtk.TreeIter iter;
        if (!get_iter(out iter, path))
            return null;
        
        Geary.Conversation? conversation;
        get(iter, Column.MESSAGE_OBJECT, out conversation);
        
        return conversation;
    }
    
    public Geary.EmailIdentifier? get_email_id_lowest() {
        Geary.EmailIdentifier? low = null;
        int count = get_count();
        for (int ctr = 0; ctr < count; ctr++) {
            Geary.Conversation c = get_conversation_at_index(ctr);
            Gee.SortedSet<Geary.Email>? mail = c.get_pool_sorted(compare_email_id_desc);
            if (mail == null)
                continue;
            
            Geary.EmailIdentifier pos = mail.first().id;
            if (low == null || pos.ordering < low.ordering)
                low = pos;
        }
        
        return low;
    }
    
    public void update_flags(Geary.EmailIdentifier id, Geary.EmailFlags flags) {
        int count = get_count();
        for (int ctr = 0; ctr < count; ctr++) {
            Geary.Conversation c = get_conversation_at_index(ctr);
            Gee.SortedSet<Geary.Email>? mail = c.get_pool_sorted(compare_email_id_desc);
            if (mail == null)
                continue;
            
            foreach (Geary.Email e in mail) {
                if (e.id.equals(id)) {
                    e.properties.email_flags = flags;
                    update_conversation(c, true);
                    
                    return;
                }
            }
        }
    }
    
    private bool find_conversation(Geary.Conversation conversation, out Gtk.TreeIter iter) {
        iter = Gtk.TreeIter();
        int count = get_count();
        for (int ctr = 0; ctr < count; ctr++) {
            if (conversation == get_conversation_at_index(ctr))
                return get_iter(out iter, new Gtk.TreePath.from_indices(ctr, -1));
        }
        
        return false;
    }
    
    private int sort_by_date(Gtk.TreeModel model, Gtk.TreeIter aiter, Gtk.TreeIter biter) {
        Geary.Conversation a, b;
        
        get(aiter, Column.MESSAGE_OBJECT, out a);
        get(biter, Column.MESSAGE_OBJECT, out b);
        
        Gee.SortedSet<Geary.Email>? apool = a.get_pool_sorted(compare_email);
        Gee.SortedSet<Geary.Email>? bpool = b.get_pool_sorted(compare_email);
        
        if (apool == null || apool.first() == null)
            return -1;
        else if (bpool == null || bpool.first() == null)
            return 1;
        
        return compare_email(apool.first(), bpool.first());
    }
}

