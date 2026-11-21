# Mint KDE desktop over RDP, from GitHub Actions

A GitHub Actions workflow that boots a throwaway Linux desktop and lets you remote into it from
any device, with an IP, a username and a password, over Tailscale.

**What you get per run**

- Ubuntu 24.04 desktop with KDE Plasma (5.27) on X11
- Linux Mint's own Mint-Y icon theme (plus Konsole, Dolphin, Kate)
- `xrdp` on port 3389, so any standard RDP client connects
- Your own user account with a password and passwordless `sudo`
- A node on your Tailscale tailnet named `mint-kde` (change it with the `TS_HOSTNAME` secret)

Nothing is exposed to the public internet: the machine is only reachable from devices signed in
to your tailnet.

**The honest caveat:** a GitHub-hosted runner is destroyed after at most 6 hours, so this is a
temporary desktop, not a permanent server. Each run gives you a fresh machine with the same name
and the same login, and its Tailscale IP usually changes between runs (the MagicDNS name
`mint-kde.<your-tailnet>.ts.net` stays). If you want something that is always on, a small VPS is
the right tool; this workflow is for "I want a Linux KDE box right now, on my phone".

Also: **Linux Mint's KDE edition was discontinued after Mint 18.3** (2018). Mint 19 and later are
Cinnamon/MATE/Xfce only. So this is Mint's base (Ubuntu 24.04) with KDE Plasma on top and Mint's
icon theme installed, which is what "Mint KDE" can actually mean today. If you specifically want
Cinnamon instead, say so and I will swap the desktop packages.

---

## 1. Set up Tailscale

1. Create a tailnet at <https://login.tailscale.com> (free plan is fine).
2. Create credentials for the workflow, either:

   **A. OAuth client (recommended, does not expire)** — Admin console → **Settings** → **OAuth
   clients** → **Generate OAuth client**, scope **`auth_keys`** (write). Note the client ID and
   secret. Then add a tag for it in **Access controls** → **Policy file**, e.g.

   ```json
   "tagOwners": {
     "tag:ci": ["autogroup:admin"]
   }
   ```

   and give the OAuth client the tag `tag:ci` when you create it.

   **B. Auth key (simpler)** — Admin console → **Settings** → **Keys** → **Generate auth key**,
   tick **Reusable** and **Ephemeral** (tick **Tags** too if you want the node tagged), then copy
   the whole `tskey-auth-...` value. Keys expire (90 days max) and a **one-off** key stops working
   after its first successful use, so Reusable matters here: every run is a new machine.

3. Install Tailscale on the device you will connect *from* (iPhone, iPad, Mac, Windows, Linux) and
   sign in to the same tailnet.

## 2. Add the repository secrets

In GitHub: **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

| Secret | Required | Meaning |
| --- | --- | --- |
| `RDP_PASSWORD` | yes | Password for the desktop user. Use something long, it is the only thing guarding the machine. |
| `TS_OAUTH_CLIENT_ID` + `TS_OAUTH_SECRET` | one of these pairs | Tailscale OAuth client (recommended). |
| `TS_AUTHKEY` | one of these pairs | Tailscale auth key instead of OAuth. |
| `RDP_USER` | no | Username, defaults to `mint`. |
| `TS_HOSTNAME` | no | Tailscale machine name, defaults to `mint-kde`. Must be a DNS label (letters, digits, dashes). |
| `TS_TAG` | no | Tailscale tag for the node, defaults to `tag:ci`. Only used with an OAuth client; with an auth key the tag comes from the key itself. |

## 3. Run it

**Actions** → **Mint KDE desktop over RDP (Tailscale)** → **Run workflow**. Set
`keep_alive_minutes` (default 320, max 330).

Tailscale connects first, before the desktop is installed, so a bad key fails in seconds instead
of after a ten-minute KDE download. Installing KDE then takes roughly 5 to 15 minutes. When the
**Show how to connect** step finishes, the run page gets a summary with the address, port,
username and password. The desktop stays up until the keep-alive ends, or until you cancel the run.

If you would rather not wait for that install each time, use the prebuilt-image workflow in the next
section.

## 4. Fast start: prebuilt image (~1 minute)

The workflow above installs KDE on every run. To get the near-instant start that most GitHub RDP
projects have, bake the desktop into a container image once and boot that instead:

1. Run **Actions** → **Build desktop image** → **Run workflow** once. It installs KDE Plasma +
   xrdp + Mint's icons into `ghcr.io/<your-owner>/<repo>:latest` (roughly 5 to 10 minutes the first
   time) and re-runs by itself whenever something in `docker/` changes.
2. Then use **Actions** → **Mint KDE desktop over RDP (prebuilt image)** → **Run workflow**. That
   only pulls the image and starts the container — about a minute to the login screen.

Both workflows use the same secrets, the same Tailscale node name and the same login, so you can
switch between them whenever you like. The from-scratch workflow stays as the fallback if the image
is missing or you changed `docker/Dockerfile` without rebuilding.

The image is a private GHCR package by default; the workflow logs in with the repository token to
pull it, so nothing has to be public. `prebuilt.yml` runs `docker run --privileged`, which Xorg
inside the container needs — it is a throwaway runner, so that trade is fine.

## 5. Connect

- **iPhone / iPad:** Microsoft **Windows App** (formerly Remote Desktop) → **+** → **Add PC** →
  address `mint-kde` (or the `100.x.y.z` Tailscale IP), user account `mint` + your password. Set a
  resolution and "fit to screen" in the PC settings; the default is small.
- **macOS:** **Windows App** from the App Store, same fields. On Macs you can also use
  `xfreerdp` or **Microsoft Remote Desktop**.
- **Windows:** built-in **Remote Desktop Connection** (`mstsc`).
- **Linux:** `xfreerdp /v:mint-kde /u:mint /size:1920x1080` (or `remmina`).

If the name does not resolve, MagicDNS is off in your tailnet (Admin console → **DNS** → enable
**MagicDNS**); use the printed Tailscale IP instead.

## Limits and cost

- **6 hours max per run.** GitHub stops every job at 6 hours; the workflow clamps itself to 330
  minutes of desktop time so it ends cleanly instead of being killed.
- **Runner minutes.** On a **private** repo, GitHub Free gives 2000 Actions minutes a month — one
  5.5 hour run is ~340 minutes, so about 5 to 6 runs a month. On a **public** repo, standard
  runners are free, so running it all day costs nothing but makes the workflow file (not the
  secrets) public. Keep it private and run it on demand unless you really want it always on.
- **Ephemeral node.** Each run logs into Tailscale as an ephemeral node and logs out when the run
  ends, so the machine disappears from your tailnet immediately instead of piling up. If a run is
  killed before that cleanup, the node is reaped 30 to 60 minutes later instead.
- The scheduled `cron` block is commented out on purpose. Uncomment it only if the repo is public
  or you accept the minutes.

## Customising

- **Longer session:** raise `keep_alive_minutes` up to 330, and `timeout-minutes` in the job if
  you want to use all 6 hours.
- **Different desktop:** replace `kde-plasma-desktop` with `ubuntu-desktop-minimal` (GNOME),
  `cinnamon-desktop-environment` (Mint's default desktop), or `xfce4` (lightest over RDP), and
  change `startplasma-x11` in `startwm.sh` to `startgnome`, `cinnamon-session`, `startxfce4`.
- **Effects on:** delete the `[Compositing]` block in "Prepare the user's desktop settings"; it is
  off there because RDP is much smoother without it.
- **More software:** append package names to the `apt-get install` list, e.g. `firefox chromium
  vlc gimp code`.
- **Audio:** RDP audio redirection needs PulseAudio and is not configured here.

## Security

- The machine is only reachable through your tailnet, but **everyone in your tailnet can log in**
  with the RDP password. Use a strong one, and lock the tailnet down with ACLs if it has other
  people in it.
- The desktop user has passwordless `sudo`, so treat a leaked password as root on a machine that
  lives inside your network for a few hours.
- Secrets are never printed; the password only appears in the connection summary as a reminder of
  which secret to use.

## Troubleshooting

- **`Add the Linux Mint look` shows an error or a warning:** that step is cosmetic (icon theme
  only) and can never stop the desktop; the run continues with KDE's default icons.
- **"Can't establish a connection" / nothing on port 3389:** the run log shows
  `xrdp is not listening on port 3389` and now prints the service status, journal and
  `/var/log/xrdp.log` above that error. Usual causes are a missing snakeoil TLS certificate or a
  missing `/run/xrdp` directory, both handled by the workflow; if it still fails, the log lines it
  dumps are the answer. If the step went green but `xrdp stopped listening` appears in the
  keep-alive, it restarted the daemon.
- **RDP connects but the session is black / disconnects immediately:** check the run log for
  `startplasma-x11`. If Plasma fails to start, the `install KDE Plasma` step likely changed
  packages; workaround is to add `--install-recommends` (remove `--no-install-recommends`).
- **`requested tags [tag:ci] are invalid or not permitted`:** the OAuth client has no `tag:ci`, or
  `tagOwners` in your policy file does not allow it. Fix the tag or set the `TS_TAG` secret to
  the tag the client owns.
- **`tailscale up` fails with `Status: 404, Message: "not found"`:** Tailscale has no such key. It
  expired, was revoked, was a one-off key that already logged a machine in, or the secret was not
  copied completely. The workflow already trims stray spaces and newlines, so a 404 here means the
  key itself: generate a fresh one with Reusable + Ephemeral ticked and re-paste the whole value.
- **`TS_AUTHKEY does not look like an auth key`:** the secret does not start with `tskey-auth-`.
  That is usually a Tailscale **API** token or an OAuth client ID sitting in the wrong secret.
- **The machine shows up as `mint-kde-2` instead of `mint-kde`:** an earlier node still owns the
  plain name — either its run was killed before the workflow could log out, or it has not been
  reaped yet (Tailscale removes idle ephemeral nodes after 30 to 60 minutes). Use the address the
  run printed, or wait an hour.
- **Cannot find the host:** MagicDNS off, or you are not signed in to the tailnet on the client.
  Use the IP from the run summary.
- **"Failed to start session" in xrdp logs:** the desktop user's home is missing or not writable;
  the user creation step did not run because the job failed earlier. Read the first failing step.
