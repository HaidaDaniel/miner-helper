#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SERVICE="wildrig-miner.service"
WILDRIG_VERSION="${WILDRIG_VERSION:-latest}"
MINER_BINARY=""
RIG_NAME_ARG=""
PROFILE_ARG=""

die() {
    echo "Ошибка: $*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Использование: ./install.sh [параметры]

Параметры:
  --rig-name NAME       имя воркера (по умолчанию hostname машины)
  --profile NAME        профиль для запуска (по умолчанию pearlhash)
  --miner-binary PATH   использовать уже скачанный бинарник вместо загрузки
  --version VERSION     версия WildRig Multi; по умолчанию последняя с GitHub
  -h, --help            показать справку

Запускайте от обычного пользователя, у которого есть sudo.
EOF
}

while (($#)); do
    case "$1" in
        --rig-name)
            (($# >= 2)) || die "после --rig-name укажите имя"
            RIG_NAME_ARG="$2"
            shift 2
            ;;
        --profile)
            (($# >= 2)) || die "после --profile укажите профиль"
            PROFILE_ARG="$2"
            shift 2
            ;;
        --miner-binary)
            (($# >= 2)) || die "после --miner-binary укажите путь"
            MINER_BINARY="$2"
            shift 2
            ;;
        --version)
            (($# >= 2)) || die "после --version укажите версию"
            WILDRIG_VERSION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "неизвестный параметр: $1"
            ;;
    esac
done

[[ "$EUID" -ne 0 ]] || die "запустите ./install.sh от обычного пользователя, не через sudo"
[[ -f /etc/os-release ]] || die "не удалось определить ОС"
# shellcheck source=/etc/os-release
source /etc/os-release
[[ "${ID:-}" == ubuntu ]] || die "установщик рассчитан на Ubuntu"
[[ "$BASE_DIR" != *[[:space:]]* ]] || die "путь к репозиторию не должен содержать пробелы"
command -v sudo >/dev/null || die "не найден sudo"
sudo -v

RUN_USER="$(id -un)"
RUN_GROUP="$(id -gn)"
[[ -d "$BASE_DIR/profiles" ]] || die "папка profiles не найдена"

# Materialize ignored, machine-local configs from tracked examples, without
# replacing any existing wallets or local edits.
shopt -s nullglob
examples=("$BASE_DIR"/profiles/*.example.conf)
for example in "${examples[@]}"; do
    target="${example%.example.conf}.conf"
    if [[ ! -e "$target" ]]; then
        install -m 0600 "$example" "$target"
    fi
done
for profile in "$BASE_DIR"/profiles/*.conf; do
    [[ "$profile" == *.example.conf ]] || chmod 0600 "$profile"
done

if [[ -n "$PROFILE_ARG" ]]; then
    [[ "$PROFILE_ARG" =~ ^[a-zA-Z0-9._-]+$ ]] || die "недопустимое имя профиля: $PROFILE_ARG"
    printf '%s\n' "$PROFILE_ARG" > "$BASE_DIR/current-profile"
elif [[ ! -f "$BASE_DIR/current-profile" ]]; then
    printf '%s\n' pearlhash > "$BASE_DIR/current-profile"
fi
chmod 0600 "$BASE_DIR/current-profile"

PROFILE_NAME="$(tr -d '[:space:]' < "$BASE_DIR/current-profile")"
[[ "$PROFILE_NAME" =~ ^[a-zA-Z0-9._-]+$ ]] || die "некорректный профиль в current-profile"
PROFILE_FILE="$BASE_DIR/profiles/$PROFILE_NAME.conf"
[[ -r "$PROFILE_FILE" ]] || die "нет файла $PROFILE_FILE"
if grep -Eq 'YOUR_WALLET_ADDRESS|CHANGE_ME|REPLACE_ME' "$PROFILE_FILE"; then
    die "в $PROFILE_FILE укажите свой адрес кошелька или логин пула в MINER_USER"
fi

if [[ -n "$RIG_NAME_ARG" ]]; then
    RIG_NAME="$RIG_NAME_ARG"
elif [[ -s "$BASE_DIR/rig-name" ]]; then
    RIG_NAME="$(tr -d '\r\n' < "$BASE_DIR/rig-name")"
else
    RIG_NAME="$(hostname -s | tr '[:upper:]' '[:lower:]')"
    RIG_NAME="${RIG_NAME//[^a-z0-9._-]/-}"
    RIG_NAME="${RIG_NAME#-}"
    RIG_NAME="${RIG_NAME%-}"
fi
[[ "$RIG_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$ ]] || die "имя рига должно быть длиной 1–32 символа и содержать только буквы, цифры, точку, дефис или подчёркивание"
printf '%s\n' "$RIG_NAME" > "$BASE_DIR/rig-name"
chmod 0644 "$BASE_DIR/rig-name"

if [[ ! -f "$BASE_DIR/gpu-settings.conf" && -f "$BASE_DIR/gpu-settings.conf.example" ]]; then
    install -m 0644 "$BASE_DIR/gpu-settings.conf.example" "$BASE_DIR/gpu-settings.conf"
fi

echo "Установка пакетов Ubuntu..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl ocl-icd-libopencl1 python3 tar

if [[ -n "$MINER_BINARY" ]]; then
    [[ -x "$MINER_BINARY" ]] || die "бинарник не найден или не исполняемый: $MINER_BINARY"
    install -m 0755 "$MINER_BINARY" "$BASE_DIR/wildrig-multi"
elif [[ ! -x "$BASE_DIR/wildrig-multi" ]]; then
    echo "Загрузка WildRig Multi ($WILDRIG_VERSION) из официального GitHub..."
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT
    python3 - "$WILDRIG_VERSION" > "$tmp_dir/release.meta" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

version = sys.argv[1].strip()
if version.lower() == "latest":
    endpoint = "https://api.github.com/repos/andru-kun/wildrig-multi/releases/latest"
else:
    tag = version[1:] if version.startswith("v") else version
    endpoint = "https://api.github.com/repos/andru-kun/wildrig-multi/releases/tags/" + urllib.parse.quote(tag, safe="")

request = urllib.request.Request(endpoint, headers={"Accept": "application/vnd.github+json", "User-Agent": "wildrig-miner-setup"})
with urllib.request.urlopen(request, timeout=30) as response:
    release = json.load(response)

assets = [asset for asset in release.get("assets", [])
          if asset.get("name", "").startswith("wildrig-multi-linux-")
          and asset.get("name", "").endswith(".tar.gz")]
if not assets:
    raise SystemExit("В указанном релизе нет Linux tar.gz архива WildRig Multi")
print(release["tag_name"])
print(assets[0]["browser_download_url"])
PY
    mapfile -t release_info < "$tmp_dir/release.meta"
    ((${#release_info[@]} == 2)) || die "не удалось прочитать сведения о релизе WildRig"
    release_tag="${release_info[0]}"
    release_url="${release_info[1]}"
    [[ "$release_url" == https://github.com/andru-kun/wildrig-multi/releases/download/* ]] || die "неожиданный URL релиза WildRig"
    curl -fL --retry 3 "$release_url" -o "$tmp_dir/wildrig.tar.gz"
    mkdir "$tmp_dir/unpacked"
    tar -xzf "$tmp_dir/wildrig.tar.gz" -C "$tmp_dir/unpacked" --no-same-owner
    extracted_binary="$(find "$tmp_dir/unpacked" -type f -name wildrig-multi -print -quit)"
    [[ -n "$extracted_binary" ]] || die "в архиве WildRig не найден бинарник wildrig-multi"
    install -m 0755 "$extracted_binary" "$BASE_DIR/wildrig-multi"
    printf '%s\n' "$release_tag" > "$BASE_DIR/wildrig-version"
    rm -rf "$tmp_dir"
    trap - EXIT
fi

if [[ ! -f "$BASE_DIR/gpu-settings.conf" ]]; then
    echo "Предупреждение: gpu-settings.conf не найден; настройка GPU будет пропущена." >&2
fi

tmp_unit="$(mktemp)"
trap 'rm -f "$tmp_unit"' EXIT
python3 - "$BASE_DIR/systemd/wildrig-miner.service.template" "$tmp_unit" "$RUN_USER" "$RUN_GROUP" "$BASE_DIR" <<'PY'
import pathlib
import sys

template, destination, user, group, base_dir = sys.argv[1:]
content = pathlib.Path(template).read_text()
for key, value in {
    "{{USER}}": user,
    "{{GROUP}}": group,
    "{{BASE_DIR}}": base_dir,
}.items():
    content = content.replace(key, value)
pathlib.Path(destination).write_text(content)
PY

systemd_unit="/etc/systemd/system/$SERVICE"
sudo systemctl stop "$SERVICE" >/dev/null 2>&1 || true
sudo install -o root -g root -m 0644 "$tmp_unit" "$systemd_unit"
sudo systemctl daemon-reload

# Disable the older per-user unit if this checkout is being upgraded in place.
systemctl --user disable --now "$SERVICE" >/dev/null 2>&1 || true

sudo systemctl enable --now "$SERVICE"

echo
echo "Установлено: $SERVICE"
echo "Профиль: $PROFILE_NAME"
echo "Имя рига: $RIG_NAME"
echo "Бинарник: $BASE_DIR/wildrig-multi"
echo "Управление: $BASE_DIR/minerctl status|start|stop|list|switch <профиль>"
