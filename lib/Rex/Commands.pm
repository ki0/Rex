#
# (c) Jan Gehring <jan.gehring@gmail.com>
#
# vim: set ts=2 sw=2 tw=0:
# vim: set expandtab:

=head1 NAME

Rex::Commands - All the basic commands

=head1 DESCRIPTION

This module is the core commands module.

=head1 SYNOPSIS

 desc "Task description";
 
 task "taskname", sub { ... };
 task "taskname", "server1", ..., "server20", sub { ... };
 
 group "group" => "server1", "server2", ...;
 
 user "user";
 
 password "password";
 
 environment live => sub {
   user "root";
   password "foobar";
   pass_auth;
   group frontend => "www01", "www02";
 };



=head1 COMMANDLIST

=over 4

=item * Cloud Management L<Rex::Commands::Cloud>

=item * Cron Management L<Rex::Commands::Cron>

=item * Database Commands L<Rex::Commands::DB>

=item * SCP Up- and Download L<Rex::Commands::Upload>, L<Rex::Commands::Download>

=item * File Manipulation L<Rex::Commands::File>

=item * Filesystem Manipulation L<Rex::Commands::Fs>

=item * Information Gathering L<Rex::Commands::Gather>

=item * Manipulation of /etc/hosts L<Rex::Commands::Host>

=item * Get an inventory of your Hardware L<Rex::Commands::Inventory>

=item * Manage your iptables rules L<Rex::Commands::Iptables>

=item * Kernel Commands L<Rex::Commands::Kernel>

=item * LVM Commands L<Rex::Commands::LVM>

=item * Package Commands L<Rex::Commands::Pkg>

=item * Process Management L<Rex::Commands::Process>

=item * Rsync Files L<Rex::Commands::Rsync>

=item * Run Remote Commands L<Rex::Commands::Run>

=item * Manage System Services (sysvinit) L<Rex::Commands::Service>

=item * Sysctl Commands L<Rex::Commands::Sysctl>

=item * Live Tail files L<Rex::Commands::Tail>

=item * Manage user and group accounts L<Rex::Commands::User>

=item * Manage your virtual environments L<Rex::Commands::Virtualization>

=back

=head1 EXPORTED FUNCTIONS

=over 4

=cut

package Rex::Commands;

use strict;
use warnings;

require Rex::Exporter;
use Rex::TaskList;
use Rex::Logger;
use Rex::Config;
use Rex::Profiler;
use Rex::Report;
use Rex;

use vars
  qw(@EXPORT $current_desc $global_no_ssh $environments $dont_register_tasks $profiler);
use base qw(Rex::Exporter);

@EXPORT = qw(task desc group
  user password port sudo_password public_key private_key pass_auth key_auth krb5_auth no_ssh
  get_random batch timeout max_connect_retries parallelism
  do_task run_task run_batch needs
  exit
  evaluate_hostname
  logging
  include
  say
  environment
  LOCAL
  path
  set
  get
  before after around
  logformat log_format
  sayformat say_format
  connection
  auth
  FALSE TRUE
  set_distributor
  set_executor_for
  template_function
  report
  make
  source_global_profile
  last_command_output
  case
  inspect
  tmp_dir
  cache
);

our $REGISTER_SUB_HASH_PARAMTER = 0;

=item no_ssh([$task])

Disable ssh for all tasks or a specified task.

If you want to disable ssh connection for your complete tasks (for example if you only want to use libVirt) put this in the main section of your Rexfile.

 no_ssh;

If you want to disable ssh connection for a given task, put I<no_ssh> in front of the task definition.

 no_ssh task "mytask", "myserver", sub {
   say "Do something without a ssh connection";
 };

=cut

sub no_ssh {
  if (@_) {
    $_[0]->( no_ssh => 1 );
  }
  else {
    $global_no_ssh = 1;
  }
}

=item task($name [, @servers], $funcref)

This function will create a new task.

=over 4

=item Create a local task (a server independent task)

 task "mytask", sub {
   say "Do something";
 };

If you call this task with (R)?ex it will run on your local machine. You can explicit run this task on other machines if you specify the I<-H> command line parameter.

=item Create a server bound task.

 task "mytask", "server1", sub {
   say "Do something";
 };

You can also specify more than one server.

 task "mytask", "server1", "server2", "server3", sub {
   say "Do something";
 };

Or you can use some expressions to define more than one server.

 task "mytask", "server[1..3]", sub {
   say "Do something";
 };

If you want, you can overwrite the servers with the I<-H> command line parameter.

=item Create a group bound task.

You can define server groups with the I<group> function.

 group "allserver" => "server[1..3]", "workstation[1..10]";
 
 task "mytask", group => "allserver", sub {
   say "Do something";
 };

=back

=cut

sub task {
  my ( $class, $file, @tmp ) = caller;
  my @_ARGS = @_;

  if ( !@_ ) {
    if ( my $t = Rex::get_current_connection ) {
      return $t->{task};
    }
    return;
  }

  # for things like
  # no_ssh task ...
  if (wantarray) {
    return sub {
      my %option = @_;

      $option{class} = $class;
      $option{file}  = $file;
      $option{tmp}   = \@tmp;

      task( @_ARGS, \%option );
    };
  }

  if ( ref( $_ARGS[-1] ) eq "HASH" ) {
    if ( $_ARGS[-1]->{class} ) {
      $class = $_ARGS[-1]->{class};
    }

    if ( $_ARGS[-1]->{file} ) {
      $file = $_ARGS[-1]->{file};
    }

    if ( $_ARGS[-1]->{tmp} ) {
      @tmp = @{ $_ARGS[-1]->{tmp} };
    }
  }

  my $task_name      = shift;
  my $task_name_save = $task_name;

  my $options = {};

  if ( ref( $_[-1] ) eq "HASH" ) {
    $options = pop;
  }

  if ($global_no_ssh) {
    $options->{"no_ssh"} = 1;
  }

  if ( $class ne "main" && $class ne "Rex::CLI" ) {
    $task_name = $class . ":" . $task_name;
  }

  $task_name =~ s/^Rex:://;
  $task_name =~ s/::/:/g;

  if ($current_desc) {
    push( @_, $current_desc );
    $current_desc = "";
  }
  else {
    push( @_, "" );
  }

  no strict 'refs';
  no warnings;
  push( @{"${class}::tasks"}, { name => $task_name_save, code => $_[-2] } );
  use strict;
  use warnings;

  if (!$class->can($task_name_save)
    && $task_name_save =~ m/^[a-zA-Z_][a-zA-Z0-9_]+$/ )
  {
    no strict 'refs';
    Rex::Logger::debug("Registering task: ${class}::$task_name_save");

    my $code = $_[-2];
    *{"${class}::$task_name_save"} = sub {
      Rex::Logger::info("Running task $task_name_save on current connection");
      if ( ref( $_[0] ) eq "HASH" ) {
        $code->(@_);
      }
      else {
        if ($REGISTER_SUB_HASH_PARAMTER) {
          $code->( {@_} );
        }
        else {
          $code->(@_);
        }
      }
    };
    use strict;
  }
  elsif ( ( $class ne "main" && $class ne "Rex::CLI" )
    && !$class->can($task_name_save)
    && $task_name_save =~ m/^[a-zA-Z_][a-zA-Z0-9_]+$/ )
  {
    # if not in main namespace, register the task as a sub
    no strict 'refs';
    Rex::Logger::debug(
      "Registering task (not main namespace): ${class}::$task_name_save");
    my $code = $_[-2];
    *{"${class}::$task_name_save"} = sub {
      if ( ref( $_[0] ) eq "HASH" ) {
        $code->(@_);
      }
      else {
        $code->( {@_} );
      }
    };

    use strict;
  }

  $options->{'dont_register'} ||= $dont_register_tasks;
  Rex::TaskList->create()->create_task( $task_name, @_, $options );
}

=item desc($description)

Set the description of a task.

 desc "This is a task description of the following task";
 task "mytask", sub {
   say "Do something";
 }

=cut

sub desc {
  $current_desc = shift;
}

=item group($name, @servers)

With this function you can group servers, so that you don't need to write too much ;-)

 group "servergroup", "www1", "www2", "www3", "memcache01", "memcache02", "memcache03";

Or with the expression syntax.

 group "servergroup", "www[1..3]", "memcache[01..03]";

=cut

sub group {
  Rex::Group->create_group(@_);
}

# Register set-handler for group
Rex::Config->register_set_handler(
  group => sub {
    Rex::Commands::group(@_);
  }
);

=item batch($name, @tasks)

With the batch function you can call tasks in a batch.

 batch "name", "task1", "task2", "task3";

And call it with the I<-b> console parameter. I<rex -b name>

=cut

sub batch {
  if ($current_desc) {
    push( @_, $current_desc );
    $current_desc = "";
  }
  else {
    push( @_, "" );
  }

  Rex::Batch->create_batch(@_);
}

=item user($user)

Set the user for the ssh connection.

=cut

sub user {
  Rex::Config->set_user(@_);
}

=item password($password)

Set the password for the ssh connection (or for the private key file).

=cut

sub password {
  Rex::Config->set_password(@_);
}

=item auth(for => $entity, %data)

With this function you can modify/set special authentication parameters for tasks and groups. If you want to modify a task's or group's authentication you first have to create it.

If you want to set special login information for a group you have to activate that feature first.

 use Rex -feature => 0.31; # activate setting auth for a group
 
 group frontends => "web[01..10]";
 group backends => "be[01..05]";
 
 auth for => "frontends" =>
            user => "root",
            password => "foobar";
 
 auth for => "backends" =>
            user => "admin",
            private_key => "/path/to/id_rsa",
            public_key => "/path/to/id_rsa.pub",
            sudo => TRUE;
 
 task "prepare", group => ["frontends", "backends"], sub {
   # do something
 };
 
 auth for => "prepare" =>
            user => "root";

=cut

sub auth {
  my ( $_d, $entity, %data ) = @_;

  my $group = Rex::Group->get_group_object($entity);
  if ( !$group ) {
    Rex::Logger::debug("No group $entity found, looking for a task.");
    if ( ref($entity) eq "Regexp" ) {
      my @tasks = Rex::TaskList->create()->get_tasks;
      my @selected_tasks = grep { m/$entity/ } @tasks;
      for my $t (@selected_tasks) {
        auth( $_d, $t, %data );
      }
      return;
    }
    else {
      $group = Rex::TaskList->create()->get_task($entity);
    }
  }

  if ( !$group ) {
    Rex::Logger::info("Group or Task $entity not found.");
    return;
  }

  if ( ref($group) eq "Rex::Group" ) {
    Rex::Logger::debug("=================================================");
    Rex::Logger::debug("You're setting special login credentials for a Group.");
    Rex::Logger::debug(
      "Please remember that the default auth information/task auth information has precedence."
    );
    Rex::Logger::debug(
      "If you want to overwrite this behaviour please use ,,use Rex -feature => 0.31;'' in your Rexfile."
    );
    Rex::Logger::debug("=================================================");
  }

  if ( exists $data{pass_auth} ) {
    $data{auth_type} = "pass";
  }
  if ( exists $data{key_auth} ) {
    $data{auth_type} = "key";
  }
  if ( exists $data{krb5_auth} ) {
    $data{auth_type} = "krb5";
  }

  Rex::Logger::debug( "Setting auth info for " . ref($group) . " $entity" );
  $group->set_auth(%data);
}

=item port($port)

Set the port where the ssh server is listening.

=cut

sub port {
  Rex::Config->set_port(@_);
}

=item sudo_password($password)

Set the password for the sudo command.

=cut

sub sudo_password {
  Rex::Config->set_sudo_password(@_);
}

=item timeout($seconds)

Set the timeout for the ssh connection and other network related stuff.

=cut

sub timeout {
  Rex::Config->set_timeout(@_);
}

=item max_connect_retries($count)

Set the maximum number of connection retries.

=cut

sub max_connect_retries {
  Rex::Config->set_max_connect_fails(@_);
}

=item get_random($count, @chars)

Returns a random string of $count characters on the basis of @chars.

 my $rnd = get_random(8, 'a' .. 'z');

=cut

sub get_random {
  my $count = shift;
  my @chars = @_;

  srand();
  my $ret = "";
  for ( 1 .. $count ) {
    $ret .= $chars[ int( rand( scalar(@chars) - 1 ) ) ];
  }

  return $ret;
}

=item do_task($task)

Call $task from an other task. Will execute the given $task with the servers defined in $task.

 task "task1", "server1", sub {
   say "Running on server1";
   do_task "task2";
 };
 
 task "task2", "server2", sub {
   say "Running on server2";
 };

You may also use an arrayRef for $task if you want to call multiple tasks.

 do_task [ qw/task1 task2 task3/ ];

=cut

sub do_task {
  my $task = shift;

  if ( ref($task) eq "ARRAY" ) {
    for my $t ( @{$task} ) {
      Rex::TaskList->create()->run($t);
    }
  }
  else {
    return Rex::TaskList->create()->run($task);
  }
}

=item run_task($task_name, %option)

Run a task on a given host.

 my $return = run_task "taskname", on => "192.168.3.56";

Do something on server5 if memory is less than 100 MB free on server3.

 task "prepare", "server5", sub {
   my $free_mem = run_task "get_free_mem", on => "server3";
   if($free_mem < 100) {
     say "Less than 100 MB free mem on server3";
     # create a new server instance on server5 to unload server3
   }
 };
 
 task "get_free_mem", sub {
    return memory->{free};
 };

If called without a hostname the task is run localy.

 # this task will run on server5
 task "prepare", "server5", sub {
   # this will call task check_something. but this task will run on localhost.
   my $check = run_task "check_something";
 }
 
 task "check_something", "server4", sub {
   return "foo";
 };

If you want to add custom parameters for the task you can do it this way.

 task "prepare", "server5", sub {
  run_task "check_something", on => "foo", params => { param1 => "value1", param2 => "value2" };
 };

=cut

sub run_task {
  my ( $task_name, %option ) = @_;

  if ( exists $option{on} ) {
    my $task = Rex::TaskList->create()->get_task($task_name);
    if ( exists $option{params} ) {
      $task->run( $option{on}, params => $option{params} );
    }
    else {
      $task->run( $option{on} );
    }
  }
  else {
    my $task = Rex::TaskList->create()->get_task($task_name);
    if ( exists $option{params} ) {
      $task->run( "<local>", params => $option{params} );
    }
    else {
      $task->run("<local>");
    }
  }

}

=item run_batch($batch_name, %option)

Run a batch on a given host.

 my @return = run_batch "batchname", on => "192.168.3.56";

It calls internally run_task, and passes it any option given.

=cut

sub run_batch {
  my ( $batch_name, %option ) = @_;

  my @tasks = Rex::Batch->get_batch($batch_name);
  my @results;
  for my $task (@tasks) {
    my $return = run_task $task, %option;
    push @results, $return;
  }

  return @results;
}

=item public_key($key)

Set the public key.

=cut

sub public_key {
  Rex::Config->set_public_key(@_);
}

=item private_key($key)

Set the private key.

=cut

sub private_key {
  Rex::Config->set_private_key(@_);
}

=item pass_auth

If you want to use password authentication, then you need to call I<pass_auth>.

 user "root";
 password "root";
 
 pass_auth;

=cut

sub pass_auth {
  if (wantarray) { return "pass"; }
  Rex::Config->set_password_auth(1);
}

=item key_auth

If you want to use pubkey authentication, then you need to call I<key_auth>.

 user "bob";
 private_key "/home/bob/.ssh/id_rsa"; # passphrase-less key
 public_key "/home/bob/.ssh/id_rsa.pub";
 
 key_auth;

=cut

sub key_auth {
  if (wantarray) { return "key"; }
  Rex::Config->set_key_auth(1);
}

=item krb5_auth

If you want to use kerberos authentication, then you need to call I<krb5_auth>.
This authentication mechanism is only available if you use Net::OpenSSH.

 set connection => "OpenSSH";
 user "root";
 krb5_auth;

=cut

sub krb5_auth {
  if (wantarray) { return "krb5"; }
  Rex::Config->set_krb5_auth(1);
}

=item parallelism($count)

Will execute the tasks in parallel on the given servers. $count is the thread count to be used.

=cut

sub parallelism {
  Rex::Config->set_parallelism( $_[0] );
}

=item set_distributor($distributor)

This sets the task distribution module. Default is "Base".

Possible values are: Base, Gearman

=cut

sub set_distributor {
  Rex::Config->set_distributor( $_[0] );
}

=item template_function(sub { ... })

This function sets the template processing function. So it is possible to change the template engine. For example to Template::Toolkit.

=cut

sub template_function {
  Rex::Config->set_template_function( $_[0] );
}

=item logging

With this function you can define the logging behaviour of (R)?ex.

=over 4

=item Logging to a file

 logging to_file => "rex.log";

=item Logging to syslog

 logging to_syslog => $facility;

=back

=cut

sub logging {
  my $args;

  if ( $_[0] eq "-nolog" || $_[0] eq "nolog" ) {
    $Rex::Logger::silent = 1 unless $Rex::Logger::debug;
    return;
  }
  else {
    $args = {@_};
  }

  if ( exists $args->{'to_file'} ) {
    Rex::Config->set_log_filename( $args->{'to_file'} );
  }
  elsif ( exists $args->{'to_syslog'} ) {
    Rex::Config->set_log_facility( $args->{'to_syslog'} );
  }
  else {
    Rex::Config->set_log_filename('rex.log');
  }
}

=item needs($package [, @tasks])

With I<needs> you can define dependencies between tasks. The "needed" tasks will be called with the same server configuration as the calling task.

I<needs> will not execute before, around and after hooks.

=over 4

=item Depend on all tasks in a given package.

Depend on all tasks in the package MyPkg. All tasks will be called with the server I<server1>.

 task "mytask", "server1", sub {
   needs MyPkg;
 };

=item Depend on a single task in a given package.

Depend on the I<uname> task in the package MyPkg. The I<uname> task will be called with the server I<server1>.

 task "mytask", "server1", sub {
   needs MyPkg "uname";
 };

=item To call tasks defined in the Rexfile from within a module

 task "mytask", "server1", sub {
   needs main "uname";
 };


=back

=cut

sub needs {
  my ( $self, @args ) = @_;

  # if no namespace is given, use the current one
  if ( ref($self) eq "ARRAY" ) {
    @args = @{$self};
    ($self) = caller;
  }

  if ( $self eq "main" ) {
    $self = "Rex::CLI";
  }

  no strict 'refs';
  my @maybe_tasks_to_run = @{"${self}::tasks"};
  use strict;

  if ( !@args && !@maybe_tasks_to_run ) {
    @args = ($self);
    ($self) = caller;
  }

  if ( ref( $args[0] ) eq "ARRAY" ) {
    @args = @{ $args[0] };
  }

  Rex::Logger::debug("need to call tasks from $self");

  no strict 'refs';
  my @tasks_to_run = @{"${self}::tasks"};
  use strict;

  my %opts = Rex::Args->get;

  for my $task (@tasks_to_run) {
    my $task_name = $task->{"name"};
    if ( @args && grep ( /^$task_name$/, @args ) ) {
      Rex::Logger::debug( "Calling " . $task->{"name"} );
      &{ $task->{"code"} }( \%opts );
    }
    elsif ( !@args ) {
      Rex::Logger::debug( "Calling " . $task->{"name"} );
      &{ $task->{"code"} }( \%opts );
    }
  }

}

# register needs in main namespace
{
  my ($caller_pkg) = caller(1);
  if ( $caller_pkg eq "Rex::CLI" ) {
    no strict 'refs';
    *{"main::needs"} = \&needs;
    use strict;
  }
};

=item include Module::Name

Include a module without registering its tasks.

  include qw/
    Module::One
    Module::Two
  /;

=cut

sub include {
  my (@mods) = @_;

  my $old_val = $dont_register_tasks;
  $dont_register_tasks = 1;
  for my $mod (@mods) {
    eval "require $mod";
    if ($@) { die $@; }
  }
  $dont_register_tasks = $old_val;
}

=item environment($name => $code)

Define an environment. With environments one can use the same task for different hosts. For example if you want to use the same task on your integration-, test- and production servers.

 # define default user/password
 user "root";
 password "foobar";
 pass_auth;
 
 # define default frontend group containing only testwww01.
 group frontend => "testwww01";
 
 # define live environment, with different user/password
 # and a frontend server group containing www01, www02 and www03.
 environment live => sub {
   user "root";
   password "livefoo";
   pass_auth;
 
   group frontend => "www01", "www02", "www03";
 };
 
 # define stage environment with default user and password. but with
 # a own frontend group containing only stagewww01.
 environment stage => sub {
   group frontend => "stagewww01";
 };
 
 task "prepare", group => "frontend", sub {
    say run "hostname";
 };

Calling this task I<rex prepare> will execute on testwww01.
Calling this task with I<rex -E live prepare> will execute on www01, www02, www03.
Calling this task I<rex -E stage prepare> will execute on stagewww01.

You can call the function within a task to get the current environment.

 task "prepare", group => "frontend", sub {
   if(environment() eq "dev") {
     say "i'm in the dev environment";
   }
 };

=cut

sub environment {
  if (@_) {
    my ( $name, $code ) = @_;
    $environments->{$name} = {
      code        => $code,
      description => $current_desc || '',
      name        => $name,
    };
    $current_desc = "";

    if ( Rex::Config->get_environment eq $name ) {
      &$code();
    }

    return 1;
  }
  else {
    return Rex::Config->get_environment || "default";
  }
}

=item LOCAL(&)

With the LOCAL function you can do local commands within a task that is defined to work on remote servers.

 task "mytask", "server1", "server2", sub {
    # this will call 'uptime' on the servers 'server1' and 'server2'
    say run "uptime";
 
    # this will call 'uptime' on the local machine.
    LOCAL {
      say run "uptime";
    };
 };

=cut

sub LOCAL (&) {
  my $cur_conn      = Rex::get_current_connection();
  my $local_connect = Rex::Interface::Connection->create("Local");

  Rex::push_connection(
    {
      conn     => $local_connect,
      ssh      => 0,
      server   => $cur_conn->{server},
      cache    => Rex::Interface::Cache->create(),
      task     => task(),
      reporter => Rex::Report->create( Rex::Config->get_report_type ),
      notify   => Rex::Notify->new(),
    }
  );

  my $ret = $_[0]->();

  Rex::pop_connection();

  return $ret;
}

=item path(@path)

Set the execution path for all commands.

 path "/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/pkg/bin", "/usr/pkg/sbin";

=cut

sub path {
  Rex::Config->set_path( [@_] );
}

=item set($key, $value)

Set a configuration parameter. These Variables can be used in templates as well.

 set database => "db01";
 
 task "prepare", sub {
   my $db = get "database";
 };

Or in a template

 DB: <%= $::database %>

=cut

sub set {
  my ( $key, @value ) = @_;
  Rex::Config->set( $key, @value );
}

=item get($key, $value)

Get a configuration parameter.

 set database => "db01";
 
 task "prepare", sub {
   my $db = get "database";
 };

Or in a template

 DB: <%= $::database %>

=cut

sub get {
  my ($key) = @_;

  if ( ref($key) eq "Rex::Value" ) {
    return $key->value;
  }

  return Rex::Config->get($key);
}

=item before($task => sub {})

Run code before executing the specified task.
(if called repeatedly, each sub will be appended to a list of 'before' functions)

Note: must come after the definition of the specified task

 before mytask => sub {
  my ($server) = @_;
  run "vzctl start vm$server";
 };

=cut

sub before {
  my ( $task, $code ) = @_;
  my ( $package, $file, $line ) = caller;
  Rex::TaskList->create()
    ->modify( 'before', $task, $code, $package, $file, $line );
}

=item after($task => sub {})

Run code after the task is finished.
(if called repeatedly, each sub will be appended to a list of 'after' functions)

Note: must come after the definition of the specified task

 after mytask => sub {
  my ($server, $failed) = @_;
  if($failed) { say "Connection to $server failed."; }
 
  run "vzctl stop vm$server";
 };

=cut

sub after {
  my ( $task, $code ) = @_;
  my ( $package, $file, $line ) = caller;

  Rex::TaskList->create()
    ->modify( 'after', $task, $code, $package, $file, $line );
}

=item around($task => sub {})

Run code before and after the task is finished.
(if called repeatedly, each sub will be appended to a list of 'around' functions)

Note: must come after the definition of the specified task

 around mytask => sub {
  my ($server, $position) = @_;
 
  unless($position) {
    say "Before Task\n";
  }
  else {
    say "After Task\n";
  }
 };

=cut

sub around {
  my ( $task, $code ) = @_;
  my ( $package, $file, $line ) = caller;

  Rex::TaskList->create()
    ->modify( 'around', $task, $code, $package, $file, $line );
}

=item logformat($format)

You can define the logging format with the following parameters.

%D - Appends the current date yyyy-mm-dd HH:mm:ss

%h - The target host

%p - The pid of the running process

%l - Loglevel (INFO or DEBUG)

%s - The Logstring

Default is: [%D] %l - %s

=cut

sub logformat {
  my ($format) = @_;
  $Rex::Logger::format = $format;
}

sub log_format { logformat(@_); }

=item connection

This function returns the current connection object.

 task "foo", group => "baz", sub {
   say "Current Server: " . connection->server;
 };

=cut

sub connection {
  return Rex::get_current_connection()->{conn};
}

=item cache

This function returns the current cache object.

=cut

sub cache {
  my ($type) = @_;

  if ( !$type ) {
    return Rex::get_cache();
  }

  Rex::Config->set_cache_type($type);
}

=item profiler

Returns the profiler object for the current connection.

=cut

sub profiler {
  my $c_profiler = Rex::get_current_connection()->{"profiler"};
  unless ($c_profiler) {
    $c_profiler = $profiler || Rex::Profiler->new;
    $profiler = $c_profiler;
  }

  return $c_profiler;
}

=item report($switch, $type)

This function will initialize the reporting.

 report -on => "YAML";

=cut

sub report {
  my ( $str, $type ) = @_;

  $type ||= "Base";
  Rex::Config->set_report_type($type);

  if ( $str && ( $str eq "-on" || $str eq "on" ) ) {
    Rex::Config->set_do_reporting(1);
    return;
  }
  elsif ( $str && ( $str eq "-off" || $str eq "off" ) ) {
    Rex::Config->set_do_reporting(0);
    return;
  }

  return Rex::get_current_connection()->{reporter};
}

=item source_global_profile(0|1)

If this option is set, every run() command will first source /etc/profile before getting executed.

=cut

sub source_global_profile {
  my ($source) = @_;
  Rex::Config->set_source_global_profile($source);
}

=item last_command_output

This function returns the output of the last "run" command.

On a debian system this example will return the output of I<apt-get install foobar>.

 task "mytask", "myserver", sub {
   install "foobar";
   say last_command_output();
 };

=cut

sub last_command_output {
  return $Rex::Commands::Run::LAST_OUTPUT->[0];
}

=item case($compare, $option)

This is a function to compare a string with some given options.

 task "mytask", "myserver", sub {
   my $ntp_service = case operating_sytem, {
                 Debian  => "ntp",
                 default => "ntpd",
               };
 
   my $ntp_service = case operating_sytem, {
                 qr{debian}i => "ntp",
                 default    => "ntpd",
               };
 
   my $ntp_service = case operating_sytem, {
                 qr{debian}i => "ntp",
                 default    => sub { return "foo"; },
               };
 };

=cut

sub case {
  my ( $compare, $option ) = @_;

  my $to_return = undef;

  if ( exists $option->{$compare} ) {
    $to_return = $option->{$compare};
  }
  else {
    for my $key ( keys %{$option} ) {
      if ( $compare =~ $key ) {
        $to_return = $option->{$key};
        last;
      }
    }
  }

  if ( exists $option->{default} && !$to_return ) {
    $to_return = $option->{default};
  }

  if ( ref $to_return eq "CODE" ) {
    $to_return = &$to_return();
  }

  return $to_return;
}

=item set_executor_for($type, $executor)

Set the executor for a special type. This is primary used for the upload_and_run helper function.

 set_executor_for perl => "/opt/local/bin/perl";

=cut

sub set_executor_for {
  Rex::Config->set_executor_for(@_);
}

=item tmp_dir($tmp_dir)

Set the tmp directory on the remote host to store temporary files.

=cut

sub tmp_dir {
  Rex::Config->set_tmp_dir(@_);
}

=item inspect($varRef)

This function dumps the contents of a variable to STDOUT.

task "mytask", "myserver", sub {
  my $myvar = {
    name => "foo",
    sys  => "bar",
  };
 
  inspect $myvar;
};

=cut

my $depth = 0;

sub _dump_hash {
  my ( $hash, $option ) = @_;

  unless ( $depth == 0 && exists $option->{no_root} && $option->{no_root} ) {
    print "{\n";
  }
  $depth++;

  for my $key ( keys %{$hash} ) {
    _print_indent($option);
    if ( exists $option->{prepend_key} ) { print $option->{prepend_key}; }
    print "$key"
      . ( exists $option->{key_value_sep} ? $option->{key_value_sep} : " => " );
    _dump_var( $hash->{$key} );
  }

  $depth--;
  _print_indent($option);

  unless ( $depth == 0 && exists $option->{no_root} && $option->{no_root} ) {
    print "}\n";
  }
}

sub _dump_array {
  my ( $array, $option ) = @_;

  unless ( $depth == 0 && exists $option->{no_root} && $option->{no_root} ) {
    print "[\n";
  }
  $depth++;

  for my $itm ( @{$array} ) {
    _print_indent($option);
    _dump_var($itm);
  }

  $depth--;
  _print_indent($option);

  unless ( $depth == 0 && exists $option->{no_root} && $option->{no_root} ) {
    print "]\n";
  }
}

sub _print_indent {
  my ($option) = @_;
  unless ( $depth == 1 && exists $option->{no_root} && $option->{no_root} ) {
    print "  " x $depth;
  }
}

sub _dump_var {
  my ( $var, $option ) = @_;

  if ( ref $var eq "HASH" ) {
    _dump_hash( $var, $option );
  }
  elsif ( ref $var eq "ARRAY" ) {
    _dump_array( $var, $option );
  }
  else {
    if ( defined $var ) {
      $var =~ s/\n/\\n/gms;
      $var =~ s/\r/\\r/gms;
      $var =~ s/'/\\'/gms;

      print "'$var'\n";
    }
    else {
      print "no value\n";
    }
  }
}

sub inspect {
  _dump_var(@_);
}

######### private functions

sub evaluate_hostname {
  my $str = shift;
  return unless $str;

  my ( $start, $from, $to, $dummy, $step, $end ) =
    $str =~ m/^([0-9\.\w\-:]+)\[(\d+)..(\d+)(\/(\d+))?\]([0-9\w\.\-:]+)?$/;

  unless ($start) {
    return $str;
  }

  $end  ||= '';
  $step ||= 1;

  my $strict_length = 0;
  if ( length $from == length $to ) {
    $strict_length = length $to;
  }

  my @ret = ();
  for ( ; $from <= $to ; $from += $step ) {
    my $format = "%0" . $strict_length . "i";
    push @ret, $start . sprintf( $format, $from ) . $end;
  }

  return @ret;
}

sub exit {
  Rex::Logger::info("Exiting Rex...");
  Rex::Logger::info("Cleaning up...");

  Rex::global_sudo(0);
  unlink("$::rexfile.lock") if ($::rexfile);
  CORE::exit( $_[0] || 0 );
}

sub get_environment {
  my ( $class, $env ) = @_;

  if ( exists $environments->{$env} ) {
    return $environments->{$env};
  }
}

sub get_environments {
  my $class = shift;

  return sort { $a cmp $b } keys %{$environments};
}

=item sayformat($format)

You can define the format of the say() function.

%D - The current date yyyy-mm-dd HH:mm:ss

%h - The target host

%p - The pid of the running process

%s - The Logstring

You can also define the following values:

default - the default behaviour.

asis - will print every single parameter in its own line. This is usefull if you want to print the output of a command.

=cut

sub sayformat {
  my ($format) = @_;
  Rex::Config->set_say_format($format);
}

sub say_format { sayformat(@_); }

sub say {
  my (@data) = @_;

  return unless defined $_[0];

  my $format = Rex::Config->get_say_format;
  if ( !defined $format || $format eq "default" ) {
    print @_, "\n";
    return;
  }

  if ( $format eq "asis" ) {
    print join( "\n", @_ );
    return;
  }

  for my $line (@data) {
    print _format_string( $format, $line ) . "\n";
  }

}

# %D - Date
# %h - Host
# %s - Logstring
sub _format_string {
  my ( $format, $line ) = @_;

  my $date = _get_timestamp();
  my $host =
      Rex::get_current_connection()
    ? Rex::get_current_connection()->{conn}->server
    : "<local>";
  my $pid = $$;

  $format =~ s/\%D/$date/gms;
  $format =~ s/\%h/$host/gms;
  $format =~ s/\%s/$line/gms;
  $format =~ s/\%p/$pid/gms;

  return $format;
}

sub _get_timestamp {
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
    localtime(time);
  $mon++;
  $year += 1900;

  return
      "$year-"
    . sprintf( "%02i", $mon ) . "-"
    . sprintf( "%02i", $mday ) . " "
    . sprintf( "%02i", $hour ) . ":"
    . sprintf( "%02i", $min ) . ":"
    . sprintf( "%02i", $sec );
}

sub TRUE {
  return 1;
}

sub FALSE {
  return 0;
}

sub make(&) {
  return $_[0];
}

=back

=cut

1;
