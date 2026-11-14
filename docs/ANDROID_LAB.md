# Android emulator on lab01

A headless Android phone that lab01's Claude Code can open apps on, look at,
tap through, and pull app files from -- plus REA, so Claude can read how an app
works. First use: the Astoria Lighting app (`com.astoria.lighting`), to build a
Home Assistant integration for the Wi-Fi controller.

| Path | Purpose |
|---|---|
| `bin/android-lab-setup.sh` | One-time install under `$HOME`. `--check` reports without changing anything. |
| `bin/droid` | The verbs Claude uses: `start`, `screen`, `tap`, `type`, `shot`, `pull-apk`, ... |

## Why lab01, and why this shape

- **lab01 is on the home LAN, next to the lighting controller.** Whatever REA
  finds about the Wi-Fi protocol can be tested from lab01 directly, and Home
  Assistant will talk to the controller from the same network.
- **The worker is lab01's own Claude Code**, same reasoning as the task queue:
  cloud sessions cannot reach the tailnet or the LAN.
- **`droid` has no raw shell passthrough.** Granting `Bash(droid:*)` gives
  Claude tap/type/screenshot/pull and nothing broader. adb stays bound to
  lab01's localhost; it is never exposed on the network.

## Step 0 -- check

    git -C ~/src/lab01-queue pull
    install -m 755 ~/src/lab01-queue/bin/droid ~/src/lab01-queue/bin/android-lab-setup.sh ~/bin/
    android-lab-setup.sh --check

Hard requirements: an x86_64 CPU and `/dev/kvm`. If lab01 is itself a VM,
nested virtualisation must be on at the hypervisor; without KVM the emulator
is too slow to use.

## Step 1 -- root steps, in person

`--check` prints the exact commands. Typically:

    sudo usermod -aG kvm doug        # then log out and back in
    sudo apt-get install -y libpulse0 libnss3 libxkbfile1 libxcomposite1 \
        libxcursor1 libxdamage1 libxtst6 libxkbcommon0 libgl1 procps unzip curl python3

REA also needs Node.js 22.23.4+ (or 24.22.1+ / 26.12.1+).

## Step 2 -- install (no sudo)

    android-lab-setup.sh

Downloads a JDK, the Android SDK, the Google Play system image (several GB)
and REA's checksum-pinned JADX engine; creates AVD `lab01-play`; writes
`~/android-lab/env.sh` and sources it from `~/.bashrc`.

## Step 3 -- first boot and Google sign-in (you, once)

The Play Store needs a Google account, and Claude should not type your
password. **Use a spare Google account**, not your main one.

    droid start

Then from Beastly, follow `droid view` (scrcpy over an SSH tunnel) to see the
screen, sign in to the Play Store, and install **Astoria Lighting**. Sign in to
the Astoria app too if you want Claude to watch it work. Quickboot keeps the
sign-in across `droid stop`/`droid start`.

## Step 4 -- REA

    npx rea-agents setup                     # choose Claude Code, approve
    rea doctor --provider jadx --json        # should report available

`REA_ADB_PATH` and `REA_JADX_MCP_JAR` come from `~/android-lab/env.sh`. If the
doctor check says they are missing, add both to REA's MCP registration env.

## Step 5 -- use it

Interactively on lab01 (or `claude remote-control` in the repo folder to follow
it from the Claude app):

    claude
    > droid start, pull the Astoria Lighting APK, and use REA to find out how
      the app sends commands to the controller over Wi-Fi

Queued from the phone:

    ct -n -t 'Bash(droid:*)' "droid start, open com.astoria.lighting and describe its screens"

## Known limits

- **No Bluetooth in the emulator.** Fine for the Wi-Fi path, which is the one
  in use.
- **Emulator networking is NAT'd.** The app inside can reach LAN addresses
  outbound, but broadcast/mDNS discovery of the controller may fail from inside
  the emulator. That limits watching the app live, not the integration --
  lab01 itself is on the LAN.
- **Static analysis first.** REA reading the APK is the main source of truth;
  watching the running app is a cross-check.
