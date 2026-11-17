#!/usr/bin/env bash
set -euo pipefail
fail() { printf '%s\n' "$*" >&2; exit 1; }
options=()
case "$#" in
  0) ;;
  1) [[ $1 == --dry-run ]] || fail 'Использование: deploy.sh [--dry-run]'
     options=(--dry-run) ;;
  *) fail 'Использование: deploy.sh [--dry-run]' ;;
esac
root=$(git rev-parse --show-toplevel) || fail 'Запустите сценарий из репозитория'
[[ -f "$root/site/index.html" ]] || fail 'Отсутствует site/index.html'
status=$(git -C "$root" status --porcelain) || fail 'Ошибка git status'
[[ -z "$status" ]] || fail 'В репозитории есть незафиксированные изменения'
remote=${DEPLOY_REMOTE:-devops}
cert=${DEPLOY_CA_CERT:-"$HOME/devops.crt"}
shell=${DEPLOY_RSYNC_RSH:-'ssh -o BatchMode=yes -o ConnectTimeout=5'}
curl_options=()
if [[ -n ${DEPLOY_CONNECT_TO:-} ]]; then
    curl_options=(--connect-to "$DEPLOY_CONNECT_TO")
fi
rsync -avz --delete --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r ${options[@]+"${options[@]}"} -e "$shell" \
    "$root/site/" "$remote:/var/www/devops-site/" || fail 'Ошибка доставки rsync'
(($# == 0)) || exit 0
curl --noproxy '*' -fsS --max-time 10 --cacert "$cert" ${curl_options[@]+"${curl_options[@]}"} \
    -o /dev/null https://devops.local/ || fail 'Проверка HTTPS не пройдена'
git -C "$root" rev-parse --short HEAD
