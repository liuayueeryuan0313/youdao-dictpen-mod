use strict;use warnings;use JSON::PP;
my $state='/userdisk/mod-backups/unified-mod-v1';
sub read_json {open my $f,'<:raw',$_[0] or die $!;local $/;return decode_json(<$f>);}
sub save {my($p,$v)=@_;open my $f,'>:raw',"$p.unified-restore" or die $!;print $f encode_json($v);close $f;chmod 0644,"$p.unified-restore";rename "$p.unified-restore",$p or die $!;}
exit 0 unless -f "$state/json-patches.json";
my $patch=read_json("$state/json-patches.json");
my $cfg='/etc/miniapp/resources/cfg.json';my $c=read_json($cfg);
if(defined($c->{screen}{fps_max}) && $c->{screen}{fps_max}==60){if($patch->{fps}{existed}){$c->{screen}{fps_max}=$patch->{fps}{old};}else{delete $c->{screen}{fps_max};}save($cfg,$c);}
my $env='/userdisk/miniapp/resources/env.json';my $e=read_json($env);
for my $key(keys %{$patch->{env}}){if(exists($e->{custom}{$key})&&encode_json($e->{custom}{$key}) eq encode_json($patch->{env}{$key})){delete $e->{custom}{$key};}}
save($env,$e);
