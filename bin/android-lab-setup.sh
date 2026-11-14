#!/usr/bin/env bash
#
# android-lab-setup.sh — install a headless Android emulator on lab01 that
# Claude can drive through `droid`, plus the JADX engine REA uses to read APKs.
#
#   android-lab-setup.sh            check, install what is missing, create the AVD
#   android-lab-setup.sh --check    only report what is missing; change nothing
#
# Everything lands under $HOME, matching the rest of lab01 (`sudo -n` fails
# there). The few things that genuinely need root -- /dev/kvm access and the
# emulator's shared libraries -- are printed as commands to run once, in person.
# Safe to re-run: each step skips itself when already done.

set -euo pipefail

OPT="${OPT:-$HOME/opt}"
SDK="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
LAB="${ANDROID_LAB:-$HOME/android-lab}"
AVD_NAME="${AVD_NAME:-lab01-play}"
# Google Play image: needed to install apps from the Play Store. API 34 is a
# well-trodden x86_64 Play image; override if Google retires it.
SYSIMG="${SYSIMG:-system-images;android-34;google_apis_playstore;x86_64}"
CMDLINE_TOOLS_URL="${CMDLINE_TOOLS_URL:-https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip}"
JDK_URL="${JDK_URL:-https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jdk/hotspot/normal/eclipse}"
# Pinned by REA (src/android/JadxRelease.ts); keep the two in step.
JADX_JAR_URL="https://github.com/1013503897/jadx-headless-mcp/releases/download/v0.7.1/jadx-headless-mcp-0.7.1-all.jar"
JADX_JAR_SHA256="6e5eacf500b64292bfb73c49797c1958f6ee44646e43e868039ae7feb573ff75"
JADX_DIR="$HOME/.local/share/rea/android"

check_only=0
[[ "${1:-}" == --check ]] && check_only=1

say()  { printf '%s\n' "$*"; }
ok()   { printf '  ok    %s\n' "$*"; }
miss() { printf '  MISS  %s\n' "$*"; missing=1; }
root_steps=()

# --- preflight: things only root can fix --------------------------------------
missing=0
say "preflight"

[[ "$(uname -m)" == x86_64 ]] && ok "x86_64 CPU" \
  || { say "  FAIL  $(uname -m): the Play Store emulator image needs x86_64"; exit 1; }

if [[ -r /dev/kvm && -w /dev/kvm ]]; then
  ok "/dev/kvm usable"
elif [[ -e /dev/kvm ]]; then
  miss "/dev/kvm exists but $USER cannot open it"
  root_steps+=("sudo usermod -aG kvm $USER     # then log out and back in")
else
  miss "/dev/kvm absent -- enable VT-x/AMD-V in BIOS, or nested virtualisation if lab01 is a VM"
fi

mem_gb=$(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo)
(( mem_gb >= 8 )) && ok "${mem_gb} GB RAM" || miss "${mem_gb} GB RAM; the emulator wants 8+ (it takes ~3)"

free_gb=$(df -Pk "$HOME" | awk 'NR==2 {printf "%d", $4/1048576}')
(( free_gb >= 20 )) && ok "${free_gb} GB free in \$HOME" || miss "${free_gb} GB free in \$HOME; need ~20"

# Shared libraries the emulator binary links against even with -no-window.
for lib in libpulse.so.0 libnss3.so libxkbfile.so.1 libXcomposite.so.1 libXcursor.so.1 libXdamage.so.1 libXtst.so.6 libxkbcommon.so.0; do
  ldconfig -p 2>/dev/null | grep -q "$lib" || { missing_libs=1; break; }
done
if [[ -n "${missing_libs:-}" ]]; then
  miss "emulator shared libraries"
  root_steps+=("sudo apt-get install -y libpulse0 libnss3 libxkbfile1 libxcomposite1 libxcursor1 libxdamage1 libxtst6 libxkbcommon0 libgl1 procps unzip curl python3")
else
  ok "emulator shared libraries"
fi

command -v ps >/dev/null && ps -o pid= -p $$ >/dev/null 2>&1 && ok "procps ps (REA needs it)" \
  || { miss "procps-compatible ps"; root_steps+=("sudo apt-get install -y procps"); }

if command -v node >/dev/null; then
  ok "node $(node --version) (REA needs 22.23.4+, 24.22.1+ or 26.12.1+)"
else
  miss "node -- REA needs Node.js 22.23.4+ / 24.22.1+ / 26.12.1+"
fi

# --- user-space installs -------------------------------------------------------
say ""
say "installs (under \$HOME)"
JAVA_HOME="$OPT/jdk"
SDKMANAGER="$SDK/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="$SDK/cmdline-tools/latest/bin/avdmanager"

[[ -x "$JAVA_HOME/bin/javac" ]] && ok "JDK at $JAVA_HOME" || miss "JDK 21"
[[ -x "$SDKMANAGER" ]]           && ok "Android cmdline-tools" || miss "Android cmdline-tools"
[[ -x "$SDK/emulator/emulator" ]] && ok "emulator" || miss "emulator + platform-tools + Play system image"
[[ -f "$HOME/.android/avd/$AVD_NAME.ini" ]] && ok "AVD $AVD_NAME" || miss "AVD $AVD_NAME"
[[ -f "$JADX_DIR/jadx-headless-mcp-0.7.1-all.jar" ]] && ok "jadx-headless-mcp jar" || miss "jadx-headless-mcp jar"

if (( check_only )); then
  (( ${#root_steps[@]} )) && { say ""; say "run once, in person, as root:"; printf '  %s\n' "${root_steps[@]}"; }
  exit $missing
fi

if (( ${#root_steps[@]} )); then
  say ""
  say "These need root and must be done in person first (sudo cannot be driven over SSH here):"
  printf '  %s\n' "${root_steps[@]}"
  say "Then re-run this script."
  exit 1
fi

mkdir -p "$OPT" "$SDK" "$LAB" "$JADX_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

if [[ ! -x "$JAVA_HOME/bin/javac" ]]; then
  say "-> JDK 21 (Temurin)"
  curl -fL -o "$tmp/jdk.tgz" "$JDK_URL"
  mkdir -p "$JAVA_HOME"
  tar -xzf "$tmp/jdk.tgz" -C "$JAVA_HOME" --strip-components=1
fi
export JAVA_HOME PATH="$JAVA_HOME/bin:$PATH"

if [[ ! -x "$SDKMANAGER" ]]; then
  say "-> Android cmdline-tools"
  curl -fL -o "$tmp/clt.zip" "$CMDLINE_TOOLS_URL"
  unzip -q "$tmp/clt.zip" -d "$tmp/clt"
  mkdir -p "$SDK/cmdline-tools"
  rm -rf "$SDK/cmdline-tools/latest"
  mv "$tmp/clt/cmdline-tools" "$SDK/cmdline-tools/latest"
fi

if [[ ! -x "$SDK/emulator/emulator" || ! -d "$SDK/${SYSIMG//;//}" ]]; then
  say "-> SDK packages (several GB; accepting Google's SDK licences)"
  yes | "$SDKMANAGER" --sdk_root="$SDK" --licenses >/dev/null
  "$SDKMANAGER" --sdk_root="$SDK" "platform-tools" "emulator" "$SYSIMG"
fi

if [[ ! -f "$HOME/.android/avd/$AVD_NAME.ini" ]]; then
  say "-> AVD $AVD_NAME"
  echo no | ANDROID_SDK_ROOT="$SDK" "$AVDMANAGER" create avd -n "$AVD_NAME" -k "$SYSIMG" -d pixel_6
  cfg="$HOME/.android/avd/$AVD_NAME.avd/config.ini"
  # 3 GB RAM, room for a few apps, hardware keyboard so `droid type` is reliable.
  sed -i -e '/^hw.ramSize=/d' -e '/^disk.dataPartition.size=/d' -e '/^hw.keyboard=/d' "$cfg"
  printf 'hw.ramSize=3072\ndisk.dataPartition.size=8G\nhw.keyboard=yes\n' >>"$cfg"
fi

if [[ ! -f "$JADX_DIR/jadx-headless-mcp-0.7.1-all.jar" ]]; then
  say "-> jadx-headless-mcp (pinned, checksum-verified)"
  curl -fL -o "$tmp/jadx.jar" "$JADX_JAR_URL"
  echo "$JADX_JAR_SHA256  $tmp/jadx.jar" | sha256sum -c - >/dev/null \
    || { say "  FAIL  jadx jar checksum mismatch -- not installing it"; exit 1; }
  mv "$tmp/jadx.jar" "$JADX_DIR/jadx-headless-mcp-0.7.1-all.jar"
fi

env_file="$LAB/env.sh"
cat >"$env_file" <<EOF
# Sourced by droid and by ~/.bashrc. Generated by android-lab-setup.sh.
export JAVA_HOME="$JAVA_HOME"
export ANDROID_SDK_ROOT="$SDK"
export ANDROID_AVD_NAME="$AVD_NAME"
export REA_ADB_PATH="$SDK/platform-tools/adb"
export REA_JADX_MCP_JAR="$JADX_DIR/jadx-headless-mcp-0.7.1-all.jar"
export PATH="\$JAVA_HOME/bin:\$ANDROID_SDK_ROOT/platform-tools:\$ANDROID_SDK_ROOT/emulator:\$PATH"
EOF
grep -qF "$env_file" "$HOME/.bashrc" 2>/dev/null \
  || printf '\n[ -f "%s" ] && . "%s"\n' "$env_file" "$env_file" >>"$HOME/.bashrc"

say ""
say "done. Next: see docs/ANDROID_LAB.md step 3 (first boot and Play Store sign-in)."
