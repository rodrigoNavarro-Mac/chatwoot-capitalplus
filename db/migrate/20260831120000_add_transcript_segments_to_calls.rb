class AddTranscriptSegmentsToCalls < ActiveRecord::Migration[7.1]
  def change
    # Diarización cruda de Aircall AI: [{speaker, role_hint, start_seconds, end_seconds, text}].
    # Se guarda junto a `transcript`/`recording` porque es dato crudo del proveedor, no derivado.
    add_column :calls, :transcript_segments, :jsonb
  end
end
