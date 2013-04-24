/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Imap.Capabilities : Geary.GenericCapabilities {
    public const string IDLE = "IDLE";
    public const string STARTTLS = "STARTTLS";
    public const string XLIST = "XLIST";
    public const string COMPRESS = "COMPRESS";
    public const string DEFLATE_SETTING = "DEFLATE";
    
    public const string NAME_SEPARATOR = " ";
    public const string? VALUE_SEPARATOR = null;
    
    public int revision { get; private set; }
    
    /**
     * Creates an empty set of capabilities.  revision represents the different variations of
     * capabilities that an IMAP session might offer (i.e. changes after login or STARTTLS, for
     * example).
     */
    public Capabilities(int revision) {
        base (NAME_SEPARATOR, VALUE_SEPARATOR);
        
        this.revision = revision;
    }

    public bool add_parameter(StringParameter stringp) {
        return parse_and_add_capability(stringp.value);
    }

    public override string to_string() {
        return "#%d: %s".printf(revision, base.to_string());
    }
}

