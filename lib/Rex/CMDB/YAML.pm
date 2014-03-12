#
# (c) Jan Gehring <jan.gehring@gmail.com>
# 
# vim: set ts=3 sw=3 tw=0:
# vim: set expandtab:
   
package Rex::CMDB::YAML;

use strict;
use warnings;

use Rex::Commands -no => [qw/get/];
use Rex::Logger;
use YAML;

sub new {
   my $that = shift;
   my $proto = ref($that) || $that;
   my $self = { @_ };

   bless($self, $proto);

   return $self;
}

sub get {
   my ($self, $item, $server) = @_;

   # first open $server.yml
   # second open $environment/$server.yml
   # third open $environment/default.yml
   # forth open default.yml

   my $env = environment;
   my $yaml_path = $self->{path};
   my @files = ("$env/$server.yml", "$env/default.yml", "$server.yml", "default.yml");

   my $all = {};

   for my $file (@files) {
      Rex::Logger::debug("CMDB - Opening $yaml_path/$file");
      if(-f "$yaml_path/$file") {
         my $content = eval { local(@ARGV, $/) = ("$yaml_path/$file"); <>; };
         $content .= "\n"; # for safety

         my $ref = Load($content);

         if(! $item) {
            for my $key (keys %{ $ref }) {
               if(exists $all->{$key}) {
                  next;
               }
               $all->{$key} = $ref->{$key};
            }
         }

         if(defined $item && exists $ref->{$item}) {
            Rex::Logger::debug("CMDB - Found $item in $file");
            return $ref->{$item};
         }
      }
   }

   if(! $item) {
      return $all;
   }

   Rex::Logger::debug("CMDB - no item ($item) found");

   return undef;
}

1;
