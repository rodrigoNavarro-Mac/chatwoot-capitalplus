# Webhooks de WhatsApp — bug de resolución de canal por número mexicano

Documento de handoff. Cubre el bug que impedía que los mensajes entrantes de WhatsApp al número
**+52 55 6944 0704** (Capital Plus Bienes Raíces, `phone_number_id` `1282565294938901`, account_id
2, inbox "Fuego") llegaran a Chatwoot. Reportado originalmente como "webhook entrante roto,
pendiente de Meta" — resultó ser un bug de Chatwoot, no de Meta. Resuelto y verificado en
producción el 2026-08-13.

## Síntoma

Los webhooks de Meta para ese número específico eran rechazados (401) o, tras un primer fix
parcial, se aceptaban pero el job de Sidekiq los descartaba en silencio con
`Inactive WhatsApp channel: unknown -` — la conversación nunca aparecía en el dashboard.

## Causa raíz

Meta agrega un dígito "1" extra a los números móviles mexicanos en
`metadata.display_phone_number` del payload del webhook (ej. `5215569440704`), dígito que **no**
está presente en el `phone_number` guardado en el canal de Chatwoot (`+525569440704`). Esta
distorsión ya era conocida y estaba resuelta para el envío de campañas salientes
(`Whatsapp::CsvContactPhoneNormalizer`), pero **no** para la resolución de canal en webhooks
entrantes, donde dos ubicaciones distintas hacían match por string contra `display_phone_number`
en lugar de por `phone_number_id` (estable, no sufre esta distorsión):

| # | Bug | Ubicación | Fix |
|---|---|---|---|
| 1 | El controller rechazaba el webhook (401) antes de poder verificar la firma, porque no encontraba el canal | `app/controllers/webhooks/whatsapp_controller.rb#whatsapp_business_payload_channel` | Resuelve el canal con `Channel::Whatsapp.find_by("provider_config ->> 'phone_number_id' = ?", phone_number_id)` en vez de matchear por `display_phone_number` |
| 2 | El job de Sidekiq encolado por el controller volvía a resolver el canal con la misma lógica rota y descartaba el mensaje silenciosamente (`Inactive WhatsApp channel: unknown -`) | `app/jobs/webhooks/whatsapp_events_job.rb#get_channel_from_wb_payload` | Mismo fix: match por `phone_number_id` |

## Deploy

- Commit: `1c06893b3` en la rama `fix/whatsapp-webhook-phone-id-lookup`.
- Tests: 12/12 en `spec/controllers/webhooks/whatsapp_controller_spec.rb`, 22/22 en
  `spec/jobs/webhooks/whatsapp_events_job_spec.rb` (incluye regresión específica para el caso del
  "1" extra mexicano en ambos specs).
- Aplicado en producción el 2026-08-13 vía parche manual en caliente (`docker compose cp` +
  reinicio) en **ambos** contenedores — `rails` y `sidekiq` corren la misma imagen pero son
  contenedores separados, así que el archivo tuvo que copiarse a los dos por separado. El primer
  intento solo tocó `rails` y el job seguía fallando hasta corregir también `sidekiq`.
- Verificado end-to-end: mensaje real de prueba creó la conversación `#270` / mensaje `#2700` en
  la cuenta 2, asignada correctamente.
- **Pendiente**: mergear `fix/whatsapp-webhook-phone-id-lookup` a `main` para que el pipeline de
  GitHub Actions reconstruya la imagen en `ghcr.io/rodrigonavarro-mac/chatwoot-capitalplus` con el
  fix incluido de forma permanente — el parche en caliente se pierde en el próximo
  `docker compose pull`/rebuild si no se mergea.
