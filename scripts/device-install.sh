#!/bin/sh
set -eu
BASE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STATE=/userdisk/mod-backups/unified-mod-v1
check(){ [ "$(sha256sum "$1" | cut -d ' ' -f 1)" = "$2" ] || { echo "HASH_MISMATCH: $1";exit 1; }; }
[ "$(id -u)" = 0 ] || { echo ROOT_REQUIRED;exit 1; }
grep -qi rk3562 /etc/os-release && grep -qi melon /etc/os-release || { echo UNSUPPORTED_PLATFORM;exit 1; }
[ -x /usr/bin/perl ] && [ -x /usr/bin/ssh-keygen ] && [ -x /sbin/sshd ]
LC_ALL=C perl -MJSON::PP -e 'exit 0'
LC_ALL=C perl -MJSON::PP -e 'local $/;open my $f,"<","/etc/miniapp/resources/local_packages.json" or die $!;exit(decode_json(<$f>)->{version} eq "4.3.5"?0:1)' || { echo UNSUPPORTED_FIRMWARE;exit 1; }
[ ! -e "$STATE/state" ] || { echo ALREADY_INSTALLED_RESTORE_FIRST;exit 1; }
for filesystem in / /userdisk /userdata;do
 available=$(df -Pk "$filesystem" | awk 'END { print $4 }')
 [ "$available" -ge 65536 ] || { [ "$filesystem" = /userdata ] && [ "$available" -ge 8192 ]; } || { echo "INSUFFICIENT_SPACE: $filesystem";exit 1; }
done
while IFS='|' read -r digest mode target allowed; do
 check "$BASE/payload$target" "$digest"
 case "$target" in
  /userdisk/miniapp/data/mini_app/pkg/800199900000000[12]/*) ;;
  /userdisk/miniapp/data/mini_app/pkg/*)
   bank=$(printf '%s' "$target" | cut -d / -f 1-8)
   [ -f "$bank/manifest.json" ] || { echo "REQUIRED_APP_BANK_MISSING: $bank";exit 1; };;
 esac
 if [ -f "$target" ]; then
  current=$(sha256sum "$target" | cut -d ' ' -f 1)
  case ",$allowed,$digest," in *",$current,"*) ;; *) echo "UNKNOWN_TARGET_FILE: $target";exit 1;; esac
 fi
done < "$BASE/files.tsv"
echo PREFLIGHT_OK
[ "${1:-}" != --check ] || exit 0
if [ -d "$STATE" ];then archive="$STATE.restored.$(date +%Y%m%d%H%M%S)";[ ! -e "$archive" ] || exit 1;mv "$STATE" "$archive";fi
mkdir -p "$STATE/original"
chmod 700 "$STATE"
was_ro=0;grep ' / ' /proc/mounts | grep -q ' ro,' && was_ro=1
printf '%s\n' "$was_ro" > "$STATE/root-was-ro"
mount -o remount,rw /
backup(){
 p=$1
 if grep -Fxq "$p" "$STATE/tracked" 2>/dev/null; then return;fi
 if [ -f "$p" ]; then mkdir -p "$STATE/original$(dirname "$p")";cp -p "$p" "$STATE/original$p";sha256sum "$STATE/original$p" >> "$STATE/original.sha256";else printf '%s\n' "$p" >> "$STATE/new";fi
 printf '%s\n' "$p" >> "$STATE/tracked"
}
rollback(){
 trap - EXIT HUP INT TERM
 sh "$BASE/device-restore.sh" --failed || true
 [ "$was_ro" = 0 ] || mount -o remount,ro / || true
}
printf 'pending\n' > "$STATE/state"
cp "$BASE/device-restore.sh" "$STATE/restore.sh"
cp "$BASE/restore-config.pl" "$STATE/restore-config.pl"
trap rollback EXIT
trap 'rollback;exit 1' HUP INT TERM
while IFS='|' read -r digest mode target allowed;do backup "$target";done < "$BASE/files.tsv"
for p in /etc/passwd /etc/shadow /userdata/cfg/mod-developer.conf /userdata/cfg/mod-upload-logs.conf /userdata/cfg/mod-upload-logs.enabled /userdata/cfg/mod-sftp/password /userdata/cfg/mod-sftp/sshd_config /userdata/cfg/mod-sftp/ssh_host_ed25519_key /userdata/cfg/mod-sftp/ssh_host_ed25519_key.pub /userdisk/miniapp/resources/env.json /etc/miniapp/resources/cfg.json /userdisk/miniapp/data/mini_app/pkg/8080272425914438/b/mod-sftp-credentials.js.bin; do backup "$p";done
for id in 8001999000000001 8001999000000002;do
 if [ ! -d "/userdisk/miniapp/data/mini_app/pkg/$id" ];then
  printf '%s\n' "$id" >> "$STATE/new-apps"
  result=$(miniapp_cli install "$BASE/apps/$id.amr")
  printf '%s\n' "$result" | grep -Eq '"ret"[[:space:]]*:[[:space:]]*0' || exit 1
 fi
done
while IFS='|' read -r digest mode target allowed;do
 mkdir -p "$(dirname "$target")"
 cp "$BASE/payload$target" "$target.unified-new"
 chmod "$mode" "$target.unified-new"
 mv "$target.unified-new" "$target"
done < "$BASE/files.tsv"
LC_ALL=C perl "$BASE/configure.pl" "$BASE"
while IFS= read -r target;do
 case "$target" in /etc/miniapp/resources/cfg.json|/userdisk/miniapp/resources/env.json|/userdata/cfg/mod-developer.conf|/userdata/cfg/mod-upload-logs.conf|/userdata/cfg/mod-upload-logs.enabled) continue;;esac
 [ ! -f "$target" ] || sha256sum "$target" >> "$STATE/installed.sha256"
done < "$STATE/tracked"
printf 'complete\n' > "$STATE/state"
printf '%s\n' "$was_ro" > "$STATE/root-was-ro"
sync
trap - EXIT HUP INT TERM
[ "$was_ro" = 0 ] || mount -o remount,ro /
echo INSTALL_COMPLETE_REBOOT_REQUIRED
