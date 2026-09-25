# WildRig GPU miner

Репозиторий разворачивает на Ubuntu WildRig Multi как системный `systemd`
сервис. Конфигурации пулов и GPU-настройки основаны на текущей установке.
Кошельки, имя рига, бинарник и логи остаются локальными и не попадают в Git.

## Установка на новую Ubuntu

Перед установкой настройте драйвер видеокарты. Для NVIDIA, если `nvidia-smi`
ещё не работает, установите рекомендуемый драйвер Ubuntu и перезагрузитесь:

```bash
sudo ubuntu-drivers install
sudo reboot
```

Затем продолжите установку репозитория. Это рекомендуемый Ubuntu способ
установки драйвера; см. [документацию Ubuntu](https://ubuntu.com/server/docs/how-to/graphics/install-nvidia-drivers/).

```bash
git clone <URL-этого-репозитория> wildrig-miner
cd wildrig-miner
cp profiles/pearlhash.example.conf profiles/pearlhash.conf
nano profiles/pearlhash.conf   # замените YOUR_WALLET_ADDRESS, оставив .{RIG_NAME}
./install.sh
```

Установщик установит системные зависимости, скачает последний Linux-релиз
WildRig Multi с [официальной страницы релизов](https://github.com/andru-kun/wildrig-multi/releases),
создаст systemd-сервис и включит его при загрузке Ubuntu. У пользователя,
который запускает установщик, должны быть права `sudo`.

По умолчанию выбирается профиль `pearlhash`. Укажите другое имя рига и/или
профиль параметрами установщика:

```bash
./install.sh --rig-name rig-garage --profile pearlhash
```

Если нужно использовать уже скачанный бинарник или закрепить версию WildRig:

```bash
./install.sh --miner-binary /path/to/wildrig-multi
./install.sh --version 0.51.2
```

## Имя рига и локальная конфигурация

Без `--rig-name` имя берётся из hostname Ubuntu. Оно сохраняется в локальном
файле `rig-name`. Его можно изменить вручную, затем перезапустить сервис:

```bash
printf '%s\n' rig-garage > rig-name
./minerctl restart
```

Шаблон `pearlhash` подставляет имя в `MINER_USER` после точки, то есть
в `MINER_USER="АДРЕС.{RIG_NAME}"` замените только `АДРЕС`; установщик подставит
вместо `{RIG_NAME}` имя рига. В других профилях, где нужен аргумент WildRig `--worker`,
имя подставляется туда. При необходимости адаптируйте соответствующий профиль
под требования выбранного пула.

Установщик копирует `profiles/*.example.conf` в локальные `profiles/*.conf`,
если локальных файлов ещё нет. Перед запуском проверьте адреса кошельков и
настройки пула в активном файле профиля. Для переключения профиля:

```bash
./minerctl list
./minerctl switch nexa
```

Профили — shell-конфиги с присваиваниями значений. Дополнительные параметры
задаются массивом `MINER_EXTRA_ARGS`; команды в профиль добавлять нельзя.

## Управление

```text
./minerctl status
./minerctl start
./minerctl stop
./minerctl restart
./minerctl enable       # включить автозапуск и запустить сейчас
./minerctl disable      # отключить автозапуск и остановить сейчас
./minerctl switch nexa  # переключить профиль
```

Сервис называется `wildrig-miner.service`, запускается от пользователя,
установившего репозиторий, и стартует при загрузке. Логи доступны в
`miner.log` и через `journalctl -u wildrig-miner.service`.

## Настройки GPU

Исходные настройки NVIDIA хранятся в `gpu-settings.conf.example` и копируются
в игнорируемый Git файл `gpu-settings.conf`. Значения лимитов и частот
перенесены с текущего рига; перед установкой на другое железо проверьте их.
Чтобы не применять настройки при старте, укажите в `gpu-settings.conf`:

```bash
GPU_SETTINGS_ENABLED=0
```

Порядок полей каждой строки массива `GPU_SETTINGS`: номер GPU, лимит мощности,
частота графики, сдвиг графики и частота памяти.

## Что хранится локально

`.gitignore` исключает `profiles/*.conf`, `current-profile`, `rig-name`,
`gpu-settings.conf`, бинарник WildRig и логи. В Git остаются только примеры
профилей без адресов кошельков.
