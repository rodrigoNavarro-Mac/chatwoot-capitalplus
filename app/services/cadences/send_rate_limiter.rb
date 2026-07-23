# Evita que el motor de cadencias dispare varias plantillas de WhatsApp al mismo tiempo para
# un mismo inbox (ej. al correr "Enroll past leads" con muchos leads viejos cuyo next_action_at
# ya paso, todos sus AdvanceJob caen en la misma ventana de segundos). Meta aplica rate limiting
# por numero de telefono, y una rafaga sin espaciar termina en send_failed para la mayoria.
class Cadences::SendRateLimiter
  MIN_INTERVAL_SECONDS = 2

  pattr_initialize [:inbox!]

  # Reclama el turno de envio para este inbox. true si nadie mas envio en la ventana actual
  # (ya puede proceder a llamar a la API de WhatsApp); false si hay que esperar y reintentar.
  def claim_slot!
    Redis::Alfred.set(lock_key, Time.current.to_f.to_s, nx: true, ex: MIN_INTERVAL_SECONDS)
  end

  private

  def lock_key
    format(Redis::RedisKeys::CADENCE_SEND_RATE_LIMIT_KEY, inbox_id: inbox.id)
  end
end
