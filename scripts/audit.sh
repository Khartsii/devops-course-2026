#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C
PASS=0
FAIL=0

check() {
    local description="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  [OK]   %s\n' "$description"
        ((PASS += 1))
    else
        printf '  [FAIL] %s (ожидалось: %s, получено: %s)\n' "$description" "$expected" "$actual"
        ((FAIL += 1))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo '[1] Служба SSH'
if ssh_config=$(sudo sshd -T); then
    check 'Вход root' no "$(awk '$1=="permitrootlogin" {print $2}' <<< "$ssh_config")"
    check 'Парольная аутентификация' no "$(awk '$1=="passwordauthentication" {print $2}' <<< "$ssh_config")"
    ports=$(awk '$1=="port" {print $2}' <<< "$ssh_config")
    port_check=$(awk '$1=="port" {n++; if ($2 !~ /^[0-9]+$/ || $2 < 1 || $2 > 65535 || $2 == 22) bad=1} END {print (n && !bad ? "да" : "нет")}' <<< "$ssh_config")
    check "Заданы только порты SSH, отличные от 22 (${ports//$'\n'/, })" да "$port_check"
    check 'Лимит попыток аутентификации' 3 "$(awk '$1=="maxauthtries" {print $2}' <<< "$ssh_config")"
else
    check 'Чтение действующей конфигурации SSH' доступно ошибка
fi

echo '[2] Межсетевой экран'
if firewall=$(sudo ufw status verbose); then
    check 'Статус UFW' active "$(awk '$1=="Status:" {print $2}' <<< "$firewall")"
    check 'Политика для входящего трафика' deny "$(awk '$1=="Default:" && $3=="(incoming)," {print $2}' <<< "$firewall")"
else
    check 'Чтение конфигурации UFW' доступно ошибка
fi

echo '[3] Учётные записи'
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd
echo '[4] Веб-сервер'
check 'Nginx запущен' active "$(systemctl is-active nginx)"
nginx_config=error
if sudo nginx -t; then nginx_config=ok; fi
check 'Синтаксис Nginx' ok "$nginx_config"
cert_state=error
if openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend "${AUDIT_CERT_MIN_SECONDS:-2592000}"; then
    cert_state=ok
fi
check 'Срок сертификата' ok "$cert_state"
if writable=$(find /var/www/devops-site -perm -0002 -print) &&
    key_mode=$(sudo stat -c '%a' /etc/ssl/private/devops.key) &&
    [[ -z "$writable" && "$key_mode" == 600 ]]; then
    check 'Права ресурса и ключа' ok ok
else
    check 'Права ресурса и ключа' ok error
fi

echo '[5] Контейнеризация'
check 'Docker запущен' active "$(systemctl is-active docker)"
health=$(docker inspect -f '{{.State.Health.Status}}' app-db-1) || health=error
check 'PostgreSQL успешно проходит healthcheck' healthy "$health"
binding=error
if listeners=$(ss -H -tln) && awk '
    $4 ~ /:(5000|5432)$/ && $4 !~ /^127[.]0[.]0[.]1:/ {bad=1}
    $4 == "127.0.0.1:5000" {app=1}
    END {exit (bad || !app)}
' <<< "$listeners"; then
    binding=ok
fi
check 'Привязка портов приложения и СУБД' ok "$binding"
env_mode=$(stat -c '%a' /home/devops/app/.env) || env_mode=error
check 'Права файла окружения' 600 "$env_mode"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]]
