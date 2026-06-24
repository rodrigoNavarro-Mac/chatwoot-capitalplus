#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid

pnpm install

echo 'Ready to run Vite development server.'

exec "$@"
