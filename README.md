# ESPHome

## ESPHome Device Builder LXC

This repository can install and maintain a native ESPHome Device Builder
installation in an unprivileged Debian 13 Proxmox LXC. Docker, nesting and USB
passthrough are not required.

### Fresh container

Install Git and Just, then clone this repository at the standard configuration
path:

```shell
apt update
apt install -y git just
mkdir -p /srv/esphome
git clone git@github.com:worgarside/esphome.git /srv/esphome/config
cd /srv/esphome/config
```

Run the one-off setup:

```shell
just setup-esphome
```

This requires `uv` to already be installed and available in `PATH`. It uses
`uv` to provision Python 3.13, creates the `esphome` service account, installs
the latest ESPHome and Device Builder in `/opt/esphome`, and enables the system
service. The system Python and `pip` are not used.

To select another supported Python version for the initial setup:

```shell
ESPHOME_PYTHON_VERSION=3.12 just setup-esphome
```

The LXC should:

- Run Debian 13 (Python 3.12 or newer).
- Be unprivileged, with nesting disabled.
- Have internet access.
- Have at least 16 GB storage, 2 CPU cores and preferably 3 GB RAM.

Create `/srv/esphome/config/secrets.yaml` in the LXC after setup. It is
intentionally excluded from Git.

The Device Builder listens on port `6052`. Keep this limited to trusted
networks or place it behind an authenticated HTTPS reverse proxy.

Optional dashboard credentials can be stored in
`/etc/esphome/environment`:

```dotenv
ESPHOME_USERNAME=your-user
ESPHOME_PASSWORD=a-long-random-password
```

After changing that file, run `just restart` inside the LXC.

### Routine commands

```shell
git pull
just update-esphome  # Refresh packages and restart after an update
just status          # Show the system service
just logs            # Follow Device Builder logs
just restart         # Restart the service
```

The initial USB flash still happens in a browser connected to the ESP board;
the LXC does not need the USB device. Later installations can use OTA.
