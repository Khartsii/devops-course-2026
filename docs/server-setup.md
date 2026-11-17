# Конфигурация виртуальной машины devops-vm

Подготовка выполнена на Mac с Apple Silicon и VirtualBox 7.2.22. На devops-vm установлена и обновлена Ubuntu Server 24.04.5 LTS arm64. SSH через NAT и UFW проверены на работающей машине.

## 1. Параметры машины

Настроены 2048 МБ ОЗУ, 2 vCPU и динамический диск VDI 25 ГиБ. Перед установкой SHA-256 официального ISO Ubuntu Server 24.04.5 LTS arm64 сверена с SHA256SUMS Canonical. Для успешного запуска заданы EFI и графический контроллер VMSVGA. Apple Silicon требует сборку VirtualBox для macOS Arm64 и ISO Ubuntu Server arm64. На Intel используются сборка для macOS Intel и ISO amd64. Для OVA заранее проверьте архитектуру гостя.

Установите обычную редакцию Server, выберите English, Use an entire disk, hostname `devops-vm`, пользователя `student` и компонент OpenSSH Server. Featured Snaps оставьте пустым. После входа в консоль выполните `sudo apt update && sudo apt upgrade -y`.

## 2. Сетевые интерфейсы

- Адаптер 1: NAT, интерфейс `enp0s8`, DHCP, фактический адрес `10.0.2.15/24`, выход к репозиториям.
- Адаптер 2: Host-only, интерфейс `enp0s9`, DHCP, фактический адрес `192.168.56.3/24`. В VirtualBox создана Host-Only Network `devops-hostonly` в сегменте `192.168.56.0/24` с диапазоном `192.168.56.1–192.168.56.101`. Гость пингует Mac по адресу `192.168.56.1`. Обратное соединение из текущего сеанса вернуло `No route to host`.
- Проверьте `ip -brief address`, зафиксируйте фактические адреса и `systemctl status ssh --no-pager`.
- Для §4.4 только после разрешения на Mac добавьте в `/etc/hosts` запись `192.168.56.3 devops.local` после сверки адреса командой `ip -brief address`. Проверьте `ping -c 3 devops.local` и `ssh -i ~/.ssh/devops_vm -p 2222 devops@devops.local`. На госте выполните `sudo hostnamectl set-hostname devops-vm` и замените либо добавьте строку `127.0.1.1 devops-vm.devops.local devops-vm` в `/etc/hosts`. Проверьте `hostname -f`. В госте подтверждено имя `devops-vm.devops.local`. Назначение `devops.local` в macOS и подключение по нему ожидают проверки.

## 3. Правило проброса портов

В NAT создайте правило `ssh`, TCP, адрес хоста `127.0.0.1`, порт хоста `2222`, адрес гостя пустой, порт гостя сначала `22`. После смены порта sshd порт гостя изменён на `2222`. Финальная запись `ssh,tcp,127.0.0.1,2222,,2222`. При доступности редактируйте проброс на работающей VM, чтобы сохранить текущую SSH-сессию; держите открытой и консоль VirtualBox.

## 4. Учётные записи

Сверьте отпечаток ED25519 при первом соединении с выводом `sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` в консоли гостя. Войдите как `ssh -p 2222 student@127.0.0.1`. Учётная запись student, созданная установщиком, имеет sudo; после усиления SSH используйте её в консоли. В госте выполните:

```bash
sudo adduser devops
sudo usermod -aG sudo devops
groups devops
```

Для проверки использовался отдельный ключ ED25519 и отдельный файл настроек клиента внутри рабочей папки. При восстановлении при необходимости создайте ключ, затем установите открытый ключ:

```bash
ssh-keygen -t ed25519 -C devops-vm-key -f ~/.ssh/devops_vm
ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1
ssh -o IdentitiesOnly=yes -i ~/.ssh/devops_vm -p 2222 devops@127.0.0.1
```

Если ssh-copy-id отсутствует, передайте содержимое только .pub через SSH: `ssh -p 2222 devops@127.0.0.1 'umask 077; mkdir -p ~/.ssh; chmod 700 ~/.ssh; cat >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys' < ~/.ssh/devops_vm.pub`. В госте проверьте `stat -c '%a %n' ~/.ssh ~/.ssh/authorized_keys` (700 и 600). На Mac зафиксируйте методы через `ssh -vvv -i ~/.ssh/devops_vm -p 2222 devops@127.0.0.1 true 2>&1 | grep -i 'authentications that can continue'`. Добавьте блок в конфигурацию SSH клиента после разрешения на изменение файла:

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

Проверьте `ssh devops` и создайте второй снимок.

## 5. Служба SSH

В активной сессии сохраните `sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup`. Создайте `/etc/ssh/sshd_config.d/99-hardening.conf` в госте:

```text
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Проверьте более ранние файлы через `grep -r PasswordAuthentication /etc/ssh/sshd_config.d/ /etc/ssh/sshd_config`; сохраните резервную копию и закомментируйте конфликтующую директиву, если она есть. В текущей установке конфликтующая строка находилась в `50-cloud-init.conf` и была закомментирована с сохранением копии. Убедитесь, что клавиатурно-интерактивный вход отключён (`kbdinteractiveauthentication no` в `sshd -T`); при необходимости установите `KbdInteractiveAuthentication no` в действующей конфигурации.

```bash
sudo sshd -t && echo "Конфигурация корректна"
sudo sshd -T | grep -Ei '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers|kbdinteractiveauthentication) '
```

Продолжайте после успешной проверки. Переведите SSH на обычный сервис и проверьте сокеты:

```bash
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd
```

Обновите проброс. В новом терминале выполните `ssh devops`, затем на своей VM проверьте ожидаемые отказы `ssh -p 2222 root@127.0.0.1` и `ssh -p 2222 -o PubkeyAuthentication=no devops@127.0.0.1`. Сопоставьте диагностику с `sudo journalctl -u ssh --since '10 min ago' --no-pager`. Исходную сессию закрывайте после успешного второго входа. При потере доступа исправьте конфигурацию через консоль VM. Создайте третий снимок.

## 6. Правила межсетевого экрана

В госте проверьте наличие UFW и его начальный статус. Выполните из консоли VM или сохраняя действующую SSH-сессию:

```bash
sudo ufw status verbose
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw status numbered
```

Проверьте свежий вход по SSH. Из консоли гостя замените правило командами `sudo ufw delete allow 2222/tcp` и `sudo ufw limit 2222/tcp comment 'SSH rate-limited'`, затем проверьте `sudo ufw status verbose` и снова подключитесь. Включите `sudo ufw logging medium`. С Mac выполните `curl -m 3 http://<Host-only-IP>:8080` с фактическим IP вместо заполнителя. В госте выполните `sudo grep 'UFW BLOCK' /var/log/ufw.log | tail -5`; если файл отсутствует, используйте `sudo journalctl -k --since '10 min ago' | grep 'UFW BLOCK'`. Зафиксируйте SRC, DST, PROTO и DPT. В текущем сеансе прямой запрос к Host-only вернул `No route to host`. Проверку выполнили через временный проброс `127.0.0.1:18080 → 8080`, который затем удалили. Журнал гостя подтвердил `SRC=10.0.2.2 DST=10.0.2.15 PROTO=TCP DPT=8080` на `enp0s8`.

## 7. Снимки состояния

| Снимок | Момент создания |
| --- | --- |
| 01-clean-install | После установки, обновления и выключения гостя |
| 02-keys-configured | После проверки входа по ключу через `ssh devops` |
| 03-ssh-hardened | После усиления SSH, проверки порта и отказов |

Созданы все три снимка. UFW и гостевой FQDN настроены после снимка 03-ssh-hardened. При восстановлении с 01-clean-install проверьте проброс на гостевой порт 22 и повторите разделы 4–6, затем шаги локального имени из раздела 2.

Проверка §6.2 в госте: `bash scripts/audit.sh; echo $?`. Затем временно замените `MaxAuthTries 3` на `MaxAuthTries 10`, проверьте синтаксис `sudo sshd -t` и повторите аудит. Для проверки скрипта достаточно изменения файла, так как он читает `sshd -T`; перезапускать службу с ослабленным лимитом не требуется. Восстановите значение 3 и подтвердите код 0 повторным запуском. На работающей Ubuntu получены коды 0, 1, 0. После проверки восстановлено значение 3.

## 8. Веб-сервер

На Ubuntu установлен пакет nginx. UFW разрешает 80/tcp и 443/tcp. Ресурс
`devops.local` обслуживается из `/var/www/devops-site` (devops:devops, 755).
Файлы, включая `404.html`, принадлежат devops:devops и имеют права 644.
Активная конфигурация — `/etc/nginx/sites-available/devops-site`, ссылка —
`/etc/nginx/sites-enabled/devops-site`. HTTP перенаправляется на HTTPS кодом 301.
При восстановлении:

```bash
sudo apt update && sudo apt install -y nginx rsync
sudo install -d -m 755 -o devops -g devops /var/www/devops-site
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt \
  -subj /CN=devops.local -addext subjectAltName=DNS:devops.local
sudo chown root:root /etc/ssl/private/devops.key /etc/ssl/certs/devops.crt
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
sudo install -m 644 nginx/devops-site.conf /etc/nginx/sites-available/devops-site
sudo ln -sfn /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/devops-site
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

Публичный сертификат действует 365 дней. На клиенте передайте его через
`curl --cacert`. Закрытый ключ служит только Nginx на VM.
При штатной настройке скрипт `scripts/deploy.sh` использует псевдоним SSH
`devops`, сертификат `~/devops.crt` и URL `https://devops.local/`.
Если Host-only недоступен, можно указать отдельную настройку клиента
`DEPLOY_RSYNC_RSH`, путь `DEPLOY_CA_CERT` и адрес для `curl --connect-to`
через `DEPLOY_CONNECT_TO=devops.local:443:127.0.0.1:18443`. Это требует
NAT-проброса 18443 → 443, ограниченного loopback Mac. Снимок VirtualBox
`04-nginx-https` сделан после проверки HTTPS и до синхронизации сайта.
