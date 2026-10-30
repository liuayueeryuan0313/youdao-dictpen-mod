#!/bin/sh
set -eu
STATE=/userdisk/mod-backups/unified-mod-v1
[ -f "$STATE/state" ] || { echo NO_BACKUP;exit 1; }
[ ! -f "$STATE/original.sha256" ] || sha256sum -c "$STATE/original.sha256" >/dev/null || { echo BACKUP_CORRUPTED_STOPPED;exit 1; }
if [ "${1:-}" != --failed ] && [ -f "$STATE/installed.sha256" ];then sha256sum -c "$STATE/installed.sha256" >/dev/null || { echo FILES_CHANGED_AFTER_INSTALL_STOPPED;exit 1; };fi
mount -o remount,rw /
restore_mount(){ if [ -f "$STATE/root-was-ro" ] && [ "$(cat "$STATE/root-was-ro")" = 1 ];then mount -o remount,ro /;fi; }
trap restore_mount EXIT
LC_ALL=C perl "$STATE/restore-config.pl"
if [ -f "$STATE/new-apps" ];then while IFS= read -r id;do
 [ -d "/userdisk/miniapp/data/mini_app/pkg/$id" ] || continue
 result=$(miniapp_cli uninstall "$id")
 printf '%s\n' "$result" | grep -Eq '"ret"[[:space:]]*:[[:space:]]*0' || { echo "APP_UNINSTALL_FAILED: $id";exit 1; }
done < "$STATE/new-apps";fi
if [ -f "$STATE/tracked" ];then
 while IFS= read -r p;do
  case "$p" in /etc/miniapp/resources/cfg.json|/userdisk/miniapp/resources/env.json) continue;;esac
  if [ -f "$STATE/original$p" ];then cp -p "$STATE/original$p" "$p.unified-restore";mv "$p.unified-restore" "$p";
  elif grep -Fxq "$p" "$STATE/new";then rm -f "$p";fi
 done < "$STATE/tracked"
fi
sync
mv "$STATE/state" "$STATE/restored-state"
restore_mount
trap - EXIT
echo RESTORE_COMPLETE_REBOOT_REQUIRED
