require 'rails_helper'

describe RevenueIntelligence::StageHistoryBuilder do
  # Payload real (anonimizado en los ids) confirmado contra la cuenta de Zoho de Fuego: 3 filas de
  # Stage_History de un deal que fue Cotizado con visita -> Apartado -> Cerrado ganado.
  let(:rows) do
    [
      { 'id' => 'hist-3', 'Stage' => 'Cerrado ganado', 'Moved_To__s' => nil,
        'Stage_Duration_Calendar_Days' => nil, 'Modified_Time' => '2025-12-16T11:35:11-06:00' },
      { 'id' => 'hist-1', 'Stage' => 'Cotizado con visita', 'Moved_To__s' => 'Apartado',
        'Stage_Duration_Calendar_Days' => 6, 'Modified_Time' => '2025-12-02T11:52:59-06:00' },
      { 'id' => 'hist-2', 'Stage' => 'Apartado', 'Moved_To__s' => 'Cerrado ganado',
        'Stage_Duration_Calendar_Days' => 8, 'Modified_Time' => '2025-12-08T17:08:39-06:00' }
    ]
  end
  let(:fallback_entered_at) { Time.zone.parse('2025-11-20T00:00:00-06:00') }

  describe '.build' do
    it 'sorts rows chronologically by Modified_Time regardless of input order' do
      built = described_class.build(rows, fallback_entered_at: fallback_entered_at)

      expect(built.map { |r| r[:zoho_history_id] }).to eq(%w[hist-1 hist-2 hist-3])
    end

    it 'uses the fallback entered_at for the first row' do
      built = described_class.build(rows, fallback_entered_at: fallback_entered_at)

      expect(built.first[:entered_at]).to eq(fallback_entered_at)
      expect(built.first[:previous_stage]).to be_nil
    end

    it "derives each subsequent row's entered_at from the previous row's Modified_Time" do
      built = described_class.build(rows, fallback_entered_at: fallback_entered_at)

      expect(built[1][:entered_at]).to eq(Time.zone.parse('2025-12-02T11:52:59-06:00'))
      expect(built[1][:previous_stage]).to eq('Cotizado con visita')
      expect(built[2][:entered_at]).to eq(Time.zone.parse('2025-12-08T17:08:39-06:00'))
      expect(built[2][:previous_stage]).to eq('Apartado')
    end

    it 'takes duration_seconds directly from Stage_Duration_Calendar_Days instead of recomputing it' do
      built = described_class.build(rows, fallback_entered_at: fallback_entered_at)

      expect(built[0][:duration_seconds]).to eq(6 * 86_400)
      expect(built[1][:duration_seconds]).to eq(8 * 86_400)
    end

    it 'leaves exited_at and duration_seconds nil for the current (still open) stage' do
      built = described_class.build(rows, fallback_entered_at: fallback_entered_at)

      current = built.last
      expect(current[:stage]).to eq('Cerrado ganado')
      expect(current[:exited_at]).to be_nil
      expect(current[:duration_seconds]).to be_nil
    end

    it 'preserves the raw row in raw_payload' do
      built = described_class.build(rows, fallback_entered_at: fallback_entered_at)

      expect(built.first[:raw_payload]).to eq(rows.find { |r| r['id'] == 'hist-1' })
    end

    it 'returns an empty array for an empty rows list' do
      expect(described_class.build([], fallback_entered_at: fallback_entered_at)).to eq([])
    end
  end
end
