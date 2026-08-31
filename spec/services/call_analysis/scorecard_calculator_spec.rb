require 'rails_helper'

describe CallAnalysis::ScorecardCalculator do
  def uniform_scores(role, value)
    CallAnalysis::ScorecardConfig.stage_keys(role).index_with { value }
  end

  it 'reads as solido at or above the configured threshold' do
    result = described_class.new(role: 'setter', stage_scores: uniform_scores('setter', 80)).calculate

    expect(result[:total_score]).to eq(80.0)
    expect(result[:reading]).to eq('solido')
  end

  it 'reads as coaching between the two thresholds' do
    result = described_class.new(role: 'setter', stage_scores: uniform_scores('setter', 70)).calculate

    expect(result[:total_score]).to eq(70.0)
    expect(result[:reading]).to eq('coaching')
  end

  it 'reads as critico below the lower threshold' do
    result = described_class.new(role: 'setter', stage_scores: uniform_scores('setter', 50)).calculate

    expect(result[:total_score]).to eq(50.0)
    expect(result[:reading]).to eq('critico')
  end

  it 'treats a missing stage score as zero instead of raising' do
    result = described_class.new(role: 'setter', stage_scores: { abre: 100 }).calculate

    expect(result[:total_score]).to be < 100
  end

  it 'works for the asesor role with its own stage keys' do
    result = described_class.new(role: 'asesor', stage_scores: uniform_scores('asesor', 90)).calculate

    expect(result[:total_score]).to eq(90.0)
    expect(result[:reading]).to eq('solido')
  end
end
