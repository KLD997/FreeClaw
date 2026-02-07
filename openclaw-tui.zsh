#!/usr/bin/env zsh
# bsddialog-based TUI for OpenClaw jail management
#
# Env overrides:
#   JAIL_NAME=openclaw
#   JAIL_IP=10.30.0.10
#   OC_USER=kld
#   OC_PORT=18789
#   GATEWAY_SERVICE=openclaw_gateway
#   AUTO_START=0|1

set -eu
setopt PIPEFAIL

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Config
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
JAIL_NAME="${JAIL_NAME:-openclaw}"
JAIL_IP="${JAIL_IP:-10.30.0.10}"
OC_USER="${OC_USER:-kld}"
OC_PORT="${OC_PORT:-18789}"
GATEWAY_SERVICE="${GATEWAY_SERVICE:-openclaw_gateway}"
FORWARD_SERVICE="${FORWARD_SERVICE:-openclaw_forward}"
AUTO_START="${AUTO_START:-0}"

UI_URL="http://127.0.0.1:${OC_PORT}/"
JAIL_GATEWAY_LOG="/var/log/openclaw_gateway.log"
JAIL_GATEWAY_PID="/var/run/openclaw/openclaw_gateway.pid"
HOST_FORWARD_LOG="/var/log/openclaw_forward.log"
HOST_FORWARD_PID="/var/run/openclaw_forward.pid"

SCRIPT_DIR="${0:A:h}"
INSTALLER="${SCRIPT_DIR}/openclaw-freebsd-install.sh"

BACKTITLE="OpenClaw • ${JAIL_NAME} (${JAIL_IP})"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Privilege helpers
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SUDO=""
command -v doas >/dev/null 2>&1 && SUDO=doas
[[ -z "$SUDO" ]] && command -v sudo >/dev/null 2>&1 && SUDO=sudo

need_rootish() {
	[[ $EUID -eq 0 ]] && return 0
	[[ -n "$SUDO" ]] && return 0
	bsddialog --backtitle "$BACKTITLE" --title "Error" \
		--msgbox "Need root privileges (install doas/sudo or run as root)." 6 50
	return 1
}

run_host() {
	if [[ $EUID -eq 0 ]]; then
		command "$@"
	else
		"$SUDO" "$@"
	fi
}

jexec_cmd() {
	need_rootish || return 1
	run_host jexec "$JAIL_NAME" "$@"
}

jail_user() {
	need_rootish || return 1
	jexec_cmd su -m "$OC_USER" -c "$*"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# State probes
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
jail_running() {
	need_rootish || return 1
	run_host jls -j "$JAIL_NAME" >/dev/null 2>&1
}

gateway_running() {
	jail_running || return 1
	local out
	out="$(jexec_cmd service "$GATEWAY_SERVICE" status 2>&1 || true)"
	print -r -- "$out" | grep -qi "is running"
}

forwarder_running() {
	local out
	out="$(run_host service "$FORWARD_SERVICE" status 2>&1 || true)"
	print -r -- "$out" | grep -qi "is running"
}

ui_reachable() {
	command -v fetch >/dev/null 2>&1 || return 1
	fetch -qo- --timeout=2 "$UI_URL" >/dev/null 2>&1
}

get_token() {
	jail_running || { printf ""; return 0; }
	jail_user "cat ~/.openclaw/gateway.token 2>/dev/null || true" 2>/dev/null \
		| tr -d '\r' | tail -n1
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Actions
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
do_install() {
	if [[ ! -f "$INSTALLER" ]]; then
		bsddialog --backtitle "$BACKTITLE" --title "Install" \
			--msgbox "Installer not found:\n$INSTALLER\n\nPlace openclaw-freebsd-install.sh next to this script." 8 60
		return
	fi
	need_rootish || return
	chmod +x "$INSTALLER" 2>/dev/null || true

	local tmp=$(mktemp)
	run_host env JAIL_NAME="$JAIL_NAME" JAIL_IP="$JAIL_IP" \
		OC_USER="$OC_USER" OC_PORT="$OC_PORT" "$INSTALLER" >"$tmp" 2>&1
	bsddialog --backtitle "$BACKTITLE" --title "Install Output" \
		--textbox "$tmp" 24 78
	rm -f "$tmp"
}

do_start() {
	need_rootish || return
	local msg=""

	if ! jail_running; then
		msg+="Starting jail: $JAIL_NAME\n"
		run_host service jail onestart "$JAIL_NAME" >/dev/null 2>&1 \
			|| run_host service jail start "$JAIL_NAME" >/dev/null 2>&1 || true
	fi

	if jail_running; then
		msg+="Starting gateway: $GATEWAY_SERVICE\n"
		jexec_cmd service "$GATEWAY_SERVICE" onestart >/dev/null 2>&1 \
			|| jexec_cmd service "$GATEWAY_SERVICE" start >/dev/null 2>&1 || true
	else
		msg+="Jail did not start; cannot start gateway.\n"
	fi

	msg+="Starting forwarder: $FORWARD_SERVICE\n"
	run_host service "$FORWARD_SERVICE" start >/dev/null 2>&1 || true

	msg+="\nUI: $UI_URL"
	bsddialog --backtitle "$BACKTITLE" --title "Start Stack" --msgbox "$msg" 12 50
}

do_stop() {
	need_rootish || return
	local msg=""

	msg+="Stopping forwarder: $FORWARD_SERVICE\n"
	run_host service "$FORWARD_SERVICE" stop >/dev/null 2>&1 || true

	if jail_running; then
		msg+="Stopping gateway: $GATEWAY_SERVICE\n"
		jexec_cmd service "$GATEWAY_SERVICE" onestop >/dev/null 2>&1 \
			|| jexec_cmd service "$GATEWAY_SERVICE" stop >/dev/null 2>&1 || true

		msg+="Stopping jail: $JAIL_NAME\n"
		run_host service jail onestop "$JAIL_NAME" >/dev/null 2>&1 \
			|| run_host service jail stop "$JAIL_NAME" >/dev/null 2>&1 || true
	fi

	bsddialog --backtitle "$BACKTITLE" --title "Stop Stack" --msgbox "${msg:-Already stopped.}" 10 50
}

do_restart() {
	do_stop
	do_start
}

do_status() {
	need_rootish || return

	local jr="STOPPED"; jail_running && jr="RUNNING"
	local gr="STOPPED"; gateway_running && gr="RUNNING"
	local fr="STOPPED"; forwarder_running && fr="RUNNING"
	local ur="NO"; ui_reachable && ur="YES"
	local token; token="$(get_token)"

	local info=""
	info+="Jail:         $jr\n"
	info+="Jail IP:      $JAIL_IP\n"
	info+="Gateway:      $gr\n"
	info+="Forwarder:    $fr\n"
	info+="UI reachable: $ur\n"
	info+="UI URL:       $UI_URL\n"
	info+="\nToken: ${token:-<missing>}\n"
	info+="\nGateway PID:   $JAIL_GATEWAY_PID\n"
	info+="Forwarder PID: $HOST_FORWARD_PID"

	bsddialog --backtitle "$BACKTITLE" --title "Status" --msgbox "$info" 18 55
}

do_logs() {
	need_rootish || return

	local choice
	choice=$(bsddialog --backtitle "$BACKTITLE" --title "View Logs" \
		--menu "Select log:" 12 50 3 \
		"1" "Gateway log (jail)" \
		"2" "Forwarder log (host)" \
		"b" "Back" \
		3>&1 1>&2 2>&3) || return

	case "$choice" in
	1)
		if jail_running; then
			local tmp=$(mktemp)
			jexec_cmd sh -c "tail -n 200 '$JAIL_GATEWAY_LOG' 2>/dev/null || true" >"$tmp"
			bsddialog --backtitle "$BACKTITLE" --title "Gateway Log" --textbox "$tmp" 24 78
			rm -f "$tmp"
		else
			bsddialog --backtitle "$BACKTITLE" --title "Logs" --msgbox "Jail not running." 6 40
		fi
		;;
	2)
		local tmp=$(mktemp)
		run_host tail -n 200 "$HOST_FORWARD_LOG" >"$tmp" 2>&1 || true
		bsddialog --backtitle "$BACKTITLE" --title "Forwarder Log" --textbox "$tmp" 24 78
		rm -f "$tmp"
		;;
	esac
}

do_open_ui() {
	local token; token="$(get_token)"

	if command -v xdg-open >/dev/null 2>&1; then
		xdg-open "$UI_URL" >/dev/null 2>&1 &
	elif command -v firefox >/dev/null 2>&1; then
		firefox "$UI_URL" >/dev/null 2>&1 &
	fi

	bsddialog --backtitle "$BACKTITLE" --title "Open UI" \
		--msgbox "URL: $UI_URL\nToken: ${token:-<missing>}" 7 55
}

do_edit_config() {
	need_rootish || return
	if ! jail_running; then
		bsddialog --backtitle "$BACKTITLE" --title "Edit Config" \
			--msgbox "Jail not running." 6 40
		return
	fi

	local ed="${EDITOR:-vi}"
	jail_user "$ed ~/.openclaw/openclaw.json"
	stty sane 2>/dev/null || true
}

do_apikeys() {
	need_rootish || return
	if ! jail_running; then
		bsddialog --backtitle "$BACKTITLE" --title "API Keys" \
			--msgbox "Jail not running." 6 40
		return
	fi

	local tmp=$(mktemp)
	jexec_cmd su -m "$OC_USER" -c \
		'test -f ~/.openclaw/.env && sed "s/=.*/=********/" ~/.openclaw/.env || echo "(no .env)"' \
		>"$tmp" 2>&1
	bsddialog --backtitle "$BACKTITLE" --title "API Keys (masked)" --textbox "$tmp" 16 60
	rm -f "$tmp"
}

do_wizard() {
	local cmd="$1" title="$2"
	need_rootish || return
	if ! jail_running; then
		bsddialog --backtitle "$BACKTITLE" --title "$title" \
			--msgbox "Jail not running. Start the stack first." 6 50
		return
	fi
	clear
	jail_user "$cmd"
	stty sane 2>/dev/null || true
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Main menu
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
main_menu() {
	if (( AUTO_START )); then
		need_rootish && {
			forwarder_running || run_host service "$FORWARD_SERVICE" start >/dev/null 2>&1 || true
			if jail_running && ! gateway_running; then
				jexec_cmd service "$GATEWAY_SERVICE" onestart >/dev/null 2>&1 || true
			fi
		}
	fi

	while true; do
		local choice
		choice=$(bsddialog --backtitle "$BACKTITLE" --title "OpenClaw Manager" \
			--cancel-label "Quit" \
			--menu "Select action:" 22 60 14 \
			"1" "Install / Repair" \
			"2" "Start Stack" \
			"3" "Stop Stack" \
			"4" "Restart Stack" \
			"5" "View Status" \
			"6" "View Logs" \
			"7" "Open UI" \
			"8" "Edit Config" \
			"9" "API Keys" \
			"w" "Onboard Wizard" \
			"d" "Dashboard" \
			"c" "Configure" \
			"s" "Web Tools" \
			"q" "Quit" \
			3>&1 1>&2 2>&3) || break

		case "$choice" in
		1) do_install ;;
		2) do_start ;;
		3) do_stop ;;
		4) do_restart ;;
		5) do_status ;;
		6) do_logs ;;
		7) do_open_ui ;;
		8) do_edit_config ;;
		9) do_apikeys ;;
		w) do_wizard "openclaw onboard" "Onboard Wizard" ;;
		d) do_wizard "openclaw dashboard" "Dashboard" ;;
		c) do_wizard "openclaw configure" "Configure" ;;
		s) do_wizard "openclaw configure --section web" "Web Tools" ;;
		q) break ;;
		esac
	done
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Entry
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if [[ -z ${ZSH_VERSION:-} ]]; then
	printf "Error: requires zsh\n" >&2
	exit 1
fi

if ! command -v bsddialog >/dev/null 2>&1; then
	printf "Error: bsddialog not found (pkg install bsddialog)\n" >&2
	exit 1
fi

main_menu
