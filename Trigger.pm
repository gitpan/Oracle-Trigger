package Oracle::Trigger;

# Perl standard modules
use strict;
use warnings;
use Carp;
# use CGI::Carp qw(fatalsToBrowser warningsToBrowser);
# warningsToBrowser(1);
# use CGI;
# use Getopt::Std;
use DBI;
use Debug::EchoMessage;
use Oracle::DML::Common qw(:db_conn :table);

require 5.003;
$Oracle::Trigger::VERSION = 0.2;

require Exporter;
our @ISA         = qw(Exporter);
our @EXPORT      = qw();
our @EXPORT_OK   = qw( prepare execute
    );
our %EXPORT_TAGS = (
    all  => [@EXPORT_OK]
    );
our @IMPORT_OK   = qw(
    get_dbh is_object_exist get_table_definition 
    debug echoMSG disp_param
    );

=head1 NAME

Oracle::Trigger - Perl class for creating Oracle triggers

=head1 SYNOPSIS

  use Oracle::Trigger;

  my %cfg = ('conn_string'=>'usr/pwd@db', 'table_name'=>'my_ora_tab');
  my $ot = Oracle::Trigger->new;
  # or combine the two together
  my $ot = Oracle::Trigger->new(%cfg);
  my $sql= $ot->prepare(%cfg); 
  $ot->execute();    # actually create the audit table and trigger


=head1 DESCRIPTION

This class contains methods to create audit tables and triggers for
Oracle tables.

=cut

=head2 new (conn_string=>'usr/pwd@db',table_name=>'my_table')

Input variables:

  $cs  - Oracle connection string in usr/pwd@db
  $tn  - Oracle table name without schema

Variables used or routines called:

  None

How to use:

   my $obj = new Oracle::Trigger;      # or
   my $obj = Oracle::Trigger->new;     # or
   my $cs  = 'usr/pwd@db';
   my $tn  = 'my_table'; 
   my $obj = Oracle::Trigger->new(cs=>$cs,tn=>$tn); # or
   my $obj = Oracle::Trigger->new('cs',$cs, 'tn',$tn); 

Return: new empty or initialized Oracle::Trigger object.

This method constructs a Perl object and capture any parameters if
specified. It creates and defaults the following variables:
 
  $self->{conn_string} = "";       # or $self->{cs}
  $self->{table_name}  = "";       # or $self->{tn}  

=cut

sub new {
    my $caller        = shift;
    my $caller_is_obj = ref($caller);
    my $class         = $caller_is_obj || $caller;
    my $self          = bless {}, $class;
    my %arg           = @_;   # convert rest of inputs into hash array
    foreach my $k ( keys %arg ) {
        if ($caller_is_obj) {
            $self->{$k} = $caller->{$k};
        } else {
            $self->{$k} = $arg{$k};
        }
    }
    my $vs = 'conn_string,table_name,cs,tn';
    foreach my $k (split /,/, $vs) {
        $self->{$k} = ""        if ! exists $arg{$k};
        $self->{$k} = $arg{$k}  if   exists $arg{$k};
    }
    my $cs1 = $self->{conn_string};
    my $tn1 = $self->{table_name};
    $self->{cs} = ($cs1)?$cs1:$self->{cs};
    $self->{tn} = ($tn1)?$tn1:$self->{tn};
    $self->{conn_string} = ($self->{cs})?$self->{cs}:$cs1;
    $self->{table_name}  = ($self->{tn})?$self->{tn}:$tn1;
    return $self;
}

=head1 METHODS

The following are the common methods, routines, and functions 
defined in this classes.

=head2 Exported Tag: All 

The I<:all> tag includes all the methods or sub-rountines 
defined in this class. 

  use Oracle::Trigger qw(:all);

It includes the following sub-routines:
=head3 prepare($cs, $tn, $tp)

Input variables:

  $cs  - Oracle connection string in usr/pwd@db
  $tn  - Oracle table name without schema
  $tp  - trigger type
         DATA - trigger to audit a table. This is the default.

Variables used or routines called:

  Debug::EchoMessage
    echoMSG - display message
  {cs} - connection string
  {tn} - table name 
  {drop_audit}   - whether to drop audit table if it exists
  {audit_table}  - audit table name, default to aud${$tn}
  {trigger_name} - trigger name, default to trg${$tn}

How to use:

  my $ar = $self->prepare('usr/pwd@db','my_tab');

Return: $hr - a hash array ref containing the following keys:

  dbh         - the database handler
  sql_audit   - SQL statement for creating the audit table
  sql_trigger - SQL statement for creating the trigger

This method performs the following tasks:

  1) create a database handler
  2) check the existance of the table 
  3) generate script for creating audit table
  4) generate script for creating trigger

And it sets the following internal variable as well:

  {dbh} - database handler
  {sql_audit} - sql statements to create audit table
  {sql_trigger} - sql statement to create trigger

=cut

sub prepare {
    my $s = shift;
    my ($cs, $tn, $tp) = @_;
    $s->echoMSG("+++ Preparing SQL statement +++",1);
    #
    # 0. check inputs
    $s->echoMSG("0 - checking inputs...", 1);
    $cs = $s->{cs} if !$cs;
    $tn = $s->{tn} if !$tn;
    $s->echoMSG("Connection string is not specified.", 1) if ! $cs;
    $s->echoMSG("Table name is not specified.", 1)        if ! $tn;
    my %r = ();    # result hash 
    return \%r                                       if !$cs || !$tn;
    $s->echoMSG("CS=$cs\nTN=$tn",3);
    $s->echoMSG("ARGV: @ARGV",3);
    #
    # 1. create and save database handler
    $s->echoMSG("1 - creating database handler...", 1);
    my $dbh = $s->get_dbh($cs,'Oracle');
    $s->{dbh} = $dbh; 
    #
    # 2. check the existence of the table
    $s->echoMSG("2 - checking the existence of table $tn...", 1);
    my $tex = $s->is_object_exist($dbh,$tn);
    $s->echoMSG("Table $tn: could not be found.", 1) if ! $tex;
    return \%r                                       if ! $tex;
    #
    # 3. generate SQL for creating audit table
    $s->echoMSG("3 - generating SQL for creating audit table...", 1);
    my ($aud, $trg, $sql, $msg, $drop) = (0,0,0,0,0);
        $aud = $s->{audit_table} if exists $s->{audit_table};
        $aud = "AUD\$$tn"        if ! $aud; 
    $r{$aud} = bless [], ref($s);
    # 3.1 check whether $aud table exist
    $tex = $s->is_object_exist($dbh,$aud);
    $drop = $s->{drop_audit} if exists $s->{drop_audit}; 
    $s->{create_audit} = 1;
    if ($tex) {
        $sql = "DROP TABLE $aud";
        if ($drop) { 
            push @{$r{$aud}}, $sql; 
            $msg = "   Audit table $aud will be dropped ";
            $msg .= "before being created.";
        } else {
            $msg = "   Audit table $aud exists and ";
            $msg .= "will not be created.";
            $s->{create_audit} = 0;
        }
        $s->echoMSG($msg, 2);
    } else {
        $s->echoMSG("    Audit table $aud does not exist.", 2);
    }
    $sql  = "CREATE TABLE $aud AS \n  SELECT * \n    FROM $tn \n";
    $sql .= "   WHERE 1=0";
    push @{$r{$aud}}, $sql; 
    $sql  = "ALTER TABLE $aud ADD (\n  audit_action CHAR(3),\n";
    $sql .= "  audit_dtm DATE,\n  audit_user VARCHAR2(30)\n  )";
    push @{$r{$aud}}, $sql; 
    $s->{sql_audit} = $r{$aud}; 
    #
    # 4. generate SQL for creating trigger
    $s->echoMSG("4 - generating SQL for creating trigger...", 1);
    $s->{create_trigger} = 1;
    $trg = $s->{trigger_name} if exists $s->{trigger_name};
    $trg = "TRG\$$tn"         if ! $trg; 
    $s->echoMSG("    Trigger $trg will be created or replaced.", 2);
    $r{$trg} = bless [], ref($s);
    # 4.1 get table definition 
    #   $cns - a list of column names separated by comma
    #   $cda - column definition array in ${$cda}[$i]{$cn}
    my ($cns, $cda, $cmt) = $s->get_table_definition($dbh,$tn,'','ah1');
    # 4.2 compose the columns
    my ($c1, $c2, $c3);
    foreach my $c (split /,/, $cns) {
        $c = uc $c;
        $c1 .= "      $c,\n"; 
        $c2 .= "      :new.$c,\n"; 
        $c3 .= "      :old.$c,\n";
    }
    $c1 .= "      AUDIT_ACTION,\n      AUDIT_DTM,\n      AUDIT_USER"; 
    $c2 .= "      v_operation, \n      SYSDATE,  \n      USER";
    $c3 .= "      v_operation, \n      SYSDATE,  \n      USER";
    # 4.3 compose the sql statement
    $sql  = "CREATE OR REPLACE TRIGGER $trg\n";
    $sql .= "  AFTER INSERT OR DELETE OR UPDATE ON $tn\n";
    $sql .= "  FOR EACH ROW\n";
    $sql .= "DECLARE\n  v_operation VARCHAR2(10) := NULL;\n";
    $sql .= "BEGIN\n  IF INSERTING THEN\n    v_operation := 'INS';\n";
    $sql .= "  ELSIF UPDATING THEN\n    v_operation := 'UPD';\n";
    $sql .= "  ELSE\n    v_operation := 'DEL';\n  END IF;\n";
    $sql .= "  IF INSERTING OR UPDATING THEN\n";
    $sql .= "    INSERT INTO $aud (\n$c1\n    ) VALUES (\n";
    $sql .= "$c2\n    );\n";
    $sql .= "  ELSE\n"; 
    $sql .= "    INSERT INTO $aud (\n$c1\n    ) VALUES (\n";
    $sql .= "$c3\n    );\n";
    $sql .= "  END IF;\nEND;\n";
    push @{$r{$trg}}, $sql; 
    $s->{sql_trigger} = $r{$trg}; 
    return \%r;
}

=head3 execute($typ)

Input variables:

  $typ - action type:
         TRIGGER - create trigger only 
         AUDIT   - create audit table only
         default - null and will create both

Variables used or routines called:

  {dbh} - database handler
  {sql_audit} - sql statements to create audit table
  {sql_trigger} - sql statement to create trigger

How to use:

  my $status = $self->execute();
  $self->execute();

Return: 0|1: 0 - OK; 1 - failed

This method submits the sql statement to Oracle server to create
audit table or trigger or both. The default is to create both. 
If the audit table exists, it will skip creating the audit table. You 
either need to manually drop the table or set {drop_audit} to '1'
before you run prepare(). 

=cut

sub execute {
    my $s = shift;
    my ($tp) = @_;
    $tp = 'both' if ! $tp;
    $s->echoMSG("+++ Executing SQL statement +++",1);
    $s->echoMSG("1 - getting variables...", 1);
    my $dbh = $s->{dbh};
    my $aud = $s->{sql_audit};
    my $trg = $s->{sql_trigger}; 
    my $crt_aud = $s->{create_audit};
    my $crt_trg = $s->{create_trigger};
    # $s->disp_param($aud);
    # $s->disp_param($trg);
    $s->echoMSG("2 - executing SQL statement...", 1);
    my @a = ();
    if ($tp && $tp =~ /^(aud|both)/i && $crt_aud) {
        $s->echoMSG("    creating audit table...", 2);
        push @a, @$aud;
    } else {
        $s->echoMSG("    creating audit table: skipped.", 2);
    } 
    if ($tp && $tp =~ /^(tri|both)/i && $crt_trg) {
        $s->echoMSG("    creating trigger...", 2);
        push @a, @$trg; 
    } else {
        $s->echoMSG("    creating trigger: skipped.", 2);
    }
    $s->echoMSG("No SQL statements.", 1) if ! @a;
    foreach my $q (@a) {
        $s->echoMSG($q, 5);
        my $s1=$dbh->prepare($q) || croak "ERR: Stmt - $dbh->errstr";
        $s1->execute() || croak "ERR: Stmt - $dbh->errstr";
    }
    return 0;
}

1;

=head1 HISTORY

=over 4

=item * Version 0.1

This version is to test the procedures and create DATA trigger.

04/22/2005 (htu) - finished creating DATA trigger rountines.

=item * Version 0.2

04/29/2005 (htu) - modified some descriptions and moved the common
routines to Oracle::DML::Common.

=cut

=head1 SEE ALSO (some of docs that I check often)

Data::Describe, Oracle::Loader, CGI::Getopt, File::Xcopy,
perltoot(1), perlobj(1), perlbot(1), perlsub(1), perldata(1),
perlsub(1), perlmod(1), perlmodlib(1), perlref(1), perlreftut(1).

=head1 AUTHOR

Copyright (c) 2005 Hanming Tu.  All rights reserved.

This package is free software and is provided "as is" without express
or implied warranty.  It may be used, redistributed and/or modified
under the terms of the Perl Artistic License (see
http://www.perl.com/perl/misc/Artistic.html)

=cut


