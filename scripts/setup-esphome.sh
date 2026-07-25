#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "This installer must run as root." >&2
  exit 1
fi

config_dir="/srv/esphome/config"
venv_dir="/opt/esphome"
service_user="esphome"
python_version="${ESPHOME_PYTHON_VERSION:-3.13}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/.." && pwd)"

if [[ ! -d "${repo_dir}/.git" ]]; then
  echo "Expected a Git repository at ${repo_dir}." >&2
  exit 1
fi

if [[ "${repo_dir}" != "${config_dir}" ]]; then
  if [[ -e "${config_dir}" ]]; then
    echo "Cannot relocate the repository: ${config_dir} already exists." >&2
    exit 1
  fi

  echo "Relocating the repository from ${repo_dir} to ${config_dir}"
  install -d "$(dirname -- "${config_dir}")"
  mv "${repo_dir}" "${config_dir}"
  repo_dir="${config_dir}"
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "uv is required but was not found in PATH. Install uv, then rerun this setup." >&2
  exit 1
fi

apt-get update
apt-get install -y \
  build-essential \
  ca-certificates \
  git \
  libffi-dev \
  libssl-dev \
  pkg-config \
  xdg-user-dirs

UV_PYTHON_INSTALL_DIR=/opt/uv/python \
  uv python install "${python_version}"

if ! id "${service_user}" >/dev/null 2>&1; then
  useradd \
    --system \
    --create-home \
    --home-dir /var/lib/esphome \
    --shell /usr/sbin/nologin \
    "${service_user}"
fi

install -d -m 0755 /etc/esphome
if [[ ! -e /etc/esphome/environment ]]; then
  install -m 0600 /dev/null /etc/esphome/environment
fi

if [[ -x "${venv_dir}/bin/python" ]] && \
   ! "${venv_dir}/bin/python" -c \
     "import sys; raise SystemExit(sys.version_info[:2] != tuple(map(int, '${python_version}'.split('.'))))"
then
  rm -rf "${venv_dir}"
fi

if [[ ! -x "${venv_dir}/bin/python" ]]; then
  UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    uv venv --python "${python_version}" "${venv_dir}"
fi

uv pip install \
  --python "${venv_dir}/bin/python" \
  --upgrade \
  esphome \
  esphome-device-builder

if [[ ! -x "${venv_dir}/bin/esphome-device-builder" ]]; then
  echo "esphome-device-builder was installed but its executable was not found." >&2
  exit 1
fi

install -m 0644 \
  "${config_dir}/systemd/esphome.service" \
  /etc/systemd/system/esphome.service

chown -R root:"${service_user}" "${config_dir}"
chmod -R g+rwX "${config_dir}"
find "${config_dir}" -type d -exec chmod g+s {} +
chown -R "${service_user}:${service_user}" /var/lib/esphome

systemctl daemon-reload
systemctl enable --now esphome
systemctl restart esphome

echo
uv --version
"${venv_dir}/bin/esphome" version
systemctl --no-pager --full status esphome
