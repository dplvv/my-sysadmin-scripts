# ДЗ №2 — первоначальная подготовка Ubuntu

Дорожка «Продвинутый», Ubuntu 22.04. Этот раздел выполняется **один раз на чистой
машине** до создания контейнера. На уже работающей учебной VM повторно создавать
диски, массив и файловые системы не нужно.

## 1. Зависимости и репозиторий

Если Docker уже установлен, проверьте `sudo docker version` и
`sudo docker compose version`. Не заменяйте работающую установку. Ниже — установка
Docker Engine и Compose из [официального репозитория Docker](https://docs.docker.com/engine/install/ubuntu/)
на чистую Ubuntu без других установок Docker/containerd.

```bash
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl git nginx openssl mdadm lvm2 python3 procps coreutils
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker version
sudo docker compose version
```

Команды Docker далее выполняются через `sudo`, поэтому изменение группы
пользователя и повторный вход не требуются. Если репозитория на машине ещё нет:

```bash
git clone --branch hw2 https://github.com/dplvv/my-sysadmin-scripts.git
cd my-sysadmin-scripts
```

## 2. RAID 1 и LVM

Создаются три новых файла по 512 МиБ. Первые два используются для RAID 1,
третий — отдельно для LVM. Блок останавливается, если учебное хранилище уже
существует или точки монтирования заняты/непусты. Не удаляйте существующее
хранилище ради повторного запуска.

```bash
sudo bash <<'STORAGE'
set -Eeuo pipefail
LAB=/mnt/raid-lab
[[ ! -e "$LAB" && ! -e /dev/md0 && ! -e /dev/vg_data ]] || {
    echo 'Остановлено: учебное хранилище уже существует.' >&2; exit 1;
}
if vgs vg_data >/dev/null 2>&1; then
    echo 'Остановлено: группа vg_data уже существует.' >&2; exit 1
fi
for target in /mnt/raid /mnt/logs; do
    if mountpoint -q "$target" || [[ -L "$target" ]] ||
       { [[ -e "$target" ]] && { [[ ! -d "$target" ]] ||
         [[ -n "$(find "$target" -mindepth 1 -maxdepth 1 -print -quit)" ]]; }; }; then
        echo "Остановлено: $target занят или содержит данные." >&2; exit 1
    fi
done
mkdir -m 0755 "$LAB"
for disk in disk1.img disk2.img disk3.img; do
    truncate -s 512M "$LAB/$disk"
    chmod 0600 "$LAB/$disk"
done
LOOP1="$(losetup --find --show "$LAB/disk1.img")"
LOOP2="$(losetup --find --show "$LAB/disk2.img")"
LOOP3="$(losetup --find --show "$LAB/disk3.img")"
printf 'Новые устройства: %s %s %s\n' "$LOOP1" "$LOOP2" "$LOOP3"
mdadm --create /dev/md0 --metadata=1.2 --level=1 --raid-devices=2 --run "$LOOP1" "$LOOP2"
udevadm settle --timeout=10
mkfs.ext4 /dev/md0
mkdir -p /mnt/raid /mnt/logs
mount /dev/md0 /mnt/raid
mdadm --detail --scan /dev/md0 > "$LAB/raid.conf"
blkid -s UUID -o value /dev/md0 > "$LAB/raid.uuid"
pvcreate "$LOOP3"
vgcreate vg_data "$LOOP3"
lvcreate -L 200M -n lv_logs vg_data
mkfs.ext4 /dev/vg_data/lv_logs
mount /dev/vg_data/lv_logs /mnt/logs
printf 'Проверка сохранности данных\n' > /mnt/logs/storage-check.txt
pvs
vgs
lvs
df -h /mnt/raid /mnt/logs
STORAGE
```

`losetup --show` возвращает фактическое имя устройства; номера `/dev/loopN`
не задаются заранее. Файлы для восстановления остаются на этой машине:

- `/mnt/raid-lab/raid.conf` — конфигурация массива из `mdadm --detail --scan`.
- `/mnt/raid-lab/raid.uuid` — **UUID файловой системы ext4 на `/dev/md0`**.
  Его использует `mount -U` в `restore-storage.sh`; это не UUID массива mdadm.

Перед снимком результата дождитесь завершения синхронизации:

```bash
sudo mdadm --wait /dev/md0 || {
    [ "$(cat /sys/block/md0/md/sync_action)" = idle ] &&
    [ "$(cat /sys/block/md0/md/degraded)" = 0 ]
}
cat /proc/mdstat
df -h /mnt/raid
```

Нужны `active raid1`, `[2/2] [UU]` и `/dev/md0`, смонтированный в `/mnt/raid`.

## 3. Расширение LVM без потери данных

Бонусная проверка: том увеличивается с 200 до 300 МиБ вместе с ext4.
Эта команда с `+100M` выполняется **один раз** после создания тома.

```bash
sudo lvextend -L +100M -r /dev/vg_data/lv_logs
sudo lvs
df -h /mnt/logs
cat /mnt/logs/storage-check.txt
```

В `lvs` ожидается `300.00m`; контрольный файл должен сохраниться. Доступный
размер из `df` меньше размера LV из-за метаданных и резерва файловой системы.

RAID и LVM используют разные учебные диски. Зеркало не защищает том логов;
все три файла лежат на одном физическом диске VM и не заменяют резервную копию.

## 4. Самоподписанный сертификат

Посмотрите `hostname -I` и задайте IPv4, по которому клиент подключается к Ubuntu.
Для исходной VM это `192.168.252.3`; на другой машине адрес нужно заменить.
Создание останавливается, если сертификат или ключ уже существуют.

```bash
LAB_IP=192.168.252.3
sudo bash -s -- "$LAB_IP" <<'TLS'
set -Eeuo pipefail
if [[ -e /etc/ssl/certs/my-app.crt || -e /etc/ssl/private/my-app.key ]]; then
    echo 'Остановлено: сертификат или ключ уже существует; проверьте эту пару.' >&2
    exit 1
fi
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/my-app.key \
  -out /etc/ssl/certs/my-app.crt \
  -subj '/CN=my-app.local' \
  -addext "subjectAltName=DNS:my-app.local,IP:$1"
chmod 0600 /etc/ssl/private/my-app.key
openssl x509 -in /etc/ssl/certs/my-app.crt -noout -subject -dates -ext subjectAltName
TLS
```

Закрытый ключ, файлы-диски и машинные UUID не добавляются в Git.
После подготовки вернитесь к разделу «Запуск» инструкции ДЗ №2 и создайте
контейнер, службы и конфигурацию Nginx. `lab-storage.service` затем будет
восстанавливать существующее хранилище после перезагрузки без форматирования.
