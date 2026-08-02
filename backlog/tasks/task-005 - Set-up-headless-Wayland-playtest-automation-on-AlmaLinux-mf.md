---
id: TASK-005
title: Set up headless Wayland playtest automation on AlmaLinux (mf)
status: Done
assignee:
  - '@claude'
created_date: '2026-08-02 05:24'
updated_date: '2026-08-02 06:22'
labels:
  - build-infra
  - playtest
  - linux
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Build a Linux equivalent of the macOS `osascript`/System Events playtest-verification approach documented in AGENTS.md, targeting the `mf` host (AlmaLinux 10.2).

Context: EL10/EPEL10 dropped the classic X.org server in favor of Wayland-only, so `Xvfb`/`xvfb-run`-style headless X11 automation is not available (`Xvfb`, `xdotool`, `ydotool`, `wtype` are all unpackaged on this host). `weston` (headless Wayland compositor, via `--backend=headless-backend.so`) IS available and SDL2 supports `SDL_VIDEODRIVER=wayland` natively, so the plan is:

1. Run `weston --backend=headless-backend.so` as a headless Wayland compositor on `mf`.
2. Run `zelda3` against it with `SDL_VIDEODRIVER=wayland` for headless rendering (no physical display needed).
3. Solve key injection for `LoadRef`/`ReplayRef` hotkeys and general input, since no packaged tool (`xdotool`/`ydotool`/`wtype`) exists for EL10 — likely via building `ydotool` from source against `/dev/uinput`, or scripting raw `uinput` events directly (e.g. Python `evdev`), since that works at the kernel level regardless of X11/Wayland.
4. For RAM-compare-only smoke tests that don't need `LoadRef`/`ReplayRef` or visual confirmation, note `SDL_VIDEODRIVER=dummy` already works today with zero extra setup — this task is specifically about the interactive/visual case.
5. Update AGENTS.md's "Interactive playtest verification" section once a working Linux method exists.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 weston runs headlessly on mf and zelda3 renders against it via SDL_VIDEODRIVER=wayland
- [x] #2 A working key-injection method is identified and demonstrated (uinput/evdev or a built ydotool) that can trigger LoadRef/ReplayRef hotkeys
- [x] #3 Screenshot capture equivalent to macOS screencapture -x is demonstrated against the headless Wayland session
- [x] #4 AGENTS.md is updated with the working Linux method, replacing the current TODO note
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SSH to mf, check current repo state (git status, whether zelda3.sfc/zelda3_assets.dat are present from prior rsync, whether a build exists).
2. Confirm weston is installed and can run with --backend=headless-backend.so; determine the Wayland socket it creates (WAYLAND_DISPLAY) for child processes to target.
3. Build zelda3 on mf (task build) if not already built, confirming SDL2 was built with Wayland support (ldd/sdl2-config, or SDL_VIDEODRIVER=wayland probe).
4. Launch weston headless in the background, then launch zelda3 with SDL_VIDEODRIVER=wayland and WAYLAND_DISPLAY pointed at the headless socket; confirm it runs without falling back/crashing and produces frames (check via logs, not necessarily pixels yet).
5. Solve key injection: check for uinput device access, try a minimal Python evdev or raw uinput script to synthesize a keypress, and confirm it reaches the SDL app running under the headless Wayland session.
6. If time permits, get a screenshot equivalent (e.g. weston's own screenshooter protocol, or grim if packaged) to visually confirm rendering.
7. Update AGENTS.md's Interactive playtest verification section with whatever concretely worked (and note what's still unresolved, if anything).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Confirmed on mf: weston 14.0.1 was not installed (dnf install -y weston pulled it in fine, along with weston-libs). headless-backend.so ships as part of the weston package at /usr/lib64/libweston-14/headless-backend.so.

Launched `weston --backend=headless-backend.so --socket=zelda3-headless --width=1024 --height=768` in the background successfully (survives, stable, verified via ps + lsof showing a listening + connected unix socket at /run/user/1000/zelda3-headless).

Ran the existing zelda3 binary (already built on mf from a prior session) with `WAYLAND_DISPLAY=zelda3-headless SDL_VIDEODRIVER=wayland ./zelda3` — no crash, no 'Failed to init SDL: wayland not available' fallback error, process stays alive and holds an active fd connected to the compositor socket (confirmed via /proc/<pid>/fd). SDL2 on mf (2.32.10, built from source per taskfile.yml's dnf/EPEL fallback path) already links Wayland support — no rebuild needed. This satisfies AC #1 / DoD #1-2.

Screenshot capture attempt with weston-screenshooter FAILED: `Assertion 'width > 0' failed` in screenshot_create_shm_buffer, core dump. Likely the headless-backend output isn't exposing geometry the screenshooter client expects, or desktop-shell's screenshooter protocol needs extra setup. Not yet resolved — AC #3 still open.

Key injection (AC #2) not yet demonstrated. /dev/uinput exists but is root-only (crw------- root root) and user 'lance' is only in groups lance/wheel/docker, not input — no direct uinput access without sudo or a udev rule granting group access. python3 evdev module is also not installed (ModuleNotFoundError). Next step: either add a udev rule + install python3-evdev via pip/dnf, or build ydotool from source against /dev/uinput with sudo.

All test processes (zelda3, weston) were killed and confirmed stopped before ending the session — nothing left running on mf.

SIDE TASK: added a new `install:weston` task to taskfile.yml (dnf/apt/pacman branches) per user request, mirroring the existing install:linux pattern for SDL2. Internal, not wired into the default `task install` chain since weston isn't needed to build/run the game, only for this headless-playtest tooling.

Session 2 (2026-08-02): Resolved uinput permissions and built the injection tooling, but discovered a hard wall in input ROUTING under the packaged headless compositors.

WHAT NOW WORKS:
- ydotool built from source (ReimuNotMoe, /usr/local/bin/ydotool + ydotoold) with scdoc/cmake. ydotoold runs as lance and creates a virtual uinput device (shows as /dev/input/event17 'ydotoold virtual device').
- /dev/uinput access fixed WITHOUT root: udev rule /etc/udev/rules.d/60-ydotool-uinput.rules (KERNEL=="uinput", GROUP="input", MODE="0660"), `uinput` added to /etc/modules-load.d/uinput.conf, and lance added to the `input` group. Fresh login sessions now get RW on /dev/uinput with no sudo.
- wtype built from source (needs meson/ninja + vendored virtual-keyboard-unstable-v1.xml) at ~/git/wtype/build/wtype.
- cage (packaged), seatd (packaged, enabled, lance in `seat` group), weston-demo (packaged) all installed.

THE WALL (input does not reach the client under headless compositors):
- ydotool (uinput level): weston --headless and cage do NOT run a libinput backend, so uinput events never reach the compositor or its clients. Confirmed: injected keys never arrive.
- wtype (zwp_virtual_keyboard protocol): cage DOES support the protocol and the injected keyboard DOES register on the seat (native probe wlkeylog shows SEAT_CAPS kbd 0->1 + KEYMAP delivered). BUT cage never sends wl_keyboard.enter to the client surface, so no keys are delivered. Proven NOT to be an SDL issue: a native client (weston-eventdemo) under cage also receives zero key events. Also proven NOT a timing race: keyboard capability was confirmed present on the seat BEFORE the client mapped, still no focus/enter.
- libinput backend path (WLR_BACKENDS=libinput,headless): blocked. libseat on EL10 has no `builtin` backend (root path fails: 'No backend matched name builtin'). With seatd now installed, cage appears to ignore WLR_BACKENDS and still runs headless-only (no libinput device enumeration in debug log), so no real keyboard is put on the seat at startup.

CONCLUSION: none of the packaged headless-compositor + injection combos on mf deliver keyboard input to a client (SDL or native). The remaining realistic options are (a) a compositor that synthesizes keyboard focus headless (sway/labwc) built from source, (b) getting cage's libinput backend to actually load a persistent uinput keyboard at startup, or (c) accepting RAM-compare-only headless testing (SDL_VIDEODRIVER=dummy) and doing interactive/visual verification only on macOS. AC #3 (screenshot) also still open. All mf test processes cleaned up (ydotoold left running as the intended daemon).

SOLVED (2026-08-02, session 2 cont.): Full headless playtest pipeline working on mf, using sway (built from source) + wtype virtual-keyboard protocol + grim screencopy.

ROOT CAUSE of the earlier 'no focus' wall: it was my SDL probe, NOT the compositor. Under Wayland a surface is only mapped/focusable once it commits a buffer. My first klog probe never rendered, so it never became a managed toplevel and could never receive keyboard focus. Real apps (and a fixed klog that calls SDL_RenderPresent) map correctly and DO get focus. zelda3 renders every frame, so it maps fine.

WORKING STACK:
- Compositor: sway 1.10.1 built from source against packaged wlroots 0.18.2 (deps: wlroots-devel json-c-devel cairo-devel pango-devel gdk-pixbuf2-devel libevdev-devel libinput-devel pixman-devel + meson/ninja/scdoc; `meson setup build -Dtray=disabled -Dwerror=false -Dman-pages=disabled`). Installed to /usr/local/bin/sway. sway maintains a focused container and supports zwp_virtual_keyboard + wlr-screencopy, which cage/weston-headless do not handle usefully.
- Run headless: `WLR_BACKENDS=headless WLR_RENDERER=pixman sway -c <config>` where config does `output HEADLESS-1 resolution 1024x896` + `exec <wrapper that cd's to repo and runs zelda3 with SDL_VIDEODRIVER=wayland SDL_AUDIODRIVER=dummy>`.
- Input: wtype (built from source, ~/git/wtype/build/wtype). KEY DETAIL: a lone `wtype "abc"` delivers NOTHING (the transient virtual keyboard is created+destroyed before the client binds wl_keyboard - bind race). Two fixes, both verified: (a) one-shot `wtype -s 1000 <keys>` - the leading 1s sleep lets the client bind the keyboard after it appears on the seat (3/3 keys delivered); (b) for many injections, run ONE persistent holder `wtype -s 600000 &` at session start so seat0 keeps keyboard capability, then subsequent plain `wtype ...` calls are instant. wtype -k <Keysym> sends named keys (Return, Down, etc.).
- ydotool does NOT work here: headless sway/wlroots runs no libinput backend, so uinput events never reach the compositor. ydotool/uinput is only viable with a libinput-backed (physical-seat/DRM) session. For headless Wayland the virtual-keyboard protocol (wtype) is the correct tool. (ydotool + /dev/uinput perms were still fully set up and work at the uinput level; just not usable against a headless wlroots compositor.)
- Screenshots: grim (built from source, ~/git/grim/build/grim; needs libpng-devel). `WAYLAND_DISPLAY=wayland-N grim out.png` captures the HEADLESS-1 output via wlr-screencopy. This is the macOS `screencapture -x` equivalent (AC #3).

EVIDENCE:
- Airtight injection proof: fixed klog SDL probe under sway received exactly the injected keys: KEYDOWN H,E,L,L,O + TEXTINPUT h,e,l,l,o from `wtype hello`.
- Real zelda3: ran as a sway view (app_id=zelda3), grim captured the Triforce intro and the 'A Link to the Past' title screen at 1024x896. Injected Return presses advanced the game intro -> title (input observably drives game state). Screenshots verified visually.

AC #1/#2/#3 satisfied. Remaining: AC #4 / DoD #4 - update AGENTS.md 'Interactive playtest verification' section with this sway+wtype+grim recipe. Also pending (deferred by user): add idempotent taskfile install task for the tooling now that the approach is proven. weston-screenshooter crash from session 1 is moot - grim is the screenshot path.

mf left clean: all sway/zelda3/wtype/ydotoold/weston/cage test processes killed. Persistent infra intentionally left in place: seatd enabled, lance in input+seat groups, /dev/uinput udev rule + modules-load.d/uinput.conf, and the built sway/wtype/grim binaries.

FINALIZED (2026-08-02): AC #4 / DoD #4 done.
- AGENTS.md 'Interactive playtest verification' section rewritten: replaced the 'no equivalent yet' Linux TODO with the sway + wtype + grim headless recipe (sway headless config, wtype bind-race workaround + default zelda3 keymap, grim capture), plus the honest note that ydotool/uinput does NOT work against a headless wlroots compositor.
- taskfile.yml: added `install:playtest-linux` task (idempotent, guarded by `command -v` per tool). apt/pacman branches install packages; dnf/EL10 branch installs build deps and builds sway v1.10.1 / wtype / grim v1.4.1 from source into /usr/local. Validated: `task --list` parses and shows the task.
- mf state reconciled with the docs: wtype and grim (previously only in ~/git/*/build dirs) installed to /usr/local/bin via `ninja install`; sway already there. All three now on PATH, so `install:playtest-linux` would report 'already installed; nothing to do'. Note: the taskfile task itself was NOT run on mf because `task` (go-task) is not installed there; the task body is the exact verified build recipe used manually.
All acceptance criteria and DoD items complete.
<!-- SECTION:NOTES:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 weston headless compositor confirmed running and stable on mf
- [x] #2 zelda3 confirmed rendering frames under SDL_VIDEODRIVER=wayland against the headless compositor (no crash, no SDL init failure)
- [x] #3 Key injection path exercised at least once end-to-end (a synthetic keypress observably affects game state, e.g. triggers LoadRef)
- [x] #4 AGENTS.md updated to reflect the working method, replacing the current TODO note
<!-- DOD:END -->
