#!/usr/bin/perl -w
#
# Morgan Jones (morgan@morganjones.org)
# $Id$
#
# Description: general purpose script to convert an ldif from one ldap
# server/schema to another.  you can omit entire entries, transform
# DNs, omit/modify/change attributes, attribute values and
# objectclasses.
#
# There is currently no way to modify different types of entries differently.
#
# The intended use is to convert the entire contents of a legacy
# directory into a newly configured directory.
#
# Usage:
# Dump the contents of the newly configured directory (Centos DS in this case):
#     /usr/lib64/dirsrv/slapd-<instance>/db2ldif -s <base> -a /var/tmp/base.ldif
# Transform the output of the old directory with this script:
#     cat <old_base>_110511.20.49.38.ldif |./convert_ldap.pl > converted.ldif
# Concatenate the converted old directory to the dump of the new directory.  This
#     Does assume that your containers were removed by convert_ldap.pl.
#     cat /var/tmp/base.ldif converted.ldif > /var/tmp/o_msues.ldif
# Stop slapd:
#     /usr/lib64/dirsrv/slapd-<instance>/stop-slapd
# Import the new data:
#     /usr/lib64/dirsrv/slapd-<instance>/ldif2db -s <base> -i /var/tmp/<base>.ldif
# It is normal to get a ton of errors the first few times.  If so, modify 
#     convert_ldap.pl or base.ldif and repeat above.
# 
use strict;

# Pull in a full LDAP entry on each pass of the while loop.
$/="";

sub contains_required_object_classes(@);
sub attr_contains_desired_objectclass($);

# rhs may be a regex in all cases.  Specials much be escaped (\\s*).
# lhs is case insensitive, rhs case will be preserved.

####
####
# Customization begins here.
# Change basedn, 
# lhs: old base
# rhs: new base
# an emptly rhs ("") will result in attribute removal
# my %base_change = ( "ou=people,[^,]+,\\s*o=msu_ag" => "ou=employees,o=msues",
#                     "ou=groups,[^,]+,\\s*o=msu_ag" => "ou=groups,o=msues",
#                     ",\\s+ou=contacts,\\s*o=msues" => ",ou=contacts,o=msues",
#                     "o=msu_ag" => "o=msues"
#                   );

# TODO: uniqemember attributes!
#my %base_change = ( "o=ithaca.edu, o=isp" => "o=Ithaca College,c=US"
my %base_change = ( );

###
# change attribute name(s).
# an emptly rhs ("") will remove the attribute.

    # "benefitcode" => "msuesBenefitcode",
    # "ctcal.*" => "",
    # "datasource"  => "",
my %attr_change = ( 
		   "maildeliveryoption" => "",
		   "mailautoreply.*" => "",
		   "vacation.*" => "",
		   "mailallowedservice.*" => "",
		   "mailmsgquota" => "",
		   "mailquota" => "",
		   "maildeliveryoption" => "",
		   "ns.*" => "",
		   "mgman.*" => "",
		   "datasource" => "",
		   "mailadminrole" => "",
		   "inetmailgroupstatus" => "",
		   "mailforwardingaddress" => "",
		   "multiLineDescription" => "",
		   "adminnumber" => "",
		   "mailmessagestore" => "",
		   "macaddress" => "",
		   "preferredlanguage" => "",
		   "memberof" => "",
		   "mailequivalentaddress" => "",
		   "member" => ""
);

###
# Set values for attributes.  This will not work for multi-value attrbutes (TODO)
#my %attr_set_value = ( "datasource" => "morgan's perl conversion script, 110511" );
my %attr_set_value = ( );

###
# Change the name of one or more objectclasses.
# This conversion is done before @objectclasses and @required_objectclasses are evaluated.
my %objectclass_name_change = (
			      "inetmailgroup" => "mailgroup"
			      );

###
# Add rhs objectclass to any entry with lhs objectclass
my %add_objectclasses = ( "mirapointmailuser" => "icorgperson");

##
# List of objectclasses you want included in an entry
# Remove unwanted indvidual objectclasses but omitting them here.
my @desired_objectclasses = 
    qw/top person organization organizationalPerson organizationalUnit inetOrgPerson  
       groupofuniquenames icorgperson ctcaluser mirapointmailuser groupofUrls mailgroup
      icorganizationalunit ctcalresource groupofnames 
      cosClassicDefinition cosSuperDefinition cosTemplate extensibleObject ldapsubentry 
      nscomplexroledefinitionnsfilteredroledefinition nsroledefinition passwordpolicy
      ctCalAdmin/;

###
# Objectclasses of entries you wish to include
# If the objectclass is here the entry will be included
# If an objectclass here is not also in @desired_objecclasses then the 
#    objectclass itself will be stripped but the entry will be included.
my @required_objectclasses = qw/organization organizationalunit inetorgperson groupofuniquenames 
      groupofUrls mailgroup icorganizationalunit ctcalresource groupofnames
      cosClassicDefinition cosSuperDefinition cosTemplate extensibleObject ldapsubentry 
      nscomplexroledefinitionnsfilteredroledefinition nsroledefinition passwordpolicy
      ctCalAdmin/;

###
# These bases and anything below in the directory will be ignored.  
# This is aft any conversion above so if you "ignore" ou=people,o=base but  convert o=domain.com,ou=people,o=base 
#     to ou=employees,o=base it will not be excluded but uid=something,ou=people,o=base will be ignored.
# This is after any conversion above so 
#     if you "ignore" ou=people,o=base but  
#     convert o=domain,ou=people,o=base ou=employees,o=base 
#     the new ou=employees,o=base will be included.
my @bases_to_ignore = ( "uid=ServiceAdmin,ou=People,o=ithaca.edu, o=isp",
			"o=ida,o=isp",
			"uid=msg-admin[^\,]+, ou=People, o=ithaca.edu, o=isp",
			"uid=junk,ou=people,o=ithaca.edu,o=isp", 
		      );

# customization ends here.
####
####

for my $b (@bases_to_ignore) {
    $b =~ s/\s+,/,/g;
    $b =~ s/\,\s+/,/g;
}



while(<>) {
    # Create a single line out of LDIF continued lines.
    s/\n\s+//g;

    my @l = split /\n/;

    my $dn;
    # find the dn, skip an extraneous contents above (# get rid of version: 1 and #entry-id: num)
    do {
        $dn = shift @l;
    } until ($#l<0 || $dn =~ /^dn:/);

    $dn =~ s/\s+,/,/g;
    $dn =~ s/\,\s+/,/g;

    # often comments are set out alone in LDIF and the above do while strips them leaving nothing.
    next if ($#l<0);

    for my $k (keys %base_change) {
        $dn =~ s/$k$/$base_change{$k}/i;
    }

    my $skip_base = 0;
    for my $b (@bases_to_ignore) { $skip_base=1 if ($dn =~ /$b\s*$/i); }
    next if ($skip_base);

    # the meat of the changes
    map {
        for my $oc (keys %objectclass_name_change) {
            s/(objectclass:)\s*$oc/$1 $objectclass_name_change{$oc}/i;
        }

        # we strip entries and objectclasses by removing the name
        # here.  Perl arrayes are immutable so a new array must be
        # created (below to actually strip entries.  We mark them for
        # later removal by leaving them /^:/ (starting with a ':').
        s/^objectclass:/:/i 
            if (/^objectclass:/i && !attr_contains_desired_objectclass($_));

        # change attributes.  Note that it's normal for attributes to end up /^:/--see note above.
        for my $k (keys %attr_change) {
            s/^$k:/$attr_change{$k}:/i
        }

        # change attribute values
        for my $k (keys %attr_set_value) {
            s/$k:.*/$k: $attr_set_value{$k}/;
        }
    } @l;

    for my $k (keys %add_objectclasses) {
        push @l, "objectclass: " . $add_objectclasses{$k}
            if (grep /objectclass:\s*$k/i, @l &&
		!grep /objectclass:\s*$add_objectclasses{$k}/i, @l);
    }

    # TODO: IC hack, add general config later
    push @l, "objectclass: icorgguest"
      if ($dn =~ /\,\s*ou=guests\,\s*/i);
    $dn =~ s/cn=#/cn=/;

    # skip entire entries unless they're in our list of required objectclasses.
    next unless contains_required_object_classes(@l);

    # find and remave any attributes whose name was left null.
    my @pl;
    for (@l) {
        push @pl, $_ unless /^:/;
    }

    print "\n\n$dn\n",
        join "\n", @pl;
    
}
print "\n";



# Subroutines
######
sub contains_required_object_classes(@) {
    my @e = @_;
    
    for my $oc (@required_objectclasses) {
        return 1 if (grep /objectclass:\s*$oc/i, @e);
    }
    return 0;
}

######
sub attr_contains_desired_objectclass($) {
    my $e = shift;

    my $oc = (split/:\s*/, $e)[1];

    for my $doc (@desired_objectclasses) {
        if (lc $oc eq lc $doc) {
            return 1;
        }
    }

    return 0;
}
