#!/usr/bin/env bash
# Fedora KDE virtual machine on an Apple Silicon Mac, for building and trying the
# Absolute surface before it goes onto the physical Fedora partition.
#
# Uses Homebrew's QEMU with the Hypervisor framework, Fedora's aarch64 cloud image
# and a cloud-init seed. Everything lives under the VM directory; nothing is
# written elsewhere on the Mac.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="${ABSOLUTE_VM_DIR:-$HOME/.local/share/absolute/vm}"
RELEASE=44
IMAGE_NAME="Fedora-Cloud-Base-Generic-44-1.7.aarch64.qcow2"
IMAGE_URL="https://dl.fedoraproject.org/pub/fedora/linux/releases/$RELEASE/Cloud/aarch64/images/$IMAGE_NAME"
CHECKSUM_URL="https://dl.fedoraproject.org/pub/fedora/linux/releases/$RELEASE/Cloud/aarch64/images/Fedora-Cloud-$RELEASE-1.7-aarch64-CHECKSUM"
DISK="$VM_DIR/absolute.qcow2"
DISK_SIZE="${ABSOLUTE_VM_DISK:-48G}"
SEED="$VM_DIR/seed.iso"
EFI_CODE="${ABSOLUTE_EFI_CODE:-/opt/homebrew/share/qemu/edk2-aarch64-code.fd}"
EFI_VARS="$VM_DIR/efi-vars.fd"
KEY="$VM_DIR/id_ed25519"
PIDFILE="$VM_DIR/qemu.pid"
QMP="$VM_DIR/qmp.sock"
SERIAL_LOG="$VM_DIR/serial.log"
SHOTS="$VM_DIR/shots"
SSH_PORT="${ABSOLUTE_VM_SSH_PORT:-2222}"
VM_USER=romil
VM_PASSWORD=absolute
CPUS="${ABSOLUTE_VM_CPUS:-8}"
MEMORY="${ABSOLUTE_VM_MEMORY:-12G}"
WIDTH="${ABSOLUTE_VM_WIDTH:-2880}"
HEIGHT="${ABSOLUTE_VM_HEIGHT:-1800}"

usage() {
    cat <<EOF
Usage: script/vm_fedora.sh COMMAND [ARGS]

  create            Download Fedora $RELEASE (aarch64 cloud image), verify it, build the
                    disk, SSH key and cloud-init seed. Safe to rerun; keeps an existing disk.
  start [--window]  Boot the machine headless (default) or with a window on this Mac.
  stop              Ask the machine to power off; force it after 60 s.
  status            Show whether it is running and how to reach it.
  ssh [COMMAND]     Open a shell or run COMMAND inside the machine.
  push SRC DEST [RSYNC-ARGS]
                    Copy a file or directory into the machine (rsync over SSH).
  shot [NAME]       Save a PNG screenshot of the machine's display to shots/NAME.png.
  key               Send a key chord to the machine, e.g. "meta-space" or "ret".
  type TEXT         Type ASCII text into the machine.
  mouse X Y [BTN]   Move the pointer to absolute X,Y and click (left by default).
  reset             Delete the disk and seed so create starts over. Keeps the download.

Machine directory: $VM_DIR (override with ABSOLUTE_VM_DIR)
User inside: $VM_USER, password: $VM_PASSWORD, SSH on 127.0.0.1:$SSH_PORT
EOF
}

fail() { printf '%s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null || fail "Missing tool: $1 ($2)"; }

running() { [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

qmp() {
    # Send one QMP command (JSON arguments as $2) and print the reply.
    python3 - "$QMP" "$1" "${2:-{\}}" <<'PY'
import json, socket, sys
path, command, arguments = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(30)
sock.connect(path)
stream = sock.makefile("rw")
def send(obj):
    stream.write(json.dumps(obj) + "\n"); stream.flush()
    while True:
        line = stream.readline()
        if not line: raise SystemExit("QMP closed")
        reply = json.loads(line)
        if "event" in reply: continue
        return reply
stream.readline()                       # greeting
send({"execute": "qmp_capabilities"})
reply = send({"execute": command, "arguments": arguments})
if "error" in reply: raise SystemExit("QMP error: " + json.dumps(reply["error"]))
print(json.dumps(reply.get("return", {})))
PY
}

ssh_opts=(-i "$KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10)

create() {
    require qemu-system-aarch64 "brew install qemu"
    require qemu-img "brew install qemu"
    require hdiutil "part of macOS"
    [[ -f "$EFI_CODE" ]] || fail "UEFI firmware not found at $EFI_CODE"
    mkdir -p "$VM_DIR" "$SHOTS"
    if [[ ! -f "$VM_DIR/$IMAGE_NAME" ]]; then
        printf 'Downloading %s\n' "$IMAGE_NAME"
        curl -L --fail -o "$VM_DIR/$IMAGE_NAME.part" "$IMAGE_URL"
        mv "$VM_DIR/$IMAGE_NAME.part" "$VM_DIR/$IMAGE_NAME"
    fi
    curl -L --fail --silent -o "$VM_DIR/CHECKSUM" "$CHECKSUM_URL"
    expected="$(grep -E "SHA256 \($IMAGE_NAME\)" "$VM_DIR/CHECKSUM" | awk '{print $NF}')"
    actual="$(shasum -a 256 "$VM_DIR/$IMAGE_NAME" | awk '{print $1}')"
    [[ -n "$expected" && "$expected" == "$actual" ]] || fail "Checksum mismatch for $IMAGE_NAME"
    printf 'Image verified: %s\n' "$actual"
    if [[ ! -f "$KEY" ]]; then
        ssh-keygen -q -t ed25519 -N '' -C "absolute-vm" -f "$KEY"
    fi
    if [[ ! -f "$DISK" ]]; then
        qemu-img create -q -f qcow2 -F qcow2 -b "$VM_DIR/$IMAGE_NAME" "$DISK" "$DISK_SIZE"
        printf 'Disk created: %s (%s, grows on demand)\n' "$DISK" "$DISK_SIZE"
    fi
    if [[ ! -f "$EFI_VARS" ]]; then
        dd if=/dev/zero of="$EFI_VARS" bs=1m count=64 status=none
    fi
    seed_dir="$(mktemp -d "$VM_DIR/.seed.XXXXXX")"
    pubkey="$(cat "$KEY.pub")"
    cat > "$seed_dir/meta-data" <<EOF
instance-id: absolute-vm
local-hostname: absolute
EOF
    cat > "$seed_dir/user-data" <<EOF
#cloud-config
hostname: absolute
timezone: Australia/Melbourne
users:
  - name: $VM_USER
    gecos: Romil
    groups: [wheel]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: $VM_PASSWORD
    ssh_authorized_keys:
      - $pubkey
ssh_pwauth: true
growpart:
  mode: auto
  devices: ["/"]
write_files:
  - path: /etc/sddm.conf.d/absolute-vm.conf
    content: |
      [Autologin]
      User=$VM_USER
      Session=plasma
      Relogin=false
  - path: /etc/absolute-vm
    content: "This Fedora runs inside Absolute's virtual machine on the Mac.\n"
EOF
    rm -f "$SEED"
    hdiutil makehybrid -quiet -iso -joliet -default-volume-name cidata -o "$SEED" "$seed_dir"
    rm -rf "$seed_dir"
    printf 'Seed written: %s\n' "$SEED"
    printf 'Ready. Start with: bash script/vm_fedora.sh start\n'
}

start() {
    local window=false
    [[ "${1:-}" == "--window" ]] && window=true
    [[ -f "$DISK" && -f "$SEED" ]] || fail "Run create first."
    running && fail "Already running (pid $(cat "$PIDFILE"))."
    rm -f "$QMP"
    local display=(-display none -audiodev none,id=snd0)
    if [[ "$window" == true ]]; then display=(-display cocoa,show-cursor=on,zoom-to-fit=on -audiodev coreaudio,id=snd0); fi
    qemu-system-aarch64 \
        -name Absolute \
        -machine virt,highmem=on -accel hvf -cpu host -smp "$CPUS" -m "$MEMORY" \
        -drive if=pflash,format=raw,readonly=on,file="$EFI_CODE" \
        -drive if=pflash,format=raw,file="$EFI_VARS" \
        -drive if=virtio,format=qcow2,file="$DISK" \
        -drive if=virtio,format=raw,readonly=on,file="$SEED" \
        -device virtio-gpu-pci,xres="$WIDTH",yres="$HEIGHT" \
        -device virtio-keyboard-pci -device virtio-tablet-pci \
        -device virtio-rng-pci \
        -device intel-hda -device hda-duplex,audiodev=snd0 \
        -netdev user,id=net0,hostfwd=tcp:127.0.0.1:"$SSH_PORT"-:22 -device virtio-net-pci,netdev=net0 \
        "${display[@]}" \
        -qmp unix:"$QMP",server,wait=off \
        -serial file:"$SERIAL_LOG" \
        > "$VM_DIR/qemu.log" 2>&1 &
    # QEMU's own -daemonize forks after Cocoa is initialised and aborts on macOS,
    # so the machine is backgrounded here and its pid recorded.
    echo $! > "$PIDFILE"
    disown
    sleep 2
    running || fail "QEMU exited at once; see $VM_DIR/qemu.log"
    printf 'Started (pid %s). SSH: bash script/vm_fedora.sh ssh\n' "$(cat "$PIDFILE")"
}

stop() {
    running || { printf 'Not running.\n'; return 0; }
    qmp system_powerdown >/dev/null || true
    for _ in $(seq 1 60); do running || { printf 'Powered off.\n'; rm -f "$PIDFILE" "$QMP"; return 0; }; sleep 1; done
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    sleep 2
    rm -f "$PIDFILE" "$QMP"
    printf 'Forced off.\n'
}

status() {
    if running; then
        printf 'Running (pid %s). SSH: ssh -i %s -p %s %s@127.0.0.1\n' "$(cat "$PIDFILE")" "$KEY" "$SSH_PORT" "$VM_USER"
    else
        printf 'Not running. Disk: %s\n' "$([[ -f "$DISK" ]] && echo "$DISK" || echo "not created")"
    fi
}

shot() {
    running || fail "Not running."
    mkdir -p "$SHOTS"
    local name="${1:-shot-$(date +%Y%m%d-%H%M%S)}"
    local path="$SHOTS/$name.png"
    qmp screendump "{\"filename\": \"$path\", \"format\": \"png\"}" >/dev/null
    printf '%s\n' "$path"
}

send_key() {
    running || fail "Not running."
    local chord="$1" hold="${2:-100}"
    python3 - "$chord" "$hold" <<'PY' | while IFS= read -r args; do qmp send-key "$args" >/dev/null; done
import json, sys
chord, hold = sys.argv[1], int(sys.argv[2])
names = {"meta": "meta_l", "super": "meta_l", "cmd": "meta_l", "ctrl": "ctrl", "alt": "alt", "shift": "shift",
         "space": "spc", "enter": "ret", "return": "ret", "escape": "esc", "esc": "esc", "tab": "tab",
         "up": "up", "down": "down", "left": "left", "right": "right", "backspace": "backspace", "delete": "delete"}
keys = [names.get(part.lower(), part.lower()) for part in chord.split("-")]
print(json.dumps({"keys": [{"type": "qcode", "data": key} for key in keys], "hold-time": hold}))
PY
}

type_text() {
    running || fail "Not running."
    python3 - "$1" <<'PY' | while IFS= read -r args; do qmp send-key "$args" >/dev/null; done
import json, sys
text = sys.argv[1]
plain = {" ": "spc", "-": "minus", "=": "equal", "[": "bracket_left", "]": "bracket_right", ";": "semicolon",
         "'": "apostrophe", ",": "comma", ".": "dot", "/": "slash", "\\": "backslash", "`": "grave_accent"}
shifted = {"!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
           "_": "minus", "+": "equal", "{": "bracket_left", "}": "bracket_right", ":": "semicolon",
           '"': "apostrophe", "<": "comma", ">": "dot", "?": "slash", "|": "backslash", "~": "grave_accent"}
for char in text:
    if char.isalpha():
        keys = (["shift"] if char.isupper() else []) + [char.lower()]
    elif char.isdigit() or char in plain:
        keys = [plain.get(char, char)]
    elif char in shifted:
        keys = ["shift", shifted[char]]
    elif char == "\n":
        keys = ["ret"]
    else:
        continue
    print(json.dumps({"keys": [{"type": "qcode", "data": key} for key in keys], "hold-time": 40}))
PY
}

mouse() {
    running || fail "Not running."
    local x="$1" y="$2" button="${3:-left}"
    # The tablet device takes absolute coordinates in 0..32767 across the display.
    local ax=$(( x * 32767 / WIDTH )) ay=$(( y * 32767 / HEIGHT ))
    qmp input-send-event "{\"events\": [{\"type\": \"abs\", \"data\": {\"axis\": \"x\", \"value\": $ax}}, {\"type\": \"abs\", \"data\": {\"axis\": \"y\", \"value\": $ay}}]}" >/dev/null
    if [[ "$button" != move ]]; then
        qmp input-send-event "{\"events\": [{\"type\": \"btn\", \"data\": {\"down\": true, \"button\": \"$button\"}}]}" >/dev/null
        qmp input-send-event "{\"events\": [{\"type\": \"btn\", \"data\": {\"down\": false, \"button\": \"$button\"}}]}" >/dev/null
    fi
}

case "${1:-}" in
    create) create ;;
    start) start "${2:-}" ;;
    stop) stop ;;
    status) status ;;
    ssh) shift; exec ssh "${ssh_opts[@]}" "$VM_USER@127.0.0.1" "$@" ;;
    push) [[ $# -ge 3 ]] || { usage >&2; exit 2; }
          require rsync "brew install rsync"
          src="$2"; dest="$3"; shift 3
          exec rsync -az --delete -e "ssh ${ssh_opts[*]}" "$@" "$src" "$VM_USER@127.0.0.1:$dest" ;;
    shot) shot "${2:-}" ;;
    key) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; send_key "$2" "${3:-100}" ;;
    type) [[ $# -eq 2 ]] || { usage >&2; exit 2; }; type_text "$2" ;;
    mouse) [[ $# -ge 3 ]] || { usage >&2; exit 2; }; mouse "$2" "$3" "${4:-left}" ;;
    reset) running && fail "Stop the machine first."; rm -f "$DISK" "$SEED" "$EFI_VARS"; printf 'Disk, seed and firmware variables removed.\n' ;;
    --help|-h|help|"") usage ;;
    *) usage >&2; exit 2 ;;
esac
