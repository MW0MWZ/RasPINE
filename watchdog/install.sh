#!/bin/sh
# install.sh ROOT - install the RasPINE watchdog into the system at ROOT (an
# image being built; "/" for a running system) and enable it
# Part of RasPINE. Used by RasPINE's image build and by Pi-Star OS's.
set -e
ROOT="${1:?usage: $0 ROOT}"
SRC=$(cd "$(dirname "$0")" && pwd)

install -D -m 755 "$SRC/etc/init.d/raspine-watchdog" "$ROOT/etc/init.d/raspine-watchdog"
install -D -m 755 "$SRC/etc/init.d/raspine-watchdog-health" "$ROOT/etc/init.d/raspine-watchdog-health"
[ -f "$ROOT/etc/conf.d/raspine-watchdog" ] || \
	install -D -m 644 "$SRC/etc/conf.d/raspine-watchdog" "$ROOT/etc/conf.d/raspine-watchdog"
for f in raspine-watchdog-health raspine-watchdog-mark raspine-watchdog-fresh; do
	install -D -m 755 "$SRC/usr/sbin/$f" "$ROOT/usr/sbin/$f"
done
install -D -m 644 "$SRC/etc/raspine-watchdog.d/README" "$ROOT/etc/raspine-watchdog.d/README"
mkdir -p "$ROOT/var/lib/raspine-watchdog"

# Both in the boot runlevel: the feeder first of all, the checks once the
# filesystems are mounted
mkdir -p "$ROOT/etc/runlevels/boot"
for svc in raspine-watchdog raspine-watchdog-health; do
	ln -sf "/etc/init.d/$svc" "$ROOT/etc/runlevels/boot/$svc"
done

# inittab: mark a shutdown's start (and leave the watchdog armed through
# it) before OpenRC stops everything, and its end after
tab="$ROOT/etc/inittab"
if ! grep -q raspine-watchdog-mark "$tab"; then
	sed -i 's|^::shutdown:/sbin/openrc shutdown$|::shutdown:/usr/sbin/raspine-watchdog-mark stopping\n&\n::shutdown:/usr/sbin/raspine-watchdog-mark stopped|' "$tab"
	grep -q "raspine-watchdog-mark stopping" "$tab" || {
		echo "install.sh: $tab has no '::shutdown:/sbin/openrc shutdown' line" >&2
		exit 1
	}
fi
echo "RasPINE watchdog installed in $ROOT"
