#!/bin/bash
# setup.sh — Corre UNA VEZ en el servidor Hetzner recién creado (Ubuntu 24.04)
# Uso: bash setup.sh TU_DOMINIO.COM tu@email.com
set -e

DOMAIN=${1:?"Uso: bash setup.sh TU_DOMINIO.COM tu@email.com"}
EMAIL=${2:?"Uso: bash setup.sh TU_DOMINIO.COM tu@email.com"}

echo "==> [1/6] Actualizando sistema..."
apt-get update -q && apt-get upgrade -y -q

echo "==> [2/6] Instalando Docker..."
curl -fsSL https://get.docker.com | sh
systemctl enable docker

echo "==> [3/6] Configurando swap (2 GB) para el build de la imagen..."
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "==> [4/6] Configurando firewall..."
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw --force enable

echo "==> [5/6] Creando directorio de la app..."
mkdir -p /opt/chatwoot
cd /opt/chatwoot

echo "==> [6/6] Clonando repositorio..."
if [ ! -d ".git" ]; then
  # Reemplaza con la URL de tu repositorio
  git clone https://github.com/TU_ORG/TU_REPO.git .
fi

echo ""
echo "✓ Servidor listo."
echo ""
echo "Próximos pasos:"
echo "  1. cd /opt/chatwoot/deploy"
echo "  2. cp .env.production.example .env.production"
echo "  3. nano .env.production  (llena todas las variables)"
echo "  4. sed -i 's/TU_DOMINIO.COM/$DOMAIN/g' nginx/chatwoot.conf"
echo "  5. bash deploy.sh --first-run $DOMAIN $EMAIL"
