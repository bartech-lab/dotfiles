# omniroute service

Login-persistent background service for the personal omniroute app
(`~/omniroute`, Next.js, listens on its configured dashboard port).
Replaces the previous pm2 setup (2026-07).

## Design

- `run.sh` — shared launcher. Resolves node without shell profiles
  (system node on Linux, newest fnm node on macOS) and **execs node
  directly** on `scripts/dev/run-next.mjs start`. Never supervise
  `npm run start`: npm's shell intermediary does not forward SIGTERM
  reliably (npm RFC #829), which breaks graceful shutdown and PID
  tracking under launchd/systemd.
- macOS: `setup.sh` copies `run.sh` to `~/.config/omniroute/` and
  installs `com.user.omniroute.plist` (KeepAlive + RunAtLoad).
- Linux: systemd **user** unit `systemd/omniroute.service`
  (Restart=on-failure, `SuccessExitStatus=130 143` because `next start`
  exits 143 on SIGTERM). Installed by `install.sh`, or manually:

```bash
mkdir -p ~/.config/omniroute ~/.config/systemd/user
cp ~/dotfiles/omniroute/run.sh ~/.config/omniroute/run.sh && chmod +x ~/.config/omniroute/run.sh
cp ~/dotfiles/omniroute/systemd/omniroute.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now omniroute
loginctl enable-linger   # required: keeps the service running without an active session
```

## Operations

```bash
# macOS
launchctl kickstart -k gui/$UID/com.user.omniroute   # restart
launchctl bootout gui/$UID/com.user.omniroute        # stop
tail -f ~/omniroute/logs/launchd.out.log

# Linux
systemctl --user restart omniroute
journalctl --user -u omniroute -f
```

Both setups skip cleanly when `~/omniroute` doesn't exist on the machine.
