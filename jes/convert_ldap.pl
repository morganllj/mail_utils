#!/usr/bin/perl -w
#
# Morgan Jones (morgan@morganjones.org)
# Description: general purpose script to convert an ldif from one ldap server/schema to another.
#  you can omit entire entries, transform DNs, omit/modify/change attributes, attribute values and objectclasses.
# There is currently no way to modify different types of entries differently.
#
# Usage:
# /usr/lib64/dirsrv/slapd-<instance>/db2ldif -s o=msues -a /var/tmp/base.ldif
# cat o_msu_ag_110511.20.49.38.ldif |./convert_ldap_base.pl > converted.ldif
# cat /var/tmp/base.ldif converted.ldif > /var/tmp/o_msues.ldif
# /usr/lib64/dirsrv/slapd-<instance>/stop-slapd
# /usr/lib64/dirsrv/slapd-<instance>/ldif2db -s o=msues -i /var/tmp/o_msues.ldif
# 
use strict;

$/="";

sub contains_required_object_classes(@);
sub attr_contains_desired_objectclass($);

# Change basedn, rhs may be a regex.  You may have as many as you like.
# lhs: old base
# rhs: new base
# null rhs ("") will result in attribute removal
# lhs is case insensitive, rhs case will be preserved.
my %base_change = ( "ou=people,[^,]+,o=msu_ag" => "ou=employees,o=msues",
                    ",\\s+ou=contacts,o=msues" => ",ou=contacts,o=msues",
                    "o=msu_ag" => "o=msues"
                  );

# change attribute name(s).
# a lhs of "" will remove the attribute.
my %attr_change = ( "datasource"  => "",
                    "focusarea" => "msuesFocusArea",
                    "programarea" => "msuesProgramArea",
                    "terminated"  => "msuesTerminated",
                    "titlecode"   => "msuesTitlecode",
                    "benefitcode" => "msuesBenefitcode",
                    "employeetype" => "msuesEmployeetype",
                    "mafesemployee" => "msuesMafesFte",
                    "secondaryDept" => "msuesSecondaryDept",
                    "mafesemployee" => "msuesMafesfte",
                    "msuesemployee" => "msuesFte",
                    "msuemployee" => "msuesMsuFte",
                    "homeorgn" => "msuesHomeorgn",
                    "inetcos" => "",
                    "memberof" => "",
                    "employeeclass" => "msuesEmployeeClass",
                    "employeepidm" => "msuesEmployeePidm",
                    "mailhost" => "",
                    "maildeliveryoption" => "",
                    "mailsieverulesource" => "",
                    "vacation.*" => "",
                    "mailautoreply.*" => "",
                    "mailforwardingaddress" => "",
                    "mailalternateaddress" => "",
                    "mailmsgquota" => "",
                    "maildeferprocessing" => "",
                    "inetuserstatus" => "",
                    "iplanet-am-modifiable-by" => "",
                    "mailuserstatus" => "",
                    "mailquota" => "",
                    "nsdacapability" => "",
                    "paburi" => "",
                    "preferredLocale" => "",
                    "psincludeingab" => "",
                    "ctcal.*" => "",
                    "nswmExtendedUserPrefs" => "",
                    "sunUC.*" => "",
                    "sunAbExtendedUserPrefs" => "",
                    "preferredLanguage" => "",
                    "psRoot" => "",
                    "ics.*" => "",
                    "nsuniqueid" => ""
                  );

# attributes for which you'd like to set a value, if any.
#my %attr_set_value = ( "datasource" => "morgan's perl conversion script, 110511" );
my %attr_set_value = ( );

# change the name of one or more objectclasses.
# this conversion is done before @objectclasses and @required_objectclasses are evaluated.
my %objectclass_name_change = ( "extPerson" => "msuesEmployee" );

# add the rhs objectclass to any entry with the lhs objectclass
my %add_objectclasses = ("msuesEmployee" => "msuesMailPerson" );
    
# remove unwanted objectclasses but omitting them here.  This is a list of objectclasses you want included in an entry.
my @desired_objectclasses = 
    qw/top person organizationalPerson inetOrgPerson posixAccount shadowAccount account sambaSamAccount msuesEmployee posixgroup/;

# This is how you control entire ldap entries that should be included/excluded.  If the objectclass is here the entry will be 
#     included.  If you don't also include objectclasses here in @desired_objecclasses then the objectclass itself will be 
#     stripped but the entry will be included.
# These should be a subset of @desired_objectclasses
#my @required_objectclasses = qw/msuesperson/;
my @required_objectclasses = qw/inetorgperson posixgroup groupofuniquenames/;

# The base and anything below it will be ignored.  
# This is post any conversion above so if you "ignore" ou=people,o=base but  convert o=domain.com,ou=people,o=base 
#     to ou=employees,o=base it will not be excluded but uid=something,ou=people,o=base will   
my @bases_to_ignore = ("o=Business,o=msues", "ou=People,o=msues");

while(<>) {
    s/\n\s+//g;

    my @l = split /\n/;
    my $dn;
    
    do {
        $dn = shift @l;
    } until ($#l<0 || $dn =~ /^dn:/);  # get rid of version: 1 and #entry-id: num
    
    next if ($#l<0);

    for my $k (keys %base_change) {
        $dn =~ s/$k$/$base_change{$k}/i;
    }

    my $skip_base = 0;
    for my $b (@bases_to_ignore) { $skip_base=1 if ($dn =~ /$b\s*$/i); }
    next if ($skip_base);

    map {
        for my $oc (keys %objectclass_name_change) {
            s/(objectclass:)\s*$oc/$1 $objectclass_name_change{$oc}/i;
        }

        s/^objectclass:/:/i 
            if (/^objectclass:/i && !attr_contains_desired_objectclass($_));

        for my $k (keys %attr_change) {
            s/^$k:/$attr_change{$k}:/i
        }

        for my $k (keys %attr_set_value) {
            s/$k:.*/$k: $attr_set_value{$k}/;
        }
    } @l;

    for my $k (keys %add_objectclasses) {
        push @l, "objectclass: " . $add_objectclasses{$k}
            if (grep /objectclass:\s*$k/i, @l);
    }

    next unless contains_required_object_classes(@l);

    my @pl;
    for (@l) {
        push @pl, $_ unless /^:/;
    }

    print "\n\n$dn\n",
        join "\n", @pl;
    
}
print "\n";


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
