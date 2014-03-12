#
# (c) Jan Gehring <jan.gehring@gmail.com>
# 
# vim: set ts=3 sw=3 tw=0:
# vim: set expandtab:
   
package Rex::Interface::Exec::Local;
   
use strict;
use warnings;

use Rex::Logger;
use Rex::Commands;

use Symbol 'gensym';
use IPC::Open3;

sub new {
   my $that = shift;
   my $proto = ref($that) || $that;
   my $self = { @_ };

   bless($self, $proto);

   return $self;
}

sub exec {
   my ($self, $cmd, $path, $option) = @_;


   my ($out, $err);

   if(exists $option->{cwd}) {
      $cmd = "cd " . $option->{cwd} . " && $cmd";
   }

   if(exists $option->{path}) {
      $path = $option->{path};
   }

   if(exists $option->{format_cmd}) {
      $option->{format_cmd} =~ s/{{CMD}}/$cmd/;
      $cmd = $option->{format_cmd};
   }

   Rex::Logger::debug("Executing: $cmd");

   Rex::Commands::profiler()->start("exec: $cmd");
   if($^O !~ m/^MSWin/) {
      if($path) { $path = "PATH=$path" }
      $path ||= "";

      my $new_cmd = "LC_ALL=C $cmd";
      if($path) {
         $new_cmd = "export $path ; $new_cmd";
      }

      if(Rex::Config->get_source_global_profile) {
         $new_cmd = ". /etc/profile >/dev/null 2>&1; $new_cmd";
      }

      $cmd = $new_cmd;
   }

   my($writer, $reader, $error);
   $error = gensym;

   if(Rex::Config->get_no_tty) {
      my $pid = open3($writer, $reader, $error, $cmd);

      while(my $output = <$reader>) {
         $out .= $output;
      }

      while(my $errout = <$error>) {
         $err .= $errout;
      }

      waitpid($pid, 0) or die($!);
   }
   else {
      $cmd .= " 2>&1";
      $out = qx{$cmd};
   }

   $? >>= 8;

   Rex::Logger::debug($out) if($out);
   if($err) {
      Rex::Logger::debug("========= ERR ============");
      Rex::Logger::debug($err);
      Rex::Logger::debug("========= ERR ============");
   }

   Rex::Commands::profiler()->end("exec: $cmd");

   if(wantarray) { return ($out, $err); }

   return $out;
}

1;
