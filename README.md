# Flysunaba

## OVERVIEW

`Flysunaba` is a utility to run X (or X11) applications in a rudimentary sandbox on OpenBSD, isolating them from your X session and from each other. The command is `Fsunaba`.

`Flysunaba` is a fork of [`Xsunaba`](https://github.com/morgant/Xsunaba), which was ported to OpenBSD and `doas` by Morgan Aldridge. 'Sunaba' is romaji for the Japanese word '砂場', which translates as 'sandbox' or 'sandpit'. See [FORK.md](FORK.md) for what this fork adds and fixes compared to `Xsunaba`.

The sandbox consists of:

1. A separate, less privileged, local user account under which the X application runs, restricting access to your user files (assuming appropriate permissions are set).
2. A separate X session created and rendered into a window within your running X display by `Xephyr`, one per invocation, so the application cannot snoop on `XEvents` in the parent X session, in another `Fsunaba` session, or in another application of the same session.

Limitations due to implementation via `Xephyr`:

* Hardware acceleration is not supported for X applications using OpenGL, so the sandbox only provides software rasterization via the [LLVMpipe](https://docs.mesa3d.org/drivers/llvmpipe.html) driver. This _may_ be performant enough for some 2D rendering, but 3D rendering performance will be abysmal.
* The sandbox does not provide a display manager (DM), so will not execute the sandbox user's `~/.xsession` or `~/.xinitrc`. Window managers do not run by default either, because some applications expect to be the only client; use `-w` to run one when an application needs it (see [Options](#options) and [Troubleshooting](#troubleshooting)). If specific environment configuration is necessary for an X application to run correctly in the sandbox, it is suggested to create a wrapper script to configure & execute the application, then execute the wrapper script with `Fsunaba`.

**IMPORTANT:** _`Flysunaba` reduces the blast radius of an untrusted X application. It is not a strong isolation boundary; see [SECURITY](#security)._

## WHY: X11 HAS NO GUI ISOLATION

X11 has no per-client isolation. Once an application is authorised to connect to a display, the server trusts it exactly as much as every other client on that display, and the protocol offers it the tools to prove it:

* **Read other windows and the screen**: `XGetImage` reads pixels from any drawable, including the root window, so a client can capture everything, including another application's window.
* **Log keystrokes**: the `XRecord` extension records all input, including events sent to no client, and `XInput2` raw events and `XQueryKeymap` give the same regardless of which window has focus.
* **Inject input**: `XTEST` synthesises keystrokes, clicks, and pointer motion indistinguishable from real hardware, and `XSendEvent` delivers events to any window.
* **Read the selection/clipboard**: any client can ask the selection owner for its contents, with no prompt and no audit.

This is not a bug that patches fix; it is the X11 trust model.

OpenBSD's Xenocara is a hardened X.Org build, but its hardening is about the server, not the clients. The server drops privileges to the `_x11` user, keeps a small `[priv]` child confined with [pledge(2)](https://man.openbsd.org/pledge) and [unveil(2)](https://man.openbsd.org/unveil), and disables TCP by default. All of that protects the system from a compromised *server*. It does **not** isolate clients from each other: every authenticated client still shares the display, so it can read, keylog, inject into, and screenshot every other application, exactly as on stock X.Org. OpenBSD can hand out an *untrusted* cookie through the `SECURITY` extension, but that is opt-in per client, has only two trust levels, and is not used for local applications.

The goal of `Flysunaba` is to remove that problem for the applications you run through it. Each session is a separate unprivileged user inside its own nested `Xephyr` display, so an application cannot read or interfere with your X session, with another `Fsunaba` session, or with any other application. Existing X11 applications keep working, without Wayland and without XWayland.

That GUI isolation is the main goal, but `Fsunaba` also restricts more than the display:

* **Separate user and filesystem**: the application runs as the sandbox user, not as you, so Unix permissions keep your files out of reach.
* **No audio**: the sandbox has no `sndio` cookie, so it can neither play nor record until you explicitly copy one in (see [Audio](#audio)).
* **No clipboard or selection**: nothing is shared by default; copying requires the explicit `xclip` bridge (see [Shared Selection and/or Clipboard](#shared-selection-andor-clipboard)).
* **No credentials**: a fresh, minimal environment, with its home directory as the working directory.

### Compared with Wayland

Wayland isolates the GUI for native clients, and does nothing else by itself. Applications still run as your user with full access to your files; PipeWire and PulseAudio accept any client of your user, so audio is not blocked; and the clipboard is shared across the session and readable by any client, including through `wlr-data-control`/`ext-data-control-v1`. Filesystem and audio isolation appear only when a container (Flatpak, bubblewrap) and portals are added.

* **Wayland only**: native clients cannot read each other's surfaces or input, and there is no X11 socket. But there is no user, filesystem, audio, or clipboard isolation without extra sandboxing, and X11 applications do not run.
* **Wayland with XWayland**: X11 applications keep working, but they all share one XWayland server and therefore the whole X11 problem among themselves, and XWayland carries X.Org's code and its vulnerabilities.
* **Xenocara with Flysunaba**: X11 applications keep working, and every `Fsunaba` session gets its own X server and its own unprivileged user, with audio and clipboard off by default. The cost is software rendering only (no OpenGL acceleration), no display manager, and one `doas` rule.

On OpenBSD, Xenocara is still the base graphical stack; Wayland compositors are available only as packages.

## PREREQUISITES

* OpenBSD
* [X(7)](https://man.openbsd.org/X) and [Xorg(1)](https://man.openbsd.org/Xorg) (preferably with the [xenodm(1)](https://man.openbsd.org/xenodm) display manager)
* [ksh(1)](https://man.openbsd.org/ksh)
* [doas(1)](https://man.openbsd.org/doas)
* [Xephyr(1)](https://man.openbsd.org/Xephyr)
* [xauth(1)](https://man.openbsd.org/xauth)
* [openssl(1)](https://man.openbsd.org/openssl)

### Optional

* [xclip(1)](https://github.com/astrand/xclip)
* [sndio(7)](https://man.openbsd.org/sndio)
* [xdotool(1)](https://github.com/jordansissel/xdotool), so application windows follow a resized sandbox display (see `-r`); without it, `-r` resizes the display only.

## INSTALLATION

To install `Fsunaba`, the manual page, create the `fsunaba` user, and update your `/etc/doas.conf` to allow your user to run applications in the sandbox without a password:

```
$ doas make install USER="$USER"
```

`make install` also rebuilds the manual page index of `${PREFIX}/man` with [makewhatis(8)](https://man.openbsd.org/makewhatis), so that `man Fsunaba` works; an already installed manual page that `man` cannot find means the index was not rebuilt, and running `doas makewhatis /usr/local/man` fixes it. `make uninstall` rebuilds the index too.

If you don't yet have an `/etc/doas.conf`, one will be created for you, but you will need explicitly specify your username when running `make install` as `root` (replacing `<username>` with your username):

```
# make install USER=<username>
```

The sandbox user needs a `doas` rule for both the normal and the amnesic user, for example:

```
permit nopass <username> as fsunaba
permit nopass <username> as fsunaba-amnesic
```

### UNINSTALLING

`make uninstall` removes the script, the manual page, the sandbox users and the `doas` rules:

```
$ doas make uninstall USER="$USER"
```

The individual `uninstall-user`, `uninstall-amnesic-user`, `uninstall-doas` and `uninstall-sndio-cookie` targets undo one piece each. All of them are safe to run again, and none of them fails when the piece is already gone. Removing a sandbox user asks before deleting its home directory, so the directory survives when the question is not answered; `make install` reuses it.

## USAGE

Prefix your X application command with `Fsunaba`, for example:

```
Fsunaba chrome --incognito &

Fsunaba firefox --private-window &

Fsunaba tor-browser
```

**NOTE:** `Fsunaba` automatically applies window geometry options for `chrome`, `chromium`, `ungoogled-chromium`, `firefox` and `tor-browser`, and gives `tor-browser` a 1000x1000 sandbox display by default so that the browser keeps its default window size and fingerprint.

### OPTIONS

```
Fsunaba [-hvrGAw] [-d display] [-s widthxheight] [-u user] command [argument ...]
```

* `-A`: run as the amnesic sandbox user and erase its home directory before and after the session. See [Amnesic Mode](#amnesic-mode).
* `-d display`: host X display to render the sandbox into. Default: `DISPLAY`.
* `-G`: pass `-no-host-grab` to `Xephyr`, so the sandbox window does not grab the keyboard and mouse.
* `-h`: show help and exit.
* `-r`: pass `-resizeable` to `Xephyr`, so the sandbox window can be resized. With [xdotool(1)](https://github.com/jordansissel/xdotool) installed, the largest application window is kept matched to the sandbox display: while a Firefox-based browser starts and whenever the display changes. Without it, only the display resizes; see [Troubleshooting](#troubleshooting).
* `-s widthxheight`: sandbox display resolution in pixels, e.g. `1280x1024`. Default: `1024x768`, reduced to the host screen's work area when that is smaller, except for [`tor-browser`](#application-defaults).
* `-u user`: sandbox user to run the command as. Default: `fsunaba`. The user must exist and must not be a member of `wheel` or `operator`, because such a user could escalate from inside the sandbox.
* `-v`: show verbose output.
* `-w`: run a window manager inside the sandbox, before the application. Default manager: `cwm`, change it with `FSUNABA_WM`. Needed for applications whose popup menus expect a window manager to handle the input focus, such as Tor Browser; see [Troubleshooting](#troubleshooting).

Each `Fsunaba` invocation gets its own X display: `Fsunaba` picks the lowest display number that is free on the host and starts `Xephyr` on it, so `Xephyr` locks that display and a second session cannot land on it. There is no fixed sandbox display number to configure. If another process takes the number first, `Fsunaba` retries with the next free one; `Xephyr`'s output is captured and only shown if no display can be started. Do not use `Xephyr -displayfd` for this: it disables the server lock and lets a second session take over a running session's display.

### APPLICATION DEFAULTS

`Fsunaba` recognizes some applications and passes the window geometry options they need so their window fits the sandbox display:

| Application | Options | Sandbox display |
| --- | --- | --- |
| `chrome`, `chromium`, `ungoogled-chromium` | `-window-size=W,H --window-position=0,0` | default |
| `firefox` | `-width W -height H` | default |
| `tor-browser` | `-width W -height H` | `1000x1000` unless `-s` or `WIDTH`/`HEIGHT` is given, capped to the host screen |

The `tor-browser` default keeps the screen size Tor Browser expects. Tor Browser ignores `-width` and `-height` under its fingerprinting protection, sizes its window from the screen and rounds its content to 200x100 steps, so the sandbox display decides how much room it takes. Use `-s` to override it.

### ADVANCED USAGE

The following environment variables may be set to override `Fsunaba`'s default behavior:

* `VERBOSE`: Set to `true` to show verbose output. Default: `false`.
* `FSUNABA_WM`: Window manager run by `-w`. Default: `cwm`.
* `FSUNABA_HOST_DISPLAY`: Host X display to render the sandbox into. Overridden by `-d`. Default: `DISPLAY`.
* `FSUNABA_USER`: Set a username to run the X application as. Overridden by `-u`. Default: `fsunaba`.
* `FSUNABA_AMNESIC_USER`: Amnesic user used by `-A`. Default: the sandbox user name followed by `-amnesic`.
* `WIDTH`: Set a custom `Xephyr` display width in pixels. Overridden by `-s`. Default: `1024`.
* `HEIGHT`: Set a custom `Xephyr` display height in pixels. Overridden by `-s`. Default: `768`.
* `FSUNABA_TIMEOUT`: Seconds to wait for `Xephyr` to become ready. Default: `10`.
* `FSUNABA_XEPHYR_OPTS`: Additional options to pass to `Xephyr`. The `-r` and `-G` options append to this value. `-ac`, `-auth`, `-nolock`, `-listen` and `+iglx` are refused, because each would weaken the sandbox display.

#### Amnesic Mode

The `-A` option runs the application as a separate amnesic user and empties that user's home directory before and after the session, so each session starts with nothing but its own session authority file and leaves nothing behind.

Create the amnesic user once (default name `fsunaba-amnesic`):

```
doas make install-amnesic-user
```

Then run, for example:

```
Fsunaba -A firefox --private-window
```

Use `FSUNABA_AMNESIC_USER` or `make install-amnesic-user FSUNABA_AMNESIC_USER=<user>` to choose a different name.

`Fsunaba` erases everything inside the amnesic home, including hidden files and files the application made read-only, and reports an error if anything survives. The home directory itself is kept, because it is owned by the amnesic user and only `root` could remove the directory entry from `/home`.

*IMPORTANT:* Amnesic mode only erases the amnesic user's home directory. Data written elsewhere (e.g. `/tmp`) and the sandbox's full network access are unaffected. `Fsunaba` runs only as an unprivileged user, and amnesic mode in addition refuses to run as you or with your user identifier, as `root`, on a home that is a symbolic link, on a home that is not owned by the amnesic user, on a home outside `/home`, or on a home that resolves to your own home directory. Nothing is erased when it refuses.

#### Alternate and/or Multiple Sandbox Users

If you would like your sandbox user to have a different username than `fsunaba` or would like to create multiple sandbox users, you can create them
as follows (replacing `<sandbox_user>` with your preferred sandbox username):

```
doas make install-user FSUNABA_USER=<sandbox_user>
doas make install-doas FSUNABA_USER=<sandbox_user> USER=$USER
```

You can then execute `Fsunaba` with your custom sandbox user, for example (replacing `<sandbox_user>`):

```
FSUNABA_USER=<sandbox_user> Fsunaba firefox --private-window &
```

#### Shared Selection and/or Clipboard

If you want to copy the sandbox user's X selection and/or clipboard to your user's selection and/or clipboard, this can be done with `xclip`. After starting an application in your `Fsunaba` sandbox, note the sandbox display it reports when run with `-v` (for example `:77`), then do the following (replacing `<sandbox_user>` and `:N` with the sandbox user and display):

##### Selection

```
doas -u <sandbox_user> xclip -display :N -out | xclip -in
```

##### Clipboard

```
doas -u <sandbox_user> xclip -display :N -selection clipboard -out | xclip -selection clipboard -in
```

#### Shared Files

If you want to share some files between your user and the `fsunaba` user, it is suggested that you create a directory owned by the `fsunaba` user and grant group access to it to your user's group (generally the same as your user's name). It is best to only move specific files into and out of this shared directory as needed, not permanently store data in it, as any X application run using `Fsunaba` will have access to it.

*IMPORTANT:* This will weaken the security of your sandbox!

#### Audio

By default, X applications executed in the sandbox will not have access to play or record audio for privacy reasons. Per the ['Authentication' section in sndio(7)](https://man.openbsd.org/sndio#Authentication), one can copy their `~/.sndio/cookie` file to the `fsunaba` user to allow it to access [sndiod(8)](https://man.openbsd.org/sndiod) simultaneously:

```
doas -u fsunaba mkdir -p ~fsunaba/.sndio
doas install -o fsunaba -g fsunaba -m 600 ~${USER}/.sndio/cookie ~fsunaba/.sndio/
```

The Makefile also provides an `install-sndio-cookie` target to automate this:

```
doas make install-sndio-cookie USER=$USER
```

*IMPORTANT:* If you have enabled audio recording in the OpenBSD kernel using [sysctl(8)](https://man.openbsd.org/sysctl) or [sysctl.conf(5)](https://man.openbsd.org/sysctl.conf) (`kern.audio.record=1`), applications run in the sandbox will be able to access your microphone.

If audio is failing to play from applications within the Flysunaba sandbox, first confirm the following:

1. You have played _any_ audio as your primary user, which will have created the sndio(7) cookie
2. You have copied, _not_ symlinked, your user's `~/.sndio/cookie` to the Flysunaba user
3. The Flysunaba user's `~/.sndio/cookie` is owned by the correct user (e.g. `fsunaba:fsunaba`) and _only_ the owner has read & write permissions (i.e. `600`)
4. That the contents of your user's and the Flysunaba user's `~/.sndio/cookie` files are identical

## TROUBLESHOOTING

* `_XSERVTransSocketUNIXCreateListener: ...SocketCreateListener() failed` or `_XSERVTransMakeAllCOTSServerListeners: server already running`: `Xephyr` prints these when the display number it was given was taken between the check and the start. `Fsunaba` retries with the next free number and captures that output, so you only see it if no display can be started.
* `Crash Annotation GraphicsCriticalError: |[0][GFX1-]: RenderCompositorSWGL failed mapping default framebuffer, no dt`: harmless warning from Firefox-based browsers (including Tor Browser) using the software compositor, which is always the case in the sandbox because there is no hardware acceleration. It appears while a window or popup is unmapped, for example when closing the browser, and does not affect it. Newer Firefox releases no longer print it.
* Amnesic mode reports that the home is not empty after erasing: something is still writing to the amnesic home, usually an application that outlived its launcher. Close it and run `Fsunaba -A` again.
* Tor Browser or Firefox menus (the hamburger menu, bookmarks, the security panel) close as soon as the mouse reaches them, and the cursor turns into a large X: by default the sandbox runs no window manager, so the X server moves the input focus with the pointer and the application closes its own popup when the popup takes that focus. Run `Fsunaba -w tor-browser` to put a window manager in the sandbox, which handles the focus and keeps those popups open. The X cursor is the server's default root cursor; `Fsunaba` sets the usual arrow, but that alone does not keep a popup open.
* Resizing the sandbox window with `-r` resizes the sandbox display, but `Xephyr` cannot resize application windows, so on its own the application keeps its size. With `xdotool` installed, `Fsunaba` resizes the largest application window to the display while a Firefox-based browser starts and whenever the display changes. Without `xdotool`, a window follows only if the window manager resizes its clients on a screen change; the default `cwm` does not, so use a manager that does (set `FSUNABA_WM`) or start at the wanted size with `-s`.
* Tor Browser leaves a strip of the sandbox background below its window: its fingerprinting protection sizes the window from the screen, ignores `-width` and `-height`, and always leaves room for window decorations that `cwm` does not draw. With `xdotool` installed `Fsunaba` enlarges the window to fill the display; without it, run a window manager that draws a title bar (`FSUNABA_WM=fvwm Fsunaba -w tor-browser`), which uses that reserved room and looks better. `fvwm` switches workspace when the pointer reaches a screen edge; add `EdgeScroll 0 0` to its configuration to disable that.

## SECURITY

`Fsunaba` is not a strong isolation boundary. Keep the following in mind:

* The sandbox user can read any file on the system that its permissions allow, and it has full network access. Do not run untrusted applications and assume your data is safe.
* `Fsunaba` stores its X authority file in a private, mode `700` temporary directory, and removes it, along with all authentication cookies, when the application exits or the utility is interrupted. The sandbox cookie is kept per session in `~fsunaba/.fsunaba/Xauthority.N`, mode `600`, never in the sandbox user's shared `~/.Xauthority`.
* The authentication cookie is fed to `xauth` through a pipe instead of the command line, because process arguments are readable by every local user on OpenBSD.
* The sandboxed application runs with a minimal environment (`DISPLAY`, `HOME`, `LOGNAME`, `USER`, `XAUTHORITY`, `PATH`), with its home directory as the working directory, with its arguments unchanged, and with `umask 077`, so the files it creates are private.
* The optional `xdotool` helper that makes the largest window follow `-r` runs inside the sandbox as the sandbox user, like the application, and talks only to the sandbox display; it cannot reach your X session.
* `make install` validates the sandbox username and `/etc/doas.conf`, edits the `doas.conf` rules idempotently through a renamed copy, so an interrupted run cannot leave a partial rule behind, and makes the sandbox user's home directory non-writable by group and others.
* Amnesic mode erases the contents of the amnesic home but cannot remove the home directory itself, and never touches data outside it.

### What a Malicious Application Can Still Do

`Fsunaba` limits what an application reaches, it does not stop a hostile one. The application runs with the full privileges of the sandbox user and can:

* **Read whatever the sandbox user can read**, including world-readable files in your home, everything under `/etc` and `/tmp`, and its own home directory. A mode `700` home keeps your files out of reach.
* **Write to its home and `/tmp`**, so it can plant files for you to open later, and fill your disk.
* **Reach the network**, including your LAN and services listening on `localhost`, and exfiltrate anything it read.
* **Read another session's cookie file.** Sessions that share a sandbox user also share that user, its home directory and its user identifier, so one can read another session's cookie file and reach its display. Give each concurrent session a different `-u` sandbox user when they must not reach each other; amnesic mode shares one home and is meant for one session at a time.
* **Attack `Xephyr` and the X server**, which parse the application's X protocol traffic while running with *your* privileges; a memory-safety bug there is a way out of the sandbox. OpenBSD's `pledge(2)`/`unveil(2)` reduce that surface but do not remove it.
* **Grab the host keyboard** while the sandbox window holds the keyboard grab, and read the sandbox clipboard. `-G` prevents the grab.
* **Exhaust resources** with processes, memory, or disk, and leave processes running after the launcher exits.
* **Exploit the kernel**; a local privilege escalation bug is not contained by any of this.
* **Abuse bridges you enable**: the sndio cookie (audio, and the microphone with `kern.audio.record=1`), shared directories, and the clipboard.

It cannot use `doas`: the rules let you become the sandbox user, not the reverse.

## HISTORY

`Flysunaba` is a fork of `Xsunaba`, which is based on [a script by Milosz Galazka](https://blog.sleeplessbeastie.eu/2013/07/19/how-to-create-browser-sandbox/) (see [Internet Archive's Wayback Machine archive](https://web.archive.org/web/20210115000000*/https://blog.sleeplessbeastie.eu/2013/07/19/how-to-create-browser-sandbox/)) and ported to [OpenBSD](http://www.openbsd.org/) and `doas` by Morgan Aldridge. Milosz granted permission for this implementation to be released under the MIT license.

## LICENSE

Released under the [MIT License](LICENSE) by permission.
