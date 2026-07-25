set shell := ["bash", "-euo", "pipefail", "-c"]

# Run once after cloning this repository into /srv/esphome/config in the LXC.
setup-esphome:
    ./scripts/setup-esphome.sh

# Refresh the Python packages and service definition after a Git pull.
update-esphome:
    ./scripts/setup-esphome.sh

restart:
    systemctl restart esphome

status:
    systemctl --no-pager --full status esphome

logs:
    journalctl -u esphome -f

validate config:
    /opt/esphome/bin/esphome config "{{ config }}"
