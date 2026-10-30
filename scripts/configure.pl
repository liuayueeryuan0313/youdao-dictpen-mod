use strict;use warnings;use JSON::PP;use File::Path qw(make_path);use File::Copy qw(copy);
my $base=shift or die 'base';
sub read_file {open my $f,'<:raw',$_[0] or die "read $_[0]: $!";local $/;return <$f>}
sub write_file {my($p,$v,$mode)=@_;open my $f,'>:raw',"$p.unified-new" or die $!;print $f $v;close $f or die $!;chmod $mode,"$p.unified-new";rename "$p.unified-new",$p or die $!;}
my $passwd=read_file('/etc/passwd');my $shadow=read_file('/etc/shadow');
die 'existing unmanaged files account' if $passwd=~/^files:(?!x:0:0:MOD SFTP files:\/:\/bin\/false$)/m;
open my $random,'<:raw','/dev/urandom' or die $!;read($random,my $entropy,48)==48 or die 'entropy';close $random;
my @alphabet=('A'..'Z','a'..'z',0..9);my $password=join('',map{$alphabet[ord($_)%62]}split //,substr($entropy,0,16));
my $salt='\$6\$'.unpack('H*',substr($entropy,16,8)).'\$';$salt=~s/\\//g;
my $hash=crypt($password,$salt);die 'crypt unsupported' unless $hash=~/^\$6\$/;
$passwd=~s/^files:[^\n]*\n?//mg;$shadow=~s/^files:[^\n]*\n?//mg;
$passwd.="\n" unless $passwd=~/\n$/;$shadow.="\n" unless $shadow=~/\n$/;
$passwd.="files:x:0:0:MOD SFTP files:/:/bin/false\n";$shadow.="files:$hash:19000:0:99999:7:::\n";
write_file('/etc/passwd',$passwd,0644);write_file('/etc/shadow',$shadow,0600);
make_path('/userdata/cfg/mod-sftp',{mode=>0700});
write_file('/userdata/cfg/mod-sftp/password',$password,0600);
copy("$base/sshd_config",'/userdata/cfg/mod-sftp/sshd_config') or die $!;chmod 0600,'/userdata/cfg/mod-sftp/sshd_config';
unless(-f '/userdata/cfg/mod-sftp/ssh_host_ed25519_key'){
 system('/usr/bin/ssh-keygen','-q','-t','ed25519','-N','','-f','/userdata/cfg/mod-sftp/ssh_host_ed25519_key')==0 or die 'ssh-keygen';
}
my $module=read_file("$base/credentials-template.js.bin");my $count=($module=~s/ZZZZZZZZZZZZZZZZ/$password/g);die 'credential template mismatch' unless $count==1;
write_file('/userdisk/miniapp/data/mini_app/pkg/8080272425914438/b/mod-sftp-credentials.js.bin',$module,0600);
unless(-f '/userdata/cfg/mod-developer.conf'){write_file('/userdata/cfg/mod-developer.conf',"MOD_USB_ADB=1\nMOD_WIFI_ADB=0\nMOD_ADB_PORT=5555\nMOD_SFTP=0\n",0600);}
unless(-f '/userdata/cfg/mod-upload-logs.conf'){write_file('/userdata/cfg/mod-upload-logs.conf',"UPLOAD_LOGS=0\n",0600);}
my $state='/userdisk/mod-backups/unified-mod-v1';make_path($state,{mode=>0700});
my $cfg='/etc/miniapp/resources/cfg.json';my $c=decode_json(read_file($cfg));
my $env='/userdisk/miniapp/resources/env.json';my $e=decode_json(read_file($env));$e->{custom}||={};
my %defaults=(modDevUsbAdb=>JSON::PP::true,modDevWirelessAdb=>JSON::PP::false,modDevAdbPort=>5555,modDevSftp=>JSON::PP::false,modDevUploadLogs=>JSON::PP::false,littlePDeepseekMode=>'on',littlePResponseMode=>'socratic');
my $patches={fps=>{existed=>exists($c->{screen}{fps_max})?1:0,old=>$c->{screen}{fps_max}},env=>{}};
for my $k(keys %defaults){$patches->{env}{$k}=$defaults{$k} unless exists $e->{custom}{$k};}
write_file("$state/json-patches.json",encode_json($patches),0600);
$c->{screen}{fps_max}=60;write_file($cfg,encode_json($c),0644);
for my $k(keys %defaults){$e->{custom}{$k}=$defaults{$k} unless exists $e->{custom}{$k};}
write_file($env,encode_json($e),0644);
system('/sbin/sshd','-t','-f','/userdata/cfg/mod-sftp/sshd_config')==0 or die 'sshd validation';
print "TARGET_CONFIGURATION_READY\n";
