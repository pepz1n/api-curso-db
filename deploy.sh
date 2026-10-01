#!/usr/bin/env bash
# Atualiza a API e o banco na EC2: baixa o código novo e recria os containers.
# Os dados do banco ficam no volume db-data e não são apagados.
set -e
cd "$(dirname "$0")"

echo ">> Baixando a versão mais recente"
git -C ../api-curso pull
git pull

echo ">> Recriando os containers"
docker compose up -d --build

echo ">> Limpando imagens antigas"
docker image prune -f

docker compose ps
