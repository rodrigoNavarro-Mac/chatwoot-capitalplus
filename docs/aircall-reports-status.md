# Aircall + Reportes (Embudo de ventas / Reporte Semanal) — estado y pendientes

Documento de handoff para continuar este trabajo en otra sesión. Cubre todo lo construido en la
rama `main` entre los commits `314bc8b86` (backfill de Aircall) y `9cf959d34` (fix de timezone),
generado 2026-08-12. Cuenta de referencia en producción: **account_id 2 ("Capital Plus")**, inbox
**"Fuego"**.

## Qué se construyó

1. **Backfill histórico de llamadas de Aircall** — `Crm::Aircall::CallHistoryBackfillService` trae
   todo el historial vía `GET /v1/calls` (Basic Auth con `api_id`/`api_token` guardados en el mismo
   `Integrations::Hook` que ya tenía el `webhook_secret`), paginando mes a mes para respetar el
   límite de 10,000 resultados de Aircall. Corrido en producción: **1373 llamadas procesadas, 303
   guardadas como `Call`** (el resto son llamadas sin contacto/conversación existente en Chatwoot).
2. **`Crm::Aircall::CallProcessor`** — lógica compartida entre el webhook en tiempo real
   (`Crm::Aircall::InboundWebhookService`) y el backfill: resuelve contacto por teléfono, adjunta
   la llamada a su conversación más antigua, crea un `Message` real (`content_type: voice_call`)
   vía `Voice::CallMessageBuilder` — así `V2::Reports::SalesFunnelBuilder#customer_replied` ya
   cuenta una llamada contestada como "cliente contestó" sin ningún cambio ahí.
3. **Secciones de llamadas en los reportes**:
   - Embudo de ventas: `calls: { total, answered, answered_percent }` por inbox/desarrollo
     (`V2::Reports::SalesFunnelBuilder#calls_metric`).
   - Reporte semanal: sección "Llamadas (Aircall)" con desglose por asesor
     (`V2::Reports::WeeklyOpsReportCallsMetrics`), en dashboard + PDF/DOCX.
4. **Reportes por mes/trimestre** — nueva columna `period_type` en `weekly_ops_reports`, selector
   en el dashboard (semana/mes/trimestre), y una gráfica de línea "Leads creados por periodo"
   (`V2::Reports::LeadsTimelineMetrics`) que bucketea los leads de Zoho ya traídos por
   `zoho_leads_metrics` (memoizados, sin llamada extra a Zoho) — granularidad día/semana/mes según
   el tipo de reporte.

## Bugs encontrados y corregidos en esta sesión

| # | Bug | Causa raíz | Fix |
|---|---|---|---|
| 1 | Backfill procesó 1372 llamadas pero guardó 0 | El endpoint REST de historial devuelve `raw_digits` con espacios (`"+52 983 195 0040"`), a diferencia del webhook — nunca hacía match contra `Contact#phone_number` | `d12f25fc7` — normaliza espacios en `CallProcessor#raw_digits` |
| 2 | Llamadas backfilled quedaban fechadas "hoy" (el día del backfill), no la fecha real de la llamada | `Voice::CallMessageBuilder` no fijaba `created_at` al crear el `Message` | `79d0176ec` — `Messages::MessageBuilder` ahora acepta `created_at` real; `Voice::CallMessageBuilder` lo usa con `call.started_at` |
| 3 | Efecto secundario del bug #2: `conversation.last_activity_at`/`waiting_since` de 292 conversaciones quedaron "rebobinados" a la fecha del backfill | Los callbacks normales de `Message` (`set_conversation_activity`, `set_waiting_since_on_incoming_message`) asumen que todo mensaje nace en tiempo real | `79d0176ec` — `Crm::Aircall::CallProcessor` restaura `last_activity_at`/`waiting_since` cuando el mensaje backdated no es más reciente que la actividad previa. Reparación de los 303 registros ya afectados: `ea003881f` (`rake chatwoot:repair_aircall_backdated_activity`, ya corrido en producción: 303 mensajes corregidos, 137 conversaciones recalculadas) |
| 4 | El embudo de ventas (5 etapas: leads → customer_replied → has_deal → visita_efectiva → closed_won) nunca aparecía en el PDF/DOCX exportado | `kpis.pipeline.stages` solo se renderizaba en el dashboard Vue — `weekly_ops_report_pdf_service.rb`/`weekly_ops_report_docx_service.rb` nunca lo incluían | `9657ea3ce` — agrega `funnel_rows` compartido + tabla "Embudo de ventas" en ambos formatos |
| 5 | El reporte corría un día extra en husos horarios detrás de UTC (México, UTC-6): rango 3-9 mostraba hasta el 10 | `toUnixSeconds` en `WeeklyOpsReport.vue` armaba el timestamp de "hasta" en la zona horaria LOCAL del navegador (sin sufijo `Z`); el backend interpreta since/until como epoch UTC — "9 de agosto 23:59:59 local" cruza a "10 de agosto" en UTC | `615bb1dc5` — agrega `Z` al string antes de parsearlo, forzando UTC |

## ⚠️ Pendiente de verificar — no confirmado en producción

- ~~Los fixes #4 y #5 (embudo en PDF, timezone) sin desplegar/confirmar~~ — **confirmado por el
  usuario el 2026-08-12: ya desplegado y funcionando en producción.** El embudo aparece en el
  PDF/DOCX y el rango de fechas ya no corre un día de más.
- **El webhook de Aircall en tiempo real nunca se probó end-to-end con una llamada real** — se
  configuró el `Integrations::Hook` (`account_id: 2, app_id: 'aircall'`, todos los scopes) y se
  verificó que el endpoint responde 200 con la ruta/secreto correctos, pero no hay confirmación de
  que una llamada real de Aircall haya llegado y se haya reflejado como mensaje. Si algo falla ahí,
  revisar logs de Rails (`docker compose logs rails -f | grep -i aircall`) durante una llamada de
  prueba.
- Si después de desplegar el usuario sigue reportando que "el embudo no funciona correctamente",
  el síntoma reportado hasta ahora ("no sale en el PDF") ya tiene fix — cualquier reclamo posterior
  sería sobre la EXACTITUD de las etapas (conteos), no sobre que la sección exista. Ver
  `V2::Reports::SalesFunnelBuilder` (`app/builders/v2/reports/sales_funnel_builder.rb`) para la
  lógica de detección de cada etapa — ya tiene manejo de valores huérfanos del picklist de Zoho
  (`VISITA_EFECTIVA_STAGES`), pero si aparece un nuevo valor de Stage no listado ahí, hay que
  agregarlo (mismo patrón que las correcciones anteriores en este mismo builder).

## Mapa de archivos (para orientarse rápido)

**Aircall (llamadas):**
- `app/services/crm/aircall/call_processor.rb` — procesamiento compartido de una llamada
- `app/services/crm/aircall/inbound_webhook_service.rb` — webhook en tiempo real
- `app/services/crm/aircall/call_history_backfill_service.rb` — backfill histórico
- `app/services/crm/aircall/api/calls_client.rb` — cliente REST (Basic Auth)
- `lib/tasks/repair_aircall_backdated_activity.rake` — reparación de datos (ya corrida)
- `enterprise/app/services/voice/call_message_builder.rb` — crea el `Message` del `Call`

**Reportes:**
- `app/builders/v2/reports/sales_funnel_builder.rb` — embudo de ventas (5 etapas + calls_metric)
- `app/builders/v2/reports/weekly_ops_report_builder.rb` — reporte semanal (orquesta todo)
- `app/builders/v2/reports/weekly_ops_report_calls_metrics.rb` — sección de llamadas por asesor
- `app/builders/v2/reports/leads_timeline_metrics.rb` — gráfica de leads por periodo
- `app/services/reports/report_summary_rows.rb` — filas compartidas PDF/DOCX
- `app/services/reports/weekly_ops_report_pdf_service.rb` / `weekly_ops_report_docx_service.rb` —
  exports
- `app/javascript/dashboard/routes/dashboard/settings/reports/WeeklyOpsReport.vue` /
  `SalesFunnelReport.vue` — dashboard
- `app/models/weekly_ops_report.rb` — modelo (`period_type` enum: week/month/quarter)

## Cómo verificar

```bash
# Specs backend (Docker)
docker compose -f docker-compose.dev.yml exec -T rails bundle exec rspec \
  spec/builders/v2/reports/ spec/services/reports/ spec/services/crm/aircall/ \
  spec/models/weekly_ops_report_spec.rb spec/requests/api/v1/accounts/weekly_ops_reports_spec.rb

# RuboCop
docker compose -f docker-compose.dev.yml exec -T rails bundle exec rubocop <archivo>

# Deploy producción
docker compose -f docker-compose.production.yml pull rails
docker compose -f docker-compose.production.yml up -d
```

Nota: hay una falla preexistente y no relacionada en `spec/builders/v2/reports/label_summary_builder_spec.rb`
(5 ejemplos, error `Net::SMTPAuthenticationError`) — no es de este trabajo, es un problema de
configuración SMTP del entorno de test.
