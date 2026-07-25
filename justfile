set shell := ["bash", "-euo", "pipefail", "-c"]

# Run once after cloning this repository into /srv/esphome/config in the LXC.
setup-esphome:
    sudo ./scripts/setup-esphome.sh

# Refresh the Python packages and service definition after a Git pull.
update-esphome:
    sudo ./scripts/setup-esphome.sh

restart:
    sudo systemctl restart esphome

status:
    systemctl --no-pager --full status esphome

logs:
    sudo journalctl -u esphome -f

validate config:
    /opt/esphome/bin/esphome config "{{ config }}"
