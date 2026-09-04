# Bookkeeping de "hasta qué momento ya sincronicé" por cuenta y tipo de sync (uno de
# RevenueSyncCursor::SYNC_TYPES). El cursor solo avanza cuando el job llama a #advance! —
# una corrida fallida a medias no pierde el hueco sin sincronizar, la siguiente corrida recubre
# desde el último punto exitoso.
class RevenueIntelligence::SyncCursorService
  def initialize(account, sync_type)
    @account = account
    @sync_type = sync_type
  end

  def since
    cursor.last_synced_at
  end

  def advance!(until_at)
    cursor.update!(last_synced_at: until_at, last_run_status: 'ok', last_error: nil)
  end

  def record_error!(message)
    cursor.update!(last_run_status: 'failed', last_error: message)
  end

  private

  attr_reader :account, :sync_type

  def cursor
    @cursor ||= account.revenue_sync_cursors.find_or_create_by!(sync_type: sync_type)
  end
end
