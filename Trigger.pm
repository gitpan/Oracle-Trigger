package Oracle::Trigger;

# Perl standard modules
use strict;
use warnings;
use Carp;
# use CGI::Carp qw(fatalsToBrowser warningsToBrowser);
# warningsToBrowser(1);
# use CGI;
# use Getopt::Std;
use Debug::EchoMessage;
use DBI;

our $VERSION = 0.1;

require Exporter;
our @ISA         = qw(Exporter);
our @EXPORT      = qw();
our @EXPORT_OK   = qw(get_dbh is_object_exist prepare 
    get_table_definition prepare execute
  );
our %EXPORT_TAGS = (
    all  => [@EXPORT_OK]
);

=head1 NAME

Perl class for creating Oracle triggers

=head1 SYNOPSIS

  use Oracle::Trigger;

  my %cfg = ('conn_string'=>'usr/pwd@db', 'table_name'=>'my_ora_tab');
  my $ot = Oracle::Trigger->new;
  my $sql= $ot->prepare(%cfg); 
  # or combine the two
  my $ot = Oracle::Trigger->new(%cfg);


=head1 DESCRIPTION

This class contains methods to create audit tables and triggers for
Oracle tables.

=cut

=head3 new (conn_string=>'usr/pwd@db',table_name=>'my_table')

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
  $self->{table_name}  = 'my_tab'; # or $self->{tn}  

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

  my $ar = $self->prepare('usr/pwd@db','my_tab');
  $self->execute();

Return: 0|1: 0 - OK; 1 - failed

This method submit the sql statement to Oracle server. 

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

# -----------------------------------------------------------------

=head3 get_dbh($con, $dtp)

Input variables:

  $con - Connection string for
         Oralce: usr/pwd@db (default)
            CSV: /path/to/file
       ODBC|SQL: usr/pwd@DSN[:approle/rolepwd]
  $dtp - Database type: Oracle, CSV, etc

Variables used or routines called:

  DBI
  DBD::Oracle
  Win32::ODBC

How to use:

  $self->get_dbh('usr/pwd@dblk', 'Oracle');
  $self->get_dbh('usr/pwd@dblk:approle/rpwd', 'SQL');

Return: database handler

If application role is provided, it will activate the application role
as well.

=cut

sub get_dbh {
    my $self = shift;
    my ($con, $dtp) = @_;
    # Input variables:
    #   $con  - connection string: usr/pwd@db
    #   $dtp  - database type: Oracle, CSV
    #
    $dtp = 'Oracle' if !$dtp;
    my (@conn, $dsn, $dbh,$msg);
    my ($usr, $pwd, $sid) = ($con =~ /(\w+)\/(\w+)\@(\w+)/i);
    my ($apusr, $appwd) = ($con =~ /:(\w+)\/(\w+)/i);
    if ($dtp =~ /Oracle/i) {
        @conn = ("DBI:Oracle:$sid", $usr, $pwd);
        $dbh=DBI->connect(@conn) ||
            die "Connection error : $DBI::errstr\n";
        $dbh->{RaiseError} = 1;
    } elsif ($dtp =~ /CSV/i) {
        carp "WARN: CSV directory - $con does not exist.\n"
            if (!-d $con);
        @conn = ("DBI:CSV:f_dir=$con","","");
        $dbh=DBI->connect(@conn) ||
            die "Connection error : $DBI::errstr\n";

    } else {   # ODBC or SQL
        $dsn = "DSN=$sid;uid=$usr;pwd=$pwd;";
        $dbh = new Win32::ODBC($dsn);
        if (! $dbh) {
            Win32::ODBC::DumpError();
            $msg = "Could not open connection to DSN ($dsn) ";
            $msg .= "because of [$!]";
            die "$msg";
        }
        if ($apusr) {
            $dbh->Sql("exec sp_setapprole $apusr, $appwd");
        }
    }
    return $dbh;
}

=head3 is_object_exist($dbh,$tn,$tp)

Input variables:

  $dbh - database handler, required.
  $tn  - table/object name, required.
         schema.table_name is allowed.

Variables used or routines called:

  echoMSG    - display messages.

How to use:

  # whether table 'emp' exist
  $yesno = $self->is_object_exist($dbh,'emp');

Return: 0 - the object does not exist;
        1 - the object exist;

=cut

sub is_object_exist {
    my $self = shift;
    my($dbh,$tn, $tp) = @_;
    croak "ERR: could not find database handler.\n"      if !$dbh;
    croak "ERR: no table or object name is specified.\n" if !$tn;
    # get owner name and table name
    my ($sch, $tab, $stb) = ("","","");
    if (index($tn, '.')>0) {
        ($sch, $tab) = ($tn =~ /(\w+)\.([\w\$]+)/);
    }
    my($q,$r);
    $tp = 'TABLE' if ! $tp;
    $stb = 'user_objects';
    $stb = 'all_objects'   if $sch;
    $q  = "SELECT object_name from $stb ";
    $q .= " WHERE object_type = '" . uc($tp) . "'";
    if ($sch) {
        $q .= "   AND object_name = '" . uc($tab) . "'";
        $q .= "   AND owner = '" . uc($sch) . "'";
    } else {
        # $tn =~ s/\$/\\\$/g;
        $q .= "   AND object_name = '" . uc($tn) . "'";
    }
    $self->echoMSG($q, 5);
    my $sth=$dbh->prepare($q) || die  "Stmt error: $dbh->errstr";
       $sth->execute() || die "Stmt error: $dbh->errstr";
    my $n = $sth->rows;
    my $arf = $sth->fetchall_arrayref;
    $r = 0;
    $r = 1             if ($#{$arf}>=0);
    return $r;
}

=head3 get_table_definition($dbh,$tn,$cns,$otp)

Input variables:

  $dbh - database handler, required.
  $tn  - table/object name, required.
         schema.table_name is allowed.
  $cns - column names separated by comma.
         Default is null, i.e., to get all the columns.
         If specified, only get definition for those specified.
  $otp - output array type:
         AR|ARRAY        - returns ($cns,$df1,$cmt)
         AH1|ARRAY_HASH1 - returns ($cns,$df2,$cmt)
         HH|HASH         - returns ($cns,$df3,$cmt)
         AH2|ARRAY_HASH2 - returns ($cns,$df4,$cmt)

Variables used or routines called:

  echoMSG - display messages.

How to use:

  ($cns,$df1,$cmt) = $self->getTableDef($dbh,$table_name,'','array');
  ($cns,$df2,$cmt) = $self->getTableDef($dbh,$table_name,'','ah1');
  ($cns,$df3,$cmt) = $self->getTableDef($dbh,$table_name,'','hash');
  ($cns,$df4,$cmt) = $self->getTableDef($dbh,$table_name,'','ah2');

Return:

  $cns - a list of column names separated by comma.
  $df1 - column definiton array ref in [$seq][$cnn].
    where $seq is column sequence number, $cnn is array
    index number corresponding to column names: 
          0 - cname, 
          1 - coltype, 
          2 - width, 
          3 - scale, 
          4 - precision, 
          5 - nulls, 
          6 - colno,
          7 - character_set_name.
  $df2 - column definiton array ref in [$seq]{$itm}.
    where $seq is column number (colno) and $itm are:
          col - column name
          seq - column sequence number
          typ - column data type
          wid - column width
          max - max width
          min - min width
          dec - number of decimals
          req - requirement: null or not null
          dft - date format
          dsp - description or comments
  $df3 - {$cn}{$itm} when $otp = 'HASH'
    where $cn is column name in lower case and
          $itm are the same as the above
  $df4 - [$seq]{$itm} when $otp = 'AH2'
    where $seq is the column number, and $itm are:
          cname     - column name (col)
          coltype   - column data type (typ)
          width     - column width (wid)
          scale     - column scale (dec)
          precision - column precision (wid for N)
          nulls     - null or not null (req)
          colno     - column sequence number (seq)
          character_set_name - character set name

=cut

sub get_table_definition {
    my $self = shift;
    my($dbh, $tn, $cns, $otp) = @_;
    # Input variables:
    #   $dbh - database handler
    #   $tn  - table name
    #   $cns - column names
    #
    # 0. check inputs
    croak "ERR: could not find database handler.\n" if !$dbh;
    croak "ERR: no table or object name is specified.\n" if !$tn;
    $tn = uc($tn);
    $self->echoMSG("  - reading table $tn definition...", 1);
    $otp = 'ARRAY' if (! defined($otp));
    $otp = uc $otp;
    if ($cns) { $cns =~ s/,\s*/','/g; $cns = "'$cns'"; }
    #
    # 1. retrieve column definitions
    my($q,$msg);
    if (index($tn,'.')>0) {   # it is in schema.table format
        my ($sch,$tab) = ($tn =~ /([-\w]+)\.([-\w]+)/);
        $q  = "  SELECT column_name,data_type,data_length,";
        $q .= "data_scale,data_precision,\n             ";
        $q .= "nullable,column_id,character_set_name\n";
        $msg = "$q";
        $q   .= "        FROM dba_tab_columns\n";
        $msg .= "        FROM dba_tab_columns\n";
        $q   .= "       WHERE owner = '$sch' AND table_name = '$tab'\n";
        $msg .= "       WHERE owner = '$sch' AND table_name = '$tab'\n";
    } else {
        $q  = "  SELECT cname,coltype,width,scale,precision,nulls,";
        $q .= "colno,character_set_name\n";
        $msg = "$q";
        $q   .= "        FROM col\n     WHERE tname = '$tn'";
        $msg .= "        FROM col\n     WHERE tname = '$tn'\n";
    }
    if ($cns) {
        $q   .= "         AND cname in (" . uc($cns) . ")\n";
        $msg .= "         AND cname in (" . uc($cns) . ")\n";
    }
    if (index($tn,'.')>0) {   # it is in schema.table format
        $q   .= "\n    ORDER BY table_name,column_id";
        $msg .= "    ORDER BY table_name, column_id\n";
    } else {
        $q   .= "\n    ORDER BY tname, colno";
        $msg .= "    ORDER BY tname, colno\n";
    }
    $self->echoMSG("    $msg", 2);
    my $sth=$dbh->prepare($q) || croak "ERR: Stmt - $dbh->errstr";
       $sth->execute() || croak "ERR: Stmt - $dbh->errstr";
    my $arf = $sth->fetchall_arrayref;       # = output $df1
    #
    # 2. construct column name list
    my $r = ${$arf}[0][0];
    for my $i (1..$#{$arf}) { $r .= ",${$arf}[$i][0]"; }
    $msg = $r; $msg =~ s/,/, /g;
    $self->echoMSG("    $msg", 5);
    #
    # 3. get column comments
    $q  = "SELECT column_name, comments\n      FROM user_col_comments";
    $q .= "\n     WHERE table_name = '$tn'";
    $msg  = "SELECT column_name, comments\nFROM user_col_comments";
    $msg .= "\nWHERE table_name = '$tn'<p>";
    $self->echoMSG("    $msg", 5);
    my $s2=$dbh->prepare($q) || croak "ERR: Stmt - $dbh->errstr";
       $s2->execute() || croak "ERR: Stmt - $dbh->errstr";
    my $brf = $s2->fetchall_arrayref;
    my (%cmt, $j, $k, $cn);
    for my $i (0..$#{$brf}) {
        $j = lc(${$brf}[$i][0]);             # column name
        $cmt{$j} = ${$brf}[$i][1];           # comments
    }
    #
    # 4. construct output $df2($def) and $df3($df2)
    my $def = bless [], ref($self)||$self;   # = output $df2
    my $df2 = bless {}, ref($self)||$self;   # = output $df3
    for my $i (0..$#{$arf}) {
        $j  = ${$arf}[$i][6]-1;              # column seq number
        ${$def}[$j]{seq} = $j;               # column seq number
        $cn = lc(${$arf}[$i][0]);            # column name
        ${$def}[$j]{col} = uc($cn);          # column name
        ${$def}[$j]{typ} = ${$arf}[$i][1];   # column type
        if (${$arf}[$i][4]) {                # precision > 0
            # it is NUMBER data type
            ${$def}[$j]{wid} = ${$arf}[$i][4];  # column width
            ${$def}[$j]{dec} = ${$arf}[$i][3];  # number decimal
        } else {                             # CHAR or VARCHAR2
            ${$def}[$j]{wid} = ${$arf}[$i][2];  # column width
            ${$def}[$j]{dec} = ""               # number decimal
        }
        ${$def}[$j]{max} = ${$def}[$j]{wid};

        if (${$def}[$j]{typ} =~ /date/i) {   # typ is DATE
            ${$def}[$j]{max} = 17;           # set width to 17
            ${$def}[$j]{wid} = 17;           # set width to 17
            ${$def}[$j]{dft} = 'YYYYMMDD.HH24MISS';
        } else {
            ${$def}[$j]{dft} = '';           # set date format to null
        }
        if (${$arf}[$i][5] =~ /^(not null|N)/i) {
            ${$def}[$j]{req} = 'NOT NULL';
        } else {
            ${$def}[$j]{req} = '';
        }
        if (exists $cmt{$cn}) {
            ${$def}[$j]{dsp} =  $cmt{$cn};
        } else {
            ${$def}[$j]{dsp} = '';
        }
        ${$def}[$j]{min} = 0;
        ${$df2}{$cn}{seq}  = $j;
        ${$df2}{$cn}{col}  = ${$def}[$j]{col};
        ${$df2}{$cn}{typ}  = ${$def}[$j]{typ};
        ${$df2}{$cn}{dft}  = ${$def}[$j]{dft};
        ${$df2}{$cn}{wid}  = ${$def}[$j]{wid};
        ${$df2}{$cn}{dec}  = ${$def}[$j]{dec};
        ${$df2}{$cn}{max}  = ${$def}[$j]{max};
        ${$df2}{$cn}{min}  = ${$def}[$j]{min};
        ${$df2}{$cn}{req}  = ${$def}[$j]{req};
        ${$df2}{$cn}{dsp}  = ${$def}[$j]{dsp};
    }
    #
    # 5. construct output array $df4
    my $df4 = bless [],ref($self)||$self;   # = output $df4
    for my $i (0..$#{$arf}) {
        $j = lc(${$arf}[$i][0]);            # column name
        push @$df4, {cname=>$j,         coltype=>${$arf}[$i][1],
                width=>${$arf}[$i][2],    scale=>${$arf}[$i][3],
            precision=>${$arf}[$i][4],    nulls=>${$arf}[$i][5],
                colno=>${$arf}[$i][6],
            character_set_name=>${$arf}[$i][7]};
    }
    #
    # 6. output based on output type
    if ($otp =~ /^(AR|ARRAY)$/i) {
        return ($r, $arf, \%cmt);      # output ($cns,$df1,$cmt)
    } elsif ($otp =~ /^(AH1|ARRAY_HASH1)$/i) {
        return ($r, $def, \%cmt);      # output ($cns,$df2,$cmt)
    } elsif ($otp =~ /^(HH|HASH)$/i) {
        return ($r, $df2, \%cmt);      # output ($cns,$df3,$cmt)
    } else {
        return ($r, $df4, \%cmt);      # output ($cns,$df4,$cmt);
    }
}

1;

=head1 HISTORY

=over 4

=item * Version 0.1

This version is to test out the functions of Mail classes:
Mail::Box::Message and Mail::Box::Manager.

04/22/2005 (htu) - finished creating DATA trigger rountines.

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


