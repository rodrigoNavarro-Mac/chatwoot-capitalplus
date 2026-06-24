#!/bin/bash
# deploy.sh — Despliega o actualiza Chatwoot en producción
# Primer deploy: bash deploy.sh --first-run TU_DOMINIO.COM tu@email.com
# Actualizaciones: bash deploy.sh
set -e

cd /opt/chatwoot/deploy

FIRST_RUN=false
if [ "$1" = "--first-run" ]; then
  FIRST_RUN=true
  DOMAIN=$2
  EMAIL=$3
fi

echo "==> Actualizando código..."
cd /opt/chatwoot
git pull origin develop

echo "==> Construyendo imagen Docker..."
cd /opt/chatwoot/deploy
docker compose -f docker-compose.production.yml build rails

# Primer deploy: obtener certificado SSL antes de levantar nginx con HTTPS
if [ "$FIRST_RUN" = true ]; then
  echo "==> [FIRST RUN] Levantando nginx en modo HTTP para obtener certificado SSL..."

  # Levanta solo nginx en modo HTTP temporalmente (sin bloque SSL)
  docker compose -f docker-compose.production.yml up -d nginx

  echo "==> [FIRST RUN] Solicitando certificado SSL a Let's Encrypt..."
  docker compose -f docker-compose.production.yml run --rm certbot \
    certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email "$EMAIL" \
    --agree-tos \
    --no-eff-email \
    -d "$DOMAIN"

  echo "==> [FIRST RUN] Reiniciando nginx con SSL habilitado..."
  docker compose -f docker-compose.production.yml restart nginx

  echo "==> [FIRST RUN] Generando encryption keys de ActiveRecord..."
  docker compose -f docker-compose.production.yml run --rm rails \
    bundle exec rails db:encryption:init
  echo "⚠  Copia esas 3 claves a .env.production antes de continuar"
  echo "   Presiona ENTER cuando hayas guardado las claves..."
  read -r
fi

echo "==> Levantando todos los servicios..."
docker compose -f docker-compose.production.yml up -d

echo "==> Esperando que Rails esté listo..."
sleep 10

echo "==> Estado de los servicios:"
docker compose -f docker-compose.production.yml ps

echo ""
echo "✓ Deploy completado."
echo "  App disponible en: https://$(grep FRONTEND_URL .env.production | cut -d= -f2 | sed 's|https://||')"
