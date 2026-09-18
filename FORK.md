# Flysunaba compared to Xsunaba

Flysunaba is a fork of [`Xsunaba`](https://github.com/morgant/Xsunaba) by Morgan
Aldridge, which itself is based on a script by Milosz Galazka. Xsunaba runs an X
application as a separate local user inside a nested `Xephyr` display; Flysunaba
keeps that design and the MIT license.

This file lists what the fork changes: what it adds, and which problems of the
original it fixes. Behavior is documented in the
[manual page](man/Fsunaba.1); this file is about the differences.

## Names

| Aspect | Xsunaba | Flysunaba |
| --- | --- | --- |
| Project | `Xsunaba` | `Flysunaba` |
| Command | `Xsunaba` | `Fsunaba` |
| Environment variables | `XSUNABA_*` | `FSUNABA_*` |
| Sandbox users | `xsunaba` | `fsunaba`, `fsunaba-amnesic` |
| Manual page | `man/Xsunaba.1` | `man/Fsunaba.1` |

## What Flysunaba has that Xsunaba does not

* **A command-line interface**: `-d display`, `-u user`, `-s widthxheight`, `-r`,
  `-G`, `-A`, `-v`, and `-h` for help, instead of configuring everything through
  environment variables.
* **Per-session display selection**: `Fsunaba` picks the lowest display number
  that is free on the host and starts `Xephyr` on it, so each invocation gets a
  locked, separate display. There is no fixed `:32` starting point.
* **Window resize follow**: with `-r` and the optional `xdotool`, the largest
  application window is resized to fill the new sandbox display when the sandbox
  window is resized, instead of leaving the application at its original size.
* **A startup handshake**: the display socket is waited for with a timeout
  (`FSUNABA_TIMEOUT`), and startup aborts if `Xephyr` exits, instead of a fixed
  one-second `sleep`.
* **Cleanup on every exit path**: a private, mode `700` temporary directory holds
  the X authority file and the `Xephyr` diagnostics, and traps on `EXIT`, `HUP`,
  `INT`, and `TERM` remove it together with both authentication cookies.
* **An explicit minimal environment**: `DISPLAY`, `HOME`, `LOGNAME`, `USER`, and
  `PATH`, with the application's working directory set to its home.
* **Input validation** of the sandbox username, width, height, and timeout before
  anything runs, with usage errors exiting `2` and runtime errors exiting `1`.
* **The application's exit status** is returned; interruption exits
  `128 + signal`.
* **Geometry hints** for `chromium`, `ungoogled-chromium`, and `tor-browser` (in
  addition to `chrome` and `firefox`), and a 1000x1000 display for `tor-browser`
  so it keeps its default window size and fingerprint.
* **Amnesic mode**: `-A` runs the application as a dedicated `fsunaba-amnesic`
  user whose home directory is emptied before and after the session, including
  hidden files, subdirectories, and files the application made read-only, with
  leftovers reported as an error.
* **A window manager on request**: `-w` runs `cwm` inside the sandbox, which is
  what applications with popup menus need; see Usability below.
* **A hardened `Makefile`**: `install-user`, `install-amnesic-user`, and
  `install-doas` validate the usernames; `install-doas` validates
  `/etc/doas.conf` with `doas -C` before touching it; the normal and amnesic
  rules are added and removed idempotently with anchored patterns; the sandbox
  home is made non-writable by group and others; `install-amnesic-user` and
  `uninstall-amnesic-user` exist; `install` and `uninstall` rebuild the manual
  page index with `makewhatis`, so `man Fsunaba` finds the page; `uninstall-user`
  and `uninstall` no longer fail when things are already gone.
* **`ksh`**, the shell that ships with OpenBSD, instead of plain `sh`, and
  `${var:-default}` instead of `${var:=default}`, with `$(...)` instead of
  backticks.
* **`Xephyr` diagnostics captured** in the private directory and shown only when
  `Xephyr` fails to start.
* A rewritten **manual page and README** covering options, environment,
  application defaults, security, and troubleshooting.

## Problems in Xsunaba fixed here

### Security

* **The X cookie was exposed in the process list.** The original ran
  `xauth add <display> . <cookie>`, so the cookie appeared in the arguments of
  `xauth` and `doas`. Process arguments are readable by every local user on
  OpenBSD, so any local account, including the sandboxed application itself,
  could read the cookie of another sandbox session and then read its windows,
  inject events, or read its clipboard. `Fsunaba` feeds the cookie to `xauth`
  through a pipe (`xauth source -`), so it never reaches a command line.
* **The application inherited the caller's working directory.** A normal home is
  mode `700`, so the sandbox user cannot read it: `getcwd()` fails and utilities
  that resolve relative paths misbehave. `Fsunaba` starts the application in its
  home directory.
* **Arguments were re-split by the shell.** The original assembled
  `APPLICATION="$@"` and ran `... $APPLICATION`, so an argument containing a
  space became several arguments, and a glob such as `*` expanded to files in the
  caller's directory. `Fsunaba` passes `"$@"` through unchanged.
* **The authority file was left in your home.** The original used
  `~/.Xauthority-xsunaba`, removed only its entries, and never deleted the file,
  which after an interrupted run could still hold a valid cookie. `Fsunaba`
  keeps its authority file in the private temporary directory.
* **The environment was whatever `doas` left over**, without `HOME`, `LOGNAME`,
  `USER`, or `PATH` spelled out.
* **An interrupted run left `Xephyr` and the cookies behind**, because the script
  installed no signal handlers: killing it left the sandbox display running.
* **`Makefile`:** `uninstall-doas` used `grep -p`, which OpenBSD `grep` does not
  support, so removing a rule always failed; `install-doas` chowned and chmodded
  an existing `/etc/doas.conf` unconditionally, never validated it, and detected
  existing rules with an unanchored `grep` that a longer username such as
  `xsunaba2` defeated; usernames were never validated.

### Reliability

* **No error checking.** A missing sandbox user, a failed `xauth`, or an `Xephyr`
  that died at startup all went unnoticed, and the application's exit status was
  discarded in favour of the final `xauth remove`.
* **The sandbox display was fixed**: the original always started at `:32` and
  only skipped displays whose socket already existed. `Fsunaba` picks the lowest
  free display number, skipping the host display, lock files, and sockets, starts
  `Xephyr` on it so the number is locked, and retries with the next free number
  if another process takes it first.
* **The fixed `sleep 1`** either wasted time or started the application before
  the display was ready.
* **`uninstall-user` and `uninstall`** failed when the user or the installed
  files were already absent.

### Usability

* **Popup menus closed as soon as the pointer entered them**, and the pointer
turned into a large X over them, in Firefox-based browsers. Without a window
manager the X server keeps `PointerRoot` focus, so a popup that takes the focus
makes the browser close it, and a popup with no cursor of its own inherits the
server's default root cursor. Flysunaba sets that root cursor itself and offers
`-w` to run a window manager (`cwm` by default) in the sandbox, which handles
the focus and keeps menus, bookmarks and panels open. Note that a window manager
that Firefox auto-detects as pointer-focus (`twm`, `sawfish`, `fvwm`) makes it
switch to its own popup pointer grab instead, a path that is broken in older ESR
releases, so `cwm` is the default on purpose.

## Not changed

* The two-part sandbox (a separate local user plus a nested `Xephyr` display),
  the `doas`-based privilege boundary, and the MIT license.
* No network, firewall, or `pf` features, and no compiled code: the project stays
  a `ksh` script plus a `Makefile`.
