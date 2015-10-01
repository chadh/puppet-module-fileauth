fileauth puppet module

In the environment this was designed for, host authorization (not
authentication) is controlled by passwd files, and group membership is also
tracked in the group file (as opposed to ldap or something else).
`/etc/passwd` on each host is created by combining a set of entries local to a
host with a set of entries managed by our user management system.  This module
ensures that the scripts responsible for managing the passwd and group files
are correct.