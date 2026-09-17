# Flysunaba

## OVERVIEW

`Flysunaba` is a utility to run X (or X11, if you prefer) applications in a rudimentary sandbox to limit access to your files and XEvents (especially keyboard input.) The command is `Fsunaba`.

`Flysunaba` is a fork of [`Xsunaba`](https://github.com/morgant/Xsunaba), which was ported to OpenBSD and `doas` by Morgan Aldridge. 'Sunaba' is romaji for the Japanese word '砂場', which translates as 'sandbox' or 'sandpit'. See [FORK.md](FORK.md) for what this fork adds and fixes compared to `Xsunaba`.

The 'sandbox' consists of:

1. A separate, less privileged, local user account under which the X application will be executed, restricting access to your user files (assuming appropriate permissions are set)
2. A separate X session created and rendered into a window within your running X display by `Xephyr`, preventing the sandboxed X application from snooping on XEvents in the parent X session & display

**IMPORTANT:** _This **DOES NOT** guarantee access is prevented outside the sandbox user and X display, but should be at least marginally safer._

For those using `Fsunaba` under OpenBSD, some X applications in ports utilize the [pledge(2)](https://man.openbsd.org/pledge) & [unveil(2)](https://man.openbsd.org/unveil) functions to further restrict uneccessary operations and access to the filesystem, network, etc.

Limitations due to implementation via `Xephyr`:

* Hardware acceleration is not supported for X applications using OpenGL, so the sandbox only provides software rasterization via the [LLVMpipe](https://docs.mesa3d.org/drivers/llvmpipe.html) driver. This _may_ be performant enough for some 2D rendering, but 3D rendering performance will be abysmal.
* The sandbox does not provide a display manager (DM), so will not execute the sandbox user's `~/.xsession`, `~/.xinitrc`, nor initialize a window manager (WM). If specific environment configuration is necessary for an X application to run correctly in the sandbox, it is suggested to create a wrapper script to configure & execute the application, then execute the wrapper script with `Fsunaba`.

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
* `-r`: pass `-resizeable` to `Xephyr`, so the sandbox window is resizeable.
* `-s widthxheight`: sandbox display resolution in pixels, e.g. `1280x1024`. Default: `1024x768`, except for [`tor-browser`](#application-defaults).
* `-u user`: sandbox user to run the command as. Default: `fsunaba`.
* `-v`: show verbose output.
* `-w`: run a window manager inside the sandbox, before the application. Default manager: `cwm`, change it with `FSUNABA_WM`. Needed for applications whose popup menus expect a window manager to handle the input focus, such as Tor Browser; see [Troubleshooting](#troubleshooting).

`Xephyr` selects an unused display itself and reports it back to `Fsunaba`, so there is no fixed sandbox display number to configure. While searching for a free display, `Xephyr` reports an error for every display that is already in use (for example `server already running` for your own display); `Fsunaba` captures that output and only shows it if `Xephyr` fails to start.

### APPLICATION DEFAULTS

`Fsunaba` recognizes some applications and passes the window geometry options they need so their window fits the sandbox display:

| Application | Options | Sandbox display |
| --- | --- | --- |
| `chrome`, `chromium`, `ungoogled-chromium` | `-window-size=W,H --window-position=0,0` | default |
| `firefox` | `-width W -height H` | default |
| `tor-browser` | `-width W -height H` | `1000x1000` unless `-s` or `WIDTH`/`HEIGHT` is given |

The `tor-browser` default is chosen to match Tor Browser's own default 1000x1000 window and its 200x100 letterboxing steps, so the browser keeps its usual fingerprint. Use `-s` to override it.

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
* `FSUNABA_XEPHYR_OPTS`: Additional options to pass to `Xephyr`. The `-r` and `-G` options append to this value.

#### Amnesic Mode

The `-A` option runs the application as a separate amnesic user and empties that user's home directory before and after the session, so each session starts with an empty home and leaves nothing behind.

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

*IMPORTANT:* Amnesic mode only erases the amnesic user's home directory. Data written elsewhere (e.g. `/tmp`) and the sandbox's full network access are unaffected. `Fsunaba` refuses to run amnesic mode as root, against your own account, against `root`, or when the amnesic home is not under `/home`.

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

If you want to share some files beween your user and the `fsunaba` user, it is suggested that you create a directory owned by the `fsunaba` user and grant group access to it to your user's group (generally the same as your user's name). It is best to only move specific files into and out of this shared directory as needed, not permanently store data in it, as any X application run using `Fsunaba` will have access to it.

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
4. That there contents of your user's and the Flysunaba user's `~/.sndio/cookie` files are identical

## TROUBLESHOOTING

* `_XSERVTransSocketUNIXCreateListener: ...SocketCreateListener() failed` or `_XSERVTransMakeAllCOTSServerListeners: server already running`: `Xephyr` prints these while it probes displays that are already in use, starting with your own. `Fsunaba` captures that output, so you only see it if `Xephyr` actually fails to start.
* `Crash Annotation GraphicsCriticalError: |[0][GFX1-]: RenderCompositorSWGL failed mapping default framebuffer, no dt`: harmless warning from Firefox-based browsers (including Tor Browser) using the software compositor, which is always the case in the sandbox because there is no hardware acceleration. It appears while a window or popup is unmapped, for example when closing the browser, and does not affect it. Newer Firefox releases no longer print it.
* Amnesic mode reports that the home is not empty after erasing: something is still writing to the amnesic home, usually an application that outlived its launcher. Close it and run `Fsunaba -A` again.
* Tor Browser or Firefox menus (the hamburger menu, bookmarks, the security panel) close as soon as the mouse reaches them, and the cursor turns into a large X: by default the sandbox runs no window manager, so the X server moves the input focus with the pointer and the application closes its own popup when the popup takes that focus. Run `Fsunaba -w tor-browser` to put a window manager in the sandbox, which handles the focus and keeps those popups open. The X cursor is the server's default root cursor; `Fsunaba` sets the usual arrow, but that alone does not keep a popup open.

## SECURITY

`Fsunaba` is a rudimentary sandbox: it reduces the blast radius of an untrusted X application, but it is not a strong isolation boundary. Keep the following in mind:

* The sandbox user can read any file on the system that its permissions allow, and it has full network access. Do not run untrusted applications and assume your data is safe.
* Audio, the X selection/clipboard, and shared directories are only exposed when you explicitly enable them, and each one weakens the sandbox.
* `Fsunaba` stores its X authority file in a private, mode `700` temporary directory, and removes it, along with all authentication cookies, when the application exits or the utility is interrupted.
* The authentication cookie is fed to `xauth` through a pipe instead of the command line, because process arguments are readable by every local user on OpenBSD.
* The sandboxed application runs with a minimal environment (`DISPLAY`, `HOME`, `LOGNAME`, `USER`, `PATH`), with its home directory as the working directory, and with its arguments unchanged.
* `make install` validates the sandbox username and `/etc/doas.conf` before changing them, refuses to modify an invalid `doas.conf`, and makes the sandbox user's home directory non-writable by group and others.
* Amnesic mode erases the contents of the amnesic home but cannot remove the home directory itself, and never touches data outside it.

### What a Malicious Application Can Still Do

`Fsunaba` limits what an application reaches, it does not stop a hostile one. The application runs with the full privileges of the sandbox user and can:

* **Read whatever the sandbox user can read**, including world-readable files in your home, everything under `/etc` and `/tmp`, and its own home directory. A mode `700` home keeps your files out of reach.
* **Write to its home and `/tmp`**, so it can plant files for you to open later, and fill your disk.
* **Reach the network**, including your LAN and services listening on `localhost`, and exfiltrate anything it read.
* **Read the sandbox user's `~/.Xauthority`**, which also reaches any other sandbox display belonging to the same sandbox user, such as a concurrent session.
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
