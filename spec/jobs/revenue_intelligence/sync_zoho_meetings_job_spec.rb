require 'rails_helper'

describe RevenueIntelligence::SyncZohoMeetingsJob do
  let(:account) { create(:account) }
  let(:sample_event) do
    { 'id' => 'event-1', 'Owner' => { 'id' => 'owner-1', 'name' => 'Ana Setter' },
      'Start_DateTime' => '2026-02-01T10:00:00-06:00', 'End_DateTime' => '2026-02-01T10:30:00-06:00',
      'Resultado' => 'No Show', 'Event_Title' => 'Videollamada con lead' }
  end

  before do
    account.enable_features!('crm_integration')
    allow_any_instance_of(Crm::Zoho::TokenRefreshService).to receive(:token).and_return('fake-token') # rubocop:disable RSpec/AnyInstance
    create(:integrations_hook, :zoho_crm, account: account, status: 'enabled')

    stub_request(:get, %r{zohoapis\.com/crm/v7/Deals/[\w-]+/Events}).to_return(status: 204, body: '')
    stub_request(:get, %r{zohoapis\.com/crm/v7/Leads/[\w-]+/Events}).to_return(status: 204, body: '')
  end

  def stub_events(module_name, zoho_id, events)
    stub_request(:get, %r{zohoapis\.com/crm/v7/#{module_name}/#{zoho_id}/Events})
      .to_return(status: 200, body: { data: events }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#perform' do
    it 'creates a verified revenue_appointment from a real Zoho Event linked to a deal' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1')
      stub_events('Deals', 'deal-1', [sample_event])

      described_class.new.perform

      appointment = account.revenue_appointments.find_by(zoho_event_id: 'event-1')
      expect(appointment).to be_present
      expect(appointment.verified).to be(true)
      expect(appointment.status).to eq('No Show')
      expect(appointment.subject).to eq('Videollamada con lead')
      expect(appointment.zoho_deal_id).to eq('deal-1')
      expect(appointment.revenue_deal_id).to eq(deal.id)
    end

    it 'is idempotent — running it twice does not duplicate the appointment' do
      account.revenue_deals.create!(zoho_deal_id: 'deal-1')
      stub_events('Deals', 'deal-1', [sample_event])

      described_class.new.perform
      described_class.new.perform

      expect(account.revenue_appointments.where(zoho_event_id: 'event-1').count).to eq(1)
    end

    it 'does not create any appointment when a deal has no Zoho Events (no fake evidence)' do
      account.revenue_deals.create!(zoho_deal_id: 'deal-1')

      expect { described_class.new.perform }.not_to change(RevenueAppointment, :count)
    end

    it 'preserves zoho_deal_id when the same event is later re-discovered via its Lead' do
      deal = account.revenue_deals.create!(zoho_deal_id: 'deal-1')
      lead = account.revenue_leads.create!(zoho_lead_id: 'lead-1')
      deal.update!(revenue_lead_id: lead.id)
      stub_events('Deals', 'deal-1', [sample_event])
      stub_events('Leads', 'lead-1', [sample_event])

      described_class.new.perform

      appointment = account.revenue_appointments.find_by(zoho_event_id: 'event-1')
      expect(appointment.zoho_deal_id).to eq('deal-1')
      expect(appointment.zoho_lead_id).to eq('lead-1')
      expect(appointment.revenue_deal_id).to eq(deal.id)
    end

    it 'continues syncing when one deal/lead lookup raises' do
      account.revenue_deals.create!(zoho_deal_id: 'deal-broken')
      account.revenue_deals.create!(zoho_deal_id: 'deal-ok')
      stub_request(:get, %r{zohoapis\.com/crm/v7/Deals/deal-broken/Events}).to_return(status: 500, body: 'boom')
      stub_events('Deals', 'deal-ok', [sample_event])

      expect { described_class.new.perform }.not_to raise_error
      expect(RevenueAppointment.where(zoho_event_id: 'event-1')).to exist
    end
  end
end
