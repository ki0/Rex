#
# (c) Jan Gehring <jan.gehring@gmail.com>
# 
# vim: set ts=3 sw=3 tw=0:
# vim: set expandtab:
   
package Rex::Report::YAML;

use strict;
use warnings;

use Rex;
use Data::Dumper;
use Rex::Report::Base;
require Rex::Commands;
use YAML;
use base qw(Rex::Report::Base);

our $REPORT_PATH = "./reports";

sub new {
   my $that = shift;
   my $proto = ref($that) || $that;
   my $self = $proto->SUPER::new(@_);

   bless($self, $proto);

   $self->{__reports__} = [];

   return $self;
}

sub report {
   my ($self, $msg) = @_;
   push @{$self->{__reports__}}, $msg; 
}

sub write_report {
   my ($self) = @_;

   $REPORT_PATH = Rex::Commands::get('report_path') || "reports";

   if(! -d $REPORT_PATH) {
      mkdir $REPORT_PATH or die($! . ": $REPORT_PATH");
   }

   my $server_name = Rex::Commands::connection()->server;
   if($server_name eq "<local>") {
      $server_name = "_local_";
   }
   if(! -d $REPORT_PATH . "/" . $server_name) {
      mkdir "$REPORT_PATH/$server_name";
   }
   open(my $fh, ">", "$REPORT_PATH/$server_name/" . time() . ".yml") or die($!);
   print $fh Dump($self->{__reports__});
   close($fh);

   $self->{__reports__} = [];
}

sub register_reporting_hooks {
   my ($self) = @_;

   my @modules = qw(File Fs Pkg Run Service Upload User Cron Download);

   my @skip_functions = qw/
      file_write file_append file_read extract cat template
      can_run
      is_dir is_file stat rm list_files ls readlink chdir cd is_readable is_writable is_writeable free df du glob
      installed_packages is_installed update_package_db package_provider_for
      service_provider_for
      get_uid get_user user_list user_groups get_group get_gid
   /;

   for my $mod (@modules) {
      my @exports = eval "\@Rex::Commands::${mod}::EXPORT";
      for my $export (@exports) {
         if(grep { $_ eq $export } @skip_functions) {
            next;
         }
         no strict 'refs';
         no warnings;
         eval "use Rex::Commands::$mod;";
         my $orig_sub = \&{ "Rex::Commands::${mod}::$export" };
         *{"Rex::Commands::${mod}::$export"} = sub {
            my $ret;
            my $start_time = time;

            eval {
               $ret = $orig_sub->(@_);
               if(ref $ret eq "HASH") {
                  if(exists $ret->{skip} && $ret->{skip} == 1) {
                     return 1;
                  }
                  $self->report({
                        command    => $export,
                        module     => "Rex::Commands::$mod",
                        start_time => $start_time,
                        end_time   => time,
                        data       => [ @_ ],
                        success    => 1,
                        message    => "",
                        %{ $ret },
                  });
               }
               else {
                  $self->report({
                        command    => $export,
                        module     => "Rex::Commands::$mod",
                        start_time => $start_time,
                        end_time   => time,
                        data       => [ @_ ],
                        success    => 1,
                        changed    => 1,
                        message    => "",
                  });
               }
               1;
            } or do {
               $self->report({
                     command    => $export,
                     module     => "Rex::Commands::$mod",
                     start_time => $start_time,
                     end_time   => time,
                     data       => [ @_ ],
                     success    => 0,
                     changed    => 0,
                     message    => $@,
               });
               Rex::unset_modified_caller();

               die($@);
            };

            if(ref $ret eq "HASH" && exists $ret->{ret}) {
               # return the original return value
               return $ret->{ret};
            }
            return $ret;
         };
      }
   }
}



1;
