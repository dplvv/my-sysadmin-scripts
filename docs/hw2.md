# ДЗ №2 — мониторинг ресурсов в Docker

[Все задания](../README.md) · [Версия hw2](https://github.com/dplvv/my-sysadmin-scripts/tree/hw2)

Вариант Б. Скрипт каждые 5 секунд записывает `free -h`, `df -h` и `uptime` в `monitor.log`.

## Устройство проекта

- Docker запускает мониторинг и HTTP-сервер на порту 8080.
- Лог хранится на LVM-томе `vg_data/lv_logs`: `/mnt/logs` на хосте подключён к `/var/www` контейнера. Том расширен с 200 до 300 МиБ.
- RAID 1 из `disk1.img` и `disk2.img` смонтирован в `/mnt/raid`; для LVM используется `disk3.img`.
- Nginx принимает HTTPS на порту 443, проксирует на `127.0.0.1:8080` и перенаправляет HTTP на HTTPS.
- `lab-storage.service` восстанавливает хранилище, `my-app.service` запускает контейнер и перезапускает его при ошибке.

## Запуск

Для новой Ubuntu сначала выполните [первоначальную подготовку](hw2-setup.md): установка зависимостей, создание RAID/LVM, `raid.conf`, `raid.uuid` и сертификата. На работающей VM повторно создавать хранилище не нужно.

Команды ниже выполняются из корня репозитория после подготовки. Контейнер `my-app` и его конфигурационные файлы при первой установке ещё не должны существовать:

```bash
sudo docker build -t my-script .
sudo docker create --name my-app \
  -p 127.0.0.1:8080:8080 \
  --mount type=bind,src=/mnt/logs,dst=/var/www \
  my-script

sudo install -m 0755 restore-storage.sh /usr/local/sbin/restore-lab-storage.sh
sudo cp deploy/*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now lab-storage my-app
sleep 3

sudo cp deploy/nginx.conf /etc/nginx/sites-available/my-app
if [ -L /etc/nginx/sites-enabled/default ] &&
   [ "$(readlink -f /etc/nginx/sites-enabled/default)" = /etc/nginx/sites-available/default ]; then
    sudo unlink /etc/nginx/sites-enabled/default
fi
sudo ln -s /etc/nginx/sites-available/my-app /etc/nginx/sites-enabled/my-app
sudo nginx -t && sudo systemctl enable --now nginx && sudo systemctl reload nginx
```

Остановка: `sudo systemctl stop my-app`.

## Проверка

```bash
sudo docker ps
sudo nginx -t
curl -I http://127.0.0.1:8080/monitor.log
curl -I http://127.0.0.1/
curl -kI https://127.0.0.1/monitor.log
sudo systemctl status my-app --no-pager
systemctl is-enabled my-app
cat /proc/mdstat
sudo pvs
sudo vgs
sudo lvs
df -h /mnt/raid /mnt/logs
curl -kI 'https://127.0.0.1/monitor.log?check=hw2'
sudo journalctl -u my-app -n 30 --no-pager
sudo tail -n 20 /var/log/nginx/access.log
sudo tail -n 20 /var/log/nginx/error.log
```

Ожидается: HTTP на порту 80 — **301**, приложение и HTTPS — **200**; `my-app` — **active (running)** и **enabled**. Для `lab-storage` нормально **active (exited)**. После перезагрузки повторите проверки.

Флаг `-k` отключает проверку доверия к самоподписанному сертификату. При запросе с другого компьютера используйте IP-адрес Ubuntu. Проверка с доверием к созданному сертификату: `curl --cacert /etc/ssl/certs/my-app.crt -I https://<IP-из-SAN>/monitor.log`.

Для повторного запуска достаточно `sudo systemctl start my-app`; `docker create` заново не нужен. Перед первым HTTP-запросом дайте приложению около 3 секунд на запуск.

### Docker Compose

Плагин Compose устанавливается в разделе первоначальной подготовки. Это отдельный запуск на порту 8081.

```bash
sudo systemctl stop my-app
sudo docker compose up -d --build
sleep 3
sudo docker compose ps
curl -I http://127.0.0.1:8081/monitor.log
sudo docker compose down
sudo systemctl start my-app
```

## Что прикрепить к сдаче

Ссылка на версию `hw2` и скриншоты: сборка/запуск Docker; RAID и `df`; LVM до и после расширения с контрольным файлом; успешный `nginx -t`; HTTPS `200` с другого компьютера; `systemctl status` и `is-enabled`; запрос в journal и `access.log`. Один скриншот может подтверждать несколько пунктов.

## Результаты

- [Скриншоты проверок ДЗ №2](../screenshots/hw2/).

- [Пример мониторинга](../sample_output.txt) — три полных измерения.
- [Сборка образа](../evidence/docker-build.txt).
- [Проверка Nginx](../evidence/nginx-test.txt).
- [Ответ HTTPS](../evidence/https-headers.txt).
- [Журнал службы](../evidence/journal.txt) и [запросы Nginx](../evidence/nginx-access.txt).
