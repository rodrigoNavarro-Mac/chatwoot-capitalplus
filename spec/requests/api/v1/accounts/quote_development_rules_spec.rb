require 'rails_helper'

RSpec.describe 'Quote Development Rules API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/{account.id}/quote_development_rules' do
    it 'returns unauthorized for agents' do
      get "/api/v1/accounts/#{account.id}/quote_development_rules", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists rules with their tiers for administrators' do
      create(:quote_development_rule, account: account, desarrollo: 'Fuego', quote_development_rule_tiers_attributes: [
               { hasta_meses: 12, msi: true, requires_authorization: false },
               { hasta_meses: nil, msi: false, requires_authorization: true }
             ])

      get "/api/v1/accounts/#{account.id}/quote_development_rules", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body.first[:desarrollo]).to eq('Fuego')
      expect(body.first[:quote_development_rule_tiers].pluck(:hasta_meses)).to eq([12, nil])
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/quote_development_rules' do
    let(:params) do
      {
        desarrollo: 'Fuego',
        quote_development_rule_tiers_attributes: [
          { hasta_meses: 12, msi: true, requires_authorization: false },
          { hasta_meses: 24, msi: true, requires_authorization: true },
          { hasta_meses: nil, msi: false, requires_authorization: true }
        ]
      }
    end

    it 'creates a rule with multiple tiers' do
      post "/api/v1/accounts/#{account.id}/quote_development_rules",
           params: params, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      rule = account.quote_development_rules.find_by(desarrollo: 'Fuego')
      expect(rule.quote_development_rule_tiers.count).to eq(3)
      expect(rule.tier_for(6)).to have_attributes(hasta_meses: 12, msi?: true, requires_authorization?: false)
      expect(rule.tier_for(18)).to have_attributes(hasta_meses: 24, msi?: true, requires_authorization?: true)
      expect(rule.tier_for(30)).to have_attributes(hasta_meses: nil, msi?: false, requires_authorization?: true)
    end

    it 'rejects two open-ended tiers with a 422 (not a 500)' do
      params[:quote_development_rule_tiers_attributes] << { hasta_meses: nil, msi: false, requires_authorization: false }

      post "/api/v1/accounts/#{account.id}/quote_development_rules",
           params: params, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns unauthorized for agents' do
      post "/api/v1/accounts/#{account.id}/quote_development_rules",
           params: params, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/quote_development_rules/{id}' do
    it 'removes a tier via _destroy and adds a new one' do
      rule = create(:quote_development_rule, account: account, desarrollo: 'Fuego', quote_development_rule_tiers_attributes: [
                      { hasta_meses: 12, msi: true, requires_authorization: false },
                      { hasta_meses: nil, msi: false, requires_authorization: true }
                    ])
      keep = rule.quote_development_rule_tiers.find_by(hasta_meses: 12)
      remove = rule.quote_development_rule_tiers.find_by(hasta_meses: nil)

      patch "/api/v1/accounts/#{account.id}/quote_development_rules/#{rule.id}",
            params: {
              quote_development_rule_tiers_attributes: [
                { id: remove.id, _destroy: true },
                { hasta_meses: nil, msi: false, requires_authorization: true }
              ]
            },
            headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      rule.reload
      expect(rule.quote_development_rule_tiers.pluck(:id)).to include(keep.id)
      expect(rule.quote_development_rule_tiers.pluck(:id)).not_to include(remove.id)
      expect(rule.quote_development_rule_tiers.count).to eq(2)
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/quote_development_rules/{id}' do
    it 'destroys the rule and its tiers' do
      rule = create(:quote_development_rule, account: account, desarrollo: 'Fuego')
      tier = rule.quote_development_rule_tiers.first

      delete "/api/v1/accounts/#{account.id}/quote_development_rules/#{rule.id}",
             headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      expect(QuoteDevelopmentRule.exists?(rule.id)).to be false
      expect(QuoteDevelopmentRuleTier.exists?(tier.id)).to be false
    end
  end
end
