/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.Imap.EmailIdentifier : Geary.EmailIdentifier {
    public override int64 ordering { get; protected set; }
    
    public Imap.UID uid { get; private set; }
    
    public override Geary.EmailIdentifier next() {
        return new Geary.Imap.EmailIdentifier(new Imap.UID((uid.value + 1).clamp(1, uint32.MAX)));
    }
    
    public override Geary.EmailIdentifier previous() {
        return new Geary.Imap.EmailIdentifier(new Imap.UID((uid.value - 1).clamp(1, uint32.MAX)));
    }
    
    public EmailIdentifier(Imap.UID uid) {
        this.uid = uid;
        ordering = uid.value;
    }
    
    public override bool equals(Equalable o) {
        Geary.Imap.EmailIdentifier? other = o as Geary.Imap.EmailIdentifier;
        if (other == null)
            return false;
        
        if (this == other)
            return true;
        
        return uid.value == other.uid.value;
    }
    
    public override string to_string() {
        return uid.to_string();
    }
}

