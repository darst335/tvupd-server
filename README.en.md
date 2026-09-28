# tvupd-server — Remote Self-Maintenance & Distribution System for Android TV Boxes (OpenWrt Server-Side)

[中文](README.md) | **English**

A server side for **remotely managing a fleet of Android TV boxes** (customized IPTV set-top boxes). It runs on an OpenWrt router and provides:

- automatic box enrollment
- silent install / removal of apps
- remote commands (reboot, cache cleanup, brick-recovery scripts, …)
- customer geo distribution
- APK distribution library

It ships with a built-in web admin console plus a LuCI menu entry. The box-side deployment guide is at the end of this document.

## Features

| Module | Description |
|---|---|
| Automatic box enrollment | Boxes report by periodically pulling their plan (serial / MAC / model / Android version / memory / installed apps / uptime). Duplicate identities are merged by MAC. |
| Software plans | Three line types: install / remove / cmd. **remove can only uninstall apps that were distributed by this system** — the server enforces a whitelist to protect apps installed by the customer. |
| Remote commands | report / reboot / memclean / clearcache / dns / wifi / oem / maint / status / sh (script URL + md5 verification). Nonce-based anti-replay; each command executes only once. |
| Delivery records | Outbound deliveries are automatically matched against box acknowledgements into a side-by-side table. An "unmanaged apps" view reveals apps you may want to remove but that are not yet in the APK library. |
| APK library | Upload an APK and the package name is recognized automatically (AndroidManifest parsed in the browser). Chinese file names are supported. |
| Customer distribution | Geo lookup of egress IPs + ISP (ip-api.com, results cached locally); customers are listed first. |
| System settings | External service address / admin whitelist subnet / online-detection window / **APK storage location (moving it auto-migrates data + creates a symlink)** / admin password. Defaults are auto-derived from the router's current configuration. |

| No-flash agent | `agent/`: the TV Butler APK. A user-level install is enough to join the fleet (app installs need one confirmation press without root); the protocol is fully compatible with the firmware side. |

## Screenshots (sanitized demo data)

Serial numbers are fictional DEMO-prefixed values, IPs use 192.168.1.x, and the domain is your.domain.

| Overview | Software plan |
|---|---|
| ![Overview](docs/img/console-overview.png) | ![Software plan](docs/img/console-plan.png) |
| **APK library** | **Delivery records** |
| ![APK library](docs/img/console-apks.png) | ![Delivery records](docs/img/console-records.png) |
| **Device registry** | **System settings (incl. Ku9 authorization list)** |
| ![Device registry](docs/img/console-devices.png) | ![System settings](docs/img/console-settings.png) |

Real-world result: plan delivered → Ku9 installed automatically + authorized per serial → preset subscription auto-loaded, playing right after boot (customer's live channel below):

![Ku9 playing right after automatic deployment](docs/img/ku9-playing.png)

## Tested On

**Main router / server**

| Item | Configuration |
|---|---|
| Router | China Mobile CMCC RAX3000M (MT7981, 256MB RAM) |
| System | ImmortalWrt (OpenWrt) + lighttpd/CGI |
| External service | DDNS domain :8083; only the manifest and APK downloads are exposed, the admin console is reachable from the whitelisted LAN subnet only |
| Storage | On-router /srv (the APK library can be moved to a data disk with an automatic symlink) |
| Network | Home broadband; customer boxes pull plans via the DDNS domain |

**Boxes (two real devices tested)**

| Model | Onboarding | What was tested |
|---|---|---|
| UNT401H (China Mobile IPTV customized box, Android 4.4) | Firmware implant (tv-updater written into /system) | Ku9 auto-install + per-serial authorization + preset subscription auto-load, playing right after boot with zero manual steps; remote commands / APK distribution all working |
| M301H (China Mobile streaming box, Android 4.4) | Firmware implant (same) | Heartbeat reporting / plan delivery / remote commands / APK distribution under long-term operation |

Both are Android 4.4 (SDK 19), proving the whole chain works on old firmware: manifest polling, silent installs, script delivery (busybox wget + DNS compatibility layer), and Ku9's `/sdcard/酷9/configuration/` preset subscription mechanism.

## Directory Layout

```
tvupd-server/
├── install.sh        # One-shot OpenWrt installer (auto-detects subnet, installs deps, writes lighttpd config)
├── uninstall.sh      # Uninstaller (keeps data by default; PURGE=1 removes data too)
├── backup.sh         # Packs all business data into a tar.gz
├── restore.sh        # Imports a backup onto a new router
├── www/              # lighttpd site (document-root = /srv/tvupd)
│   ├── admin         # Admin CGI (dashboard / plans / settings / password / router info …)
│   ├── manifest      # Box-side CGI (reporting + plan delivery)
│   ├── admin.html    # Admin console front end (single file, no external dependencies)
│   ├── apps.txt      # Public self-check file
│   └── fixadb.sh     # Small helper that repairs network adb on the box
├── priv-skel/        # Data skeleton for first install (never overwrites existing data)
│   ├── devices.txt   # Device roster (identity | plan | note)
│   ├── geo-lookup.sh # Geo lookup (ip-api.com, results cached)
│   └── plans/        # Sample plans: default / family / senior / lab
├── box/              # Box side (Android 4.x customized IPTV boxes)
│   ├── install-to-box.sh  # One-shot adb install into /system (Route A: temporary install)
│   ├── system/            # tv-updater / tv-maint / tv-oemctl / boot autostart / config
│   ├── firmware/          # Firmware embedding reference (boot.img repacking, filesystem_config entries)
│   └── README.md          # The two onboarding routes + OTA signing notes
└── luci/admin.js     # LuCI menu view (console embedded via iframe)
```

## Installation (OpenWrt)

```sh
# On the router (or scp this directory to the router first)
opkg update && opkg install git git-http   # or clone on your PC and scp
sh install.sh
# Optional variables:
#   PORT=8090                  change port (default 8083)
#   SRVURL=http://xxx:8083     external address (DDNS domain); defaults to the LAN IP
#   ADMIN_PWD=xxx              set the admin password (default: random, printed on install)
#   SRCNET=192.168.9.          admin whitelist subnet (default: derived from the LAN IP)
```

When the installer finishes it prints the console URL and the admin password. The console is also reachable from LuCI → Services → TV Box Ops Console (embedded via iframe).

## Migrating to Another OpenWrt Router

```sh
# Old router
sh backup.sh                     # produces tvupd-backup-<date>.tar.gz
scp tvupd-backup-*.tar.gz root@new-router:/tmp/

# New router
sh install.sh                    # install the service first
sh restore.sh /tmp/tvupd-backup-*.tar.gz
# Finally, update the external service address in the console's System Settings
```

## Onboarding the Boxes

Two routes (see `box/README.md` for details):

- **Route A · Temporary install**: once the box is rooted with network adb enabled, run `sh box/install-to-box.sh <box-ip>` to install into /system in one shot.
- **Route B · Firmware embedding**: pack `box/system/` into the firmware image so every shipped unit has it out of the box — no per-device setup.

A box only needs to be able to reach
`http://<service-address>/cgi-bin/manifest?id=<identity>&mac=&sdk=&model=&group=&up=&mem=&tn=&ta=&cmd=<ack>`
to join the network: the first pull returns the `default` plan, and once the device is registered in the roster the assigned plan switches automatically (takes effect within 10 minutes).

## Security Notes

- Admin interface: LAN whitelist subnet + token (`/srv/tvupd-priv/admin.pwd`, 6–32 alphanumeric chars). The token travels in the `X-Auth-Token` header and never appears in logs.
- Box interface: manifest is read-only (plan delivery + reporting); it never modifies any configuration.
- Any external (WAN) access to `admin` is rejected with 403 at the lighttpd layer; only `manifest` and APK downloads are exposed externally.
- The data directory `/srv/tvupd-priv` uses 600/700 permissions. Backup archives contain the admin password — keep them safe.

## Data Files (/srv/tvupd-priv)

| File | Contents |
|---|---|
| devices.txt | Device roster: `identity|plan|note` (lines starting with `#` are comments) |
| plans/*.txt | Plans: `install|package|md5|URL`, `remove|package`, `cmd|seq|action|args|md5` |
| access.log | Box heartbeats: `time|serial|MAC|IP|SDK|model|plan|note|uptime-h|free-mem|app-count|app-list` |
| cmds.log | Command acknowledgements: `time|serial|<nonce><action><result>` |
| audit.log | Admin operation audit log |
| settings.env | System settings (SRVURL / SRCNET / ONLINE_H) |
| ipcache/ | Egress-IP geo cache (two lines: location / ISP) |

## Credits

Created by darst335 together with AI 🤝
