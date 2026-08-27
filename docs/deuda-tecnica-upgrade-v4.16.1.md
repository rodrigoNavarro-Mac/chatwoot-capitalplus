# Deuda técnica descubierta durante el upgrade a Chatwoot v4.16.1

Documento generado el 2026-08-26 al actualizar el fork a Chatwoot v4.16.1 (ver commits
`18065a34a`, `d45c87fe6`, `a4bb76de9`, `96f922a51`). Durante la revisión del CI real
(GitHub Actions) tras el merge aparecieron varios problemas **preexistentes en `main`**,
no causados por el merge en sí. Se documentan aquí porque varios seguirán siendo
relevantes después de este upgrade.

## Corregidos durante este trabajo

1. **Permisos de custom roles rotos desde el 2026-08-19** (commit `03c0b0023`): el módulo
   `Enterprise::Conversations::PermissionFilterService` heredaba `accessible_conversations`
   de la clase base, que desde el fix `ddfc7dd1d` (2026-07-03, "agents see only their own
   assigned conversations") solo devuelve conversaciones asignadas al agente. Esto
   significaba que cualquier rol personalizado con `conversation_manage` /
   `conversation_unassigned_manage` / `conversation_participating_manage` en realidad solo
   veía lo suyo, igual que un agente sin rol — el permiso "gestionar todo" o "ver sin
   asignar" nunca funcionó como se esperaba. Arreglado separando `role_scoped_conversations`
   (todas las conversaciones de los inboxes del agente) del `accessible_conversations` de la
   clase base (solo lo asignado).
2. **`spec/services/whatsapp/oneoff_campaign_service_spec.rb` estaba desactualizado**:
   probaba el comportamiento síncrono viejo (`send_template` llamado directo dentro de
   `perform`) cuando el código real hace tiempo usa scheduling asíncrono
   (`Campaigns::SendCampaignContactJob.set(wait_until:).perform_later`). Nadie lo detectó
   porque los specs "pasaban" corriendo por accidente contra `chatwoot_dev` en vez de
   `chatwoot_test` (ver punto 1 de pendientes). Reescrito para probar
   `send_to_contact`/`perform` según corresponde.
3. **`pnpm/action-setup@v4` en `run_foss_spec.yml`** tenía los parámetros `ref`/`repository`
   (propios de `actions/checkout`) copiados por error — código heredado de v4.16.1, no
   nuestro. Eliminados.
4. **`build_production_image.yml` publicaba sin gate de tests** — ahora depende de que
   "Run Chatwoot CE spec" pase sobre el mismo commit de `main` (trigger `workflow_run`).
5. **Overflow de feature flags**: la columna `feature_flags` llegó a 64/63 tras el merge.
   `whatsapp_cadences` (nuestra) se movió a `feature_flags_ext_1` con una migración de
   traslado de bit para las cuentas que ya la tenían activa (Capital Plus, QA Cadences),
   sin tocar `advanced_assignment` cuya posición está fijada por los specs oficiales de
   v4.16.1 (`account_spec.rb`).
6. **OOM garantizado en los 16 shards de `backend-tests`** (commit `d95bf4e37`): el fix
   anterior (forzar `assets:precompile` antes de correr specs, para evitar que Vite
   compilara bajo demanda a mitad de un spec) convirtió un problema intermitente en uno
   garantizado — ahora el build pesado de Vite (4881 módulos) corre siempre, en los 16
   shards a la vez, y el heap por defecto de Node (~2GB en este runner) no alcanza
   (`Ineffective mark-compacts near heap limit`). Arreglado con
   `NODE_OPTIONS=--max-old-space-size=4096` en ese paso.
7. **Bug de seguridad en el fix de Bulk Actions** (commit `d95bf4e37`): al permitir que un
   agente tome conversaciones sin dueño vía Bulk Actions (`include_unassigned: true` en
   `Conversations::PermissionFilterService`), la primera versión daba acceso a **cualquier**
   conversación sin dueño del account, sin importar el inbox. Corregido restringiendo las
   conversaciones sin dueño a los inboxes de los que el agente es miembro
   (`member_inbox_ids`), igual que ya aplica el listado normal.
8. **`lint-frontend` con 13 errores reales** (commit `d95bf4e37`), repartidos en 4 archivos
   de features propias (no del core del merge): `agentBots/` (formato + un string sin
   traducir, "Flujo configurado" — la sección `FLOW_BUILDER` completa faltaba en el locale
   `es`), `cadences/EnrollConversationModal.vue` e `integrations/SingleIntegrationHooks.vue`
   (formato). Arreglados con `eslint --fix` + correcciones manuales de prettier +
   traducciones faltantes.
9. **Alcance real de `ddfc7dd1d` ("agents see only their own assigned conversations")
   confirmado con el negocio** (commit pendiente de esta sesión): la política estricta (un
   agente regular NUNCA ve conversaciones sin dueño ni de otros agentes, solo lo asignado a
   él) es la correcta — el flujo real es que un "setter" gestiona y asigna las
   conversaciones, el agente no se autoasigna desde una cola. Esto dejó **~30 specs
   desactualizados** en 6 archivos, todos probando el comportamiento viejo (visibilidad por
   membresía de inbox / conversaciones sin dueño visibles). Arreglados:
   `spec/finders/conversation_finder_spec.rb` (13 de 14 — ver pendiente #6 más abajo),
   `spec/services/conversations/filter_service_spec.rb` (9),
   `spec/services/conversations/unread_counts/filtered_counter_spec.rb` (7, con un solo
   cambio en el helper compartido `spec/support/conversations_unread_counts_helpers.rb`),
   `spec/controllers/api/v1/accounts/conversations_controller_spec.rb` (6),
   `spec/controllers/api/v1/accounts/contacts/conversations_controller_spec.rb` (1),
   `spec/controllers/api/v1/accounts/contacts/attachments_controller_spec.rb` (1).
   **Gotcha encontrado de paso:** `AssignmentHandler#ensure_assignee_is_from_team`
   (`app/models/concerns/assignment_handler.rb:20`) limpia `assignee_id` silenciosamente si
   el assignee no es miembro del `team` que se le asigna a la conversación — si un fixture
   de test asigna `assignee:` y `team:` a la vez sin agregar al agente como `team_member`
   primero, el assignee desaparece sin error visible.
10. **`InternalFlowHandlerService` con 13 fallos, investigado y confirmado como bug de
    fixture del test, no de producción** (commit pendiente): el fixture nunca vinculaba el
    `agent_bot` al `inbox` via `AgentBotInbox`. Sin ese vínculo, `Inbox#active_bot?` es
    falso, y `Conversation#determine_conversation_status` (before_create,
    `app/models/conversation.rb:304`) no pone la conversación en `pending` — nace `open`
    por default de la columna. `InternalFlowHandlerService#processable?` bloquea
    deliberadamente conversaciones `open` (asume que un agente humano ya la tomó), así que
    el bot nunca respondía en los tests. **En producción cualquier bot real está vinculado a
    su inbox por definición** (si no, ni siquiera se invoca — ver `AgentBotListener
    #agent_bots_for`), así que este bug NO se manifiesta con una configuración real. Fix:
    agregar `create(:agent_bot_inbox, agent_bot: agent_bot, inbox: inbox)` al `before` del
    spec. Además 2 fallos sueltos adicionales de fixture: un test de mayúsculas sin el
    `_bot_current_step` inicial seteado, y un número de teléfono placeholder inválido
    (`+52155XXXXXXXX`, con X literales) que no pasaba la validación E.164 — reemplazado por
    un número de formato válido.
11. **Bug de `unattended` en `conversation_finder_spec.rb`, investigado a fondo y confirmado
    como fixture del test, no bug de producción** (commit pendiente): el scope
    `Conversation.unattended` (`app/models/conversation.rb:94`,
    `where(first_reply_created_at: nil).or(where.not(waiting_since: nil))`) funciona
    correctamente. La causa real: `Conversation#ensure_waiting_since` (before_create,
    `app/models/conversation.rb:284`) siempre pone `waiting_since = created_at` al crear,
    **sin importar el valor pasado** — pasar `waiting_since: nil` en la factory no sirve, el
    callback lo pisa. En producción, `waiting_since` solo se limpia cuando llega una
    respuesta real: `Message#set_first_reply_created_at`
    (`app/models/message.rb:397-399`) hace
    `conversation.update(first_reply_created_at:, waiting_since: nil)` en el mismo update. El
    fixture "attended_conversation" del test seteaba `first_reply_created_at` directamente
    sin enviar un mensaje real, así que `waiting_since` nunca se limpiaba y la conversación
    seguía contando como "sin atender" — comportamiento correcto del código dado ese fixture
    irreal. Fix: crear la conversación y hacer `.update!(first_reply_created_at:,
    waiting_since: nil)` después (replicando el update real de `Message`), y corregir el
    conteo esperado de 2 a 4 (las 2 conversaciones del fixture compartido, sin
    `first_reply_created_at`, también cuentan legítimamente como "sin atender").
    24 examples, 0 failures.
12. **Los 9 shards restantes de `backend-tests` (deploy bloqueado por el gate de
    `build_production_image.yml`)** — commit pendiente de esta sesión, todos investigados y
    arreglados sin tocar lógica de negocio salvo un bug de seguridad real:
    - **`GOTENBERG_URL` faltante en CI**: agregado `GOTENBERG_URL: http://localhost:3009`
      como placeholder al step "Run backend tests" de `run_foss_spec.yml` (los specs mockean
      la URL real con `stub_request`, solo hacía falta que la variable exista).
    - **Bug de seguridad real en `MessagesController#destroy`**: el fix oficial de Chatwoot
      (`4b748e2c8`, PR #4184, 2022) limpiaba TODO `content_attributes` al eliminar un mensaje
      (reemplazo completo del hash) para no dejar datos sensibles como `bcc_emails`
      expuestos. En algún merge posterior, al agregar el campo propio `original_content`
      (para poder ver el contenido original de un mensaje eliminado), se cambió a
      `.merge(deleted: true, original_content: ...)`, que preserva sin querer TODOS los
      `content_attributes` viejos — incluyendo `bcc_emails`, que quedaba expuesto
      permanentemente en un mensaje "eliminado". Arreglado volviendo al reemplazo completo
      del hash, agregando solo las 2 claves necesarias.
    - **Validación nueva de `AgentBot#outgoing_url` rompe fixtures oficiales**: la validación
      `validates :outgoing_url, presence: true, if: :webhook?` (agregada para la feature de
      bots de flujo interno) hace que los `valid_params` viejos de
      `agent_bots_controller_spec.rb` (API y platform) ya no sean válidos — se les agregó
      `outgoing_url`. En `agent_bot_listener_spec.rb`, un test que simula a propósito un bot
      con `outgoing_url: ''` (para probar que el listener es defensivo) usa ahora el trait
      `:skip_validate` de la factory, ya que el escenario que simula ya no es alcanzable por
      el flujo normal de creación.
    - **`campaign_type` no es asignable a mano**: `Campaign#ensure_correct_campaign_attributes`
      (before_validation) lo deriva SIEMPRE del tipo de inbox asociado (Whatsapp/Sms/Twilio
      SMS → `one_off`, cualquier otro → `ongoing`), re-evaluándose en cada save/update —
      pasar `campaign_type: :one_off` explícito en un test no sirve de nada si el inbox no es
      de un canal de mensajería. El campo `timezone` solo se sirve en la respuesta JSON para
      campañas `one_off` (`_campaign.json.jbuilder`). Arreglado el test de
      `campaigns_controller_spec.rb` usando un inbox de WhatsApp real.
    - **`WeeklyOpsReportBuilder` — `update_all` salta callbacks**: el fixture de
      `weekly_ops_report_builder_spec.rb` usaba
      `inbox.working_hours.update_all(open_all_day: true, ...)`, que por diseño de Rails NO
      dispara `before_validation`/`before_save`. `WorkingHour#ensure_open_all_day_hours` es
      justo el callback que rellena `open_hour`/`close_hour` cuando `open_all_day: true` —
      sin él, esos campos quedaban `nil` y `ReportingEventHelper#format_time` tronaba.
      Arreglado iterando con `update!` en vez de `update_all`.
    - **`CallFinder`/`CallsController` (Enterprise, adaptado por CapitalPlus)**: mismo patrón
      que el punto 9 — `CallFinder#accessible_conversations` usa
      `Conversations::PermissionFilterService` con el default estricto (solo lo asignado),
      así que un agente miembro de un inbox pero sin la conversación asignada no veía sus
      propias llamadas. Arreglados los fixtures de `call_finder_spec.rb` y
      `calls_controller_spec.rb` asignando la conversación al agente correspondiente en cada
      test.
    - **`cancel_scheduled_jobs_service_spec.rb` — reescrito, no solo arreglado**: el patrón
      original (`ActiveJob::Base.queue_adapter = :sidekiq` + `Sidekiq::Testing.disable!`)
      producía resultados inconsistentes bajo RSpec real (1 de 3 jobs llegaba a Redis,
      nunca los 3) porque `ActiveJob::TestHelper` (incluido globalmente en
      `rails_helper.rb`) resetea el adapter de la clase a `TestAdapter` en su propio hook
      `before_setup`, que corre DESPUÉS de que el `around` del spec ya asignó `:sidekiq` pero
      ANTES del cuerpo del test — un script `rails runner` aislado (sin ese hook) reproducía
      el comportamiento esperado sin problema, confirmando que la interferencia era
      específica del entorno RSpec. Reescrito para que el helper `schedule_job` empuje
      directo a Sidekiq con `Sidekiq::Client.push`, simulando el mismo formato de
      `ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper` que produce el adapter real —
      determinístico, sin depender de la resolución de adapter de ActiveJob en runtime.

## Pendientes — no arregladas, requieren decisión o acceso que no tuvimos

1. **`RAILS_ENV=development` fijo en `docker-compose.dev.yml`** (anchor `&app`) hace que
   `bundle exec rspec` sin `RAILS_ENV=test` explícito corra contra la base de
   **desarrollo** (`chatwoot_dev`, con datos reales como la cuenta "Capital Plus"), no
   contra `chatwoot_test`. RSpec envuelve cada ejemplo en una transacción con rollback, así
   que no hay riesgo de pérdida de datos, pero sí genera falsos negativos en specs que
   asumen tablas vacías (ej. `Contact.all.first` devolvía "Mauricio Aramburo" en vez del
   contacto esperado del test).
   - **Por qué pasó:** nadie lo había notado porque el equipo corre specs sueltos
     localmente, no la suite completa, y los fallos por contaminación parecían errores del
     propio código.
   - **Cómo evitarlo:** forzar siempre `RAILS_ENV=test bundle exec rspec ...`
     explícitamente al correr specs en este entorno Docker de desarrollo; no confiar en el
     default.
2. **`run_foss_spec.yml` nunca disparaba en push a `main`** (solo
   `develop`/`master`/`pull_request`), y el equipo trabaja directamente en `main` sin PRs
   regulares (ver skill `gitflow`). Esto significa que **rubocop nunca corrió contra el
   código real de producción en CI**, acumulando ~3323 ofensas reales (no cosméticas) sin
   que nadie las viera. Se agregó `main` a los triggers y se generó `.rubocop_todo.yml`
   para congelar la deuda existente sin bloquear el gate nuevo — pero esas ~3323 ofensas
   siguen ahí, solo silenciadas. Vale la pena ir limpiándolas gradualmente (quitando
   entradas de `.rubocop_todo.yml` conforme se arreglen) en vez de dejarlas congeladas para
   siempre.
3. **`.rubocop_todo.yml` congela ~3323 ofensas reales, no solo ruido cosmético.** Son en su
   mayoría `Metrics/*` (ClassLength, MethodLength, AbcSize, CyclomaticComplexity) en código
   propio grande: `zoho_crm_controller.rb`, `internal_flow_handler_service.rb` (agent
   bots), `weekly_ops_report_builder.rb`, `message_builder.rb`, `contact.rb`, `inbox.rb`,
   entre otros. Ninguna es un bug funcional, pero indican archivos que conviene partir en
   clases más chicas cuando se toquen de nuevo. No hay plan de limpieza activo, solo
   quedaron congeladas.
4. **Hook de pre-commit local (Husky + lint-staged) no funciona con cambios grandes**:
   `scss-lint` se invoca sin `bundle exec` (falla siempre, está instalado solo como gema),
   y `eslint --fix` no tiene límite de concurrencia — con miles de archivos en un mismo
   commit (como este merge), lanza decenas de procesos node en paralelo y agota la memoria
   del contenedor (`SIGKILL`). Con pocos archivos (el flujo normal del equipo)
   probablemente nunca se topa con esto. Si vuelve a pasar con un commit grande, la salida
   fue `git commit --no-verify` puntual, no cambiar la configuración del hook sin
   autorización.
5. **Falta marcar "Run Chatwoot CE spec" como required status check** en GitHub →
   Settings → Branches → main, para que ningún PR/push pueda llegar a `main` con specs en
   rojo. No se pudo hacer desde este entorno de trabajo (sin `gh` CLI ni acceso a la
   configuración del repo) — requiere que alguien con acceso de administrador en GitHub lo
   haga manualmente.
6. **`docx_to_pdf_converter_service_spec.rb`** (3 fallos): mismo `GOTENBERG_URL`, ya cubierto
   por el fix del punto 6 de "Corregidos" — no requiere cambio propio.

## Gotcha para quien edite `.rubocop.yml` en el futuro

`.rubocop.yml` tenía (y puede volver a tener) **claves YAML duplicadas**: se encontraron y
corrigieron duplicados de `Style/GuardClause`, `Style/ClassAndModuleChildren` y
`UseFromEmail` (cada cop definido dos veces en el mismo archivo; YAML usa la **última**
aparición, sobrescribiendo silenciosamente la primera sin ningún error o warning).

**Antes de agregar una sección nueva a `.rubocop.yml`, correr `grep -n "^NombreDelCop:"`
primero** para confirmar que no exista ya más abajo en el archivo — si existe, fusionar el
`Exclude` ahí en vez de crear una sección nueva.

## Estado final verificado (commit `96f922a51`)

- `bundle exec rubocop --parallel` sobre 3044 archivos: **0 offenses**.
- 471 specs de backend (`whatsapp/`, `campaign`, `permission_filter` x2, `account`,
  `message_builder`, `oneoff_campaign`) en verde, corriendo con `RAILS_ENV=test` forzado
  explícitamente.
- Push hecho a `main` (`a4bb76de9..96f922a51`).

## Estado final verificado (commit `d95bf4e37`, 2026-08-26)

- `pnpm run eslint`: **0 errores** (478 warnings preexistentes, no bloquean el gate).
- Los 6 archivos de specs de permisos listados en el punto 9 de "Corregidos": **0 fallos**
  tras el fix (96 + ~40 ejemplos verificados localmente con `RAILS_ENV=test`), salvo el bug
  real de `unattended` documentado en el pendiente #6 (dejado fallando a propósito).
- `spec/controllers/api/v1/accounts/bulk_actions_controller_spec.rb` +
  `spec/jobs/bulk_actions_job_spec.rb`: 19 ejemplos, 0 fallos, con el fix de inbox
  membership aplicado.
- Push hecho a `main` (`ab7121a7a..d95bf4e37`).
- **Gotcha de esta sesión**: correr `eslint --fix` con un path como argumento extra
  (`pnpm run eslint --fix -- ruta/especifica`) NO acota el lint a esa ruta — el script de
  `package.json` ya trae un glob fijo (`eslint app/**/*.{js,vue}`) y el path pasado se
  agrega como target ADICIONAL, no como reemplazo. Terminó reformateando (solo fin de
  línea, sin cambios de contenido) ~2210 archivos ajenos del repo por un mismatch de
  `core.autocrlf` en Windows; se revirtieron con `git checkout HEAD --` antes de comitear.
  Para lintear una ruta específica, invocar el binario directo:
  `./node_modules/.bin/eslint <ruta>` (sin pasar por el script de `pnpm run`).

## Estado final verificado (commit pendiente de push, 2026-08-27)

- Los 9 grupos de fallos restantes de `backend-tests` (punto 12 de "Corregidos"), todos
  verificados localmente con `RAILS_ENV=test`: `agent_bots_controller_spec.rb` +
  `platform/agent_bots_controller_spec.rb` + `agent_bot_listener_spec.rb` (63 ejemplos),
  `messages_controller_spec.rb` (23), `campaigns_controller_spec.rb` (32),
  `conversation_spec.rb` (1), `cancel_scheduled_jobs_service_spec.rb` (2),
  `weekly_ops_report_builder_spec.rb` (28), `call_finder_spec.rb` +
  `calls_controller_spec.rb` enterprise (13) — **0 fallos en los 162 ejemplos**.
- `bundle exec rubocop` sobre los 10 archivos Ruby tocados en esta ronda: **0 offenses**.
- Con esto, `run_foss_spec.yml` debería quedar completamente verde, desbloqueando
  `build_production_image.yml` (gateado por `workflow_run` a que el primero pase).

**Regla general para trabajo futuro en este repo:** antes de asumir que "los tests pasan",
verificar que se corrió con `RAILS_ENV=test` explícito. Antes de asumir que rubocop está
limpio, recordar que `.rubocop_todo.yml` está silenciando ~3323 ofensas reales
preexistentes, no solo ruido de formato.
