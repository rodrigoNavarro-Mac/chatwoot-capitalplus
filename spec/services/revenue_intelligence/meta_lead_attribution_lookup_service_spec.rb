require 'rails_helper'

describe RevenueIntelligence::MetaLeadAttributionLookupService do
  let(:client) { instance_double(Koala::Facebook::API) }
  let(:service) { described_class.new(client: client) }
  let(:social_lead_id) { '4582893005295147' }
  let(:created_at_source) { Time.zone.parse('2026-10-15 10:00:00') }

  def full_response(overrides = {})
    { 'id' => social_lead_id, 'created_time' => '2026-10-15T09:58:00+0000', 'ad_id' => 'ad-1', 'adset_id' => 'adset-1',
      'campaign_id' => 'campaign-1', 'form_id' => 'form-1' }.merge(overrides)
  end

  before do
    allow(client).to receive(:get_object).and_return(full_response)
  end

  it 'requests only the authorized fields, never field_data nor anything related to contact info' do
    service.call(social_lead_id: social_lead_id, created_at_source: created_at_source)

    expect(client).to have_received(:get_object).with(
      social_lead_id, { fields: 'id,ad_id,adset_id,campaign_id,form_id,created_time' }, { api_version: 'v25.0' }
    )
  end

  context 'when Meta reconoce el id, coincide, y trae los 4 identificadores con fecha consistente' do
    it 'clasifica como confirmada' do
      result = service.call(social_lead_id: social_lead_id, created_at_source: created_at_source)

      expect(result).to include(
        verification_status: 'confirmada', meta_ad_id: 'ad-1', meta_adset_id: 'adset-1',
        meta_campaign_id: 'campaign-1', meta_form_id: 'form-1'
      )
      expect(result[:fetched_at]).to be_present
    end
  end

  context 'when el id devuelto por Meta NO coincide con el social_lead_id consultado' do
    it 'clasifica como no_correspondiente, sin importar que otros campos vengan presentes' do
      allow(client).to receive(:get_object).and_return(full_response('id' => 'otro-id-distinto'))

      result = service.call(social_lead_id: social_lead_id, created_at_source: created_at_source)

      expect(result[:verification_status]).to eq('no_correspondiente')
    end
  end

  context 'when el id coincide pero falta algún identificador' do
    it 'clasifica como parcialmente_verificable si falta ad_id' do
      allow(client).to receive(:get_object).and_return(full_response('ad_id' => nil))

      result = service.call(social_lead_id: social_lead_id, created_at_source: created_at_source)

      expect(result[:verification_status]).to eq('parcialmente_verificable')
    end

    it 'clasifica como parcialmente_verificable si la fecha difiere más de la tolerancia (2 días)' do
      allow(client).to receive(:get_object).and_return(full_response('created_time' => '2026-10-01T00:00:00+0000'))

      result = service.call(social_lead_id: social_lead_id, created_at_source: created_at_source)

      expect(result[:verification_status]).to eq('parcialmente_verificable')
    end

    it 'tolera hasta 2 días de diferencia de fecha como consistente' do
      allow(client).to receive(:get_object).and_return(full_response('created_time' => '2026-10-13T10:00:00+0000'))

      result = service.call(social_lead_id: social_lead_id, created_at_source: created_at_source)

      expect(result[:verification_status]).to eq('confirmada')
    end
  end

  # Fase 18/20: un error de permisos NUNCA se reclasifica como "identificador incorrecto".
  context 'when Meta responde con el error ambiguo 100/33 (permiso insuficiente u objeto no disponible)' do
    before do
      error = Koala::Facebook::ClientError.new(
        400, '',
        { 'type' => 'GraphMethodException', 'code' => 100, 'error_subcode' => 33,
          'message' => "Unsupported get request. Object with ID '#{social_lead_id}' does not exist." }
      )
      allow(client).to receive(:get_object).and_raise(error)
    end

    it 'clasifica como no_verificable_permisos_o_ausencia, nunca como no_correspondiente' do
      result = service.call(social_lead_id: social_lead_id, created_at_source: created_at_source)

      expect(result[:verification_status]).to eq('no_verificable_permisos_o_ausencia')
      expect(result[:verification_status]).not_to eq('no_correspondiente')
      expect(result[:fetch_error_code]).to eq(100)
      expect(result[:fetch_error_subcode]).to eq(33)
    end

    it 'no deja ningún identificador parcialmente poblado en un error' do
      result = service.call(social_lead_id: social_lead_id, created_at_source: created_at_source)

      expect(result.values_at(:meta_ad_id, :meta_adset_id, :meta_campaign_id, :meta_form_id)).to all(be_nil)
    end
  end

  context 'when Meta responde con un error distinto, no relacionado a permisos (p. ej. parámetro inválido real)' do
    it 'clasifica como no_verificable_otro_error (reintentable, no un bloqueo de permisos)' do
      error = Koala::Facebook::ClientError.new(500, '', { 'type' => 'OtherException', 'code' => 2, 'message' => 'Temporary server error' })
      allow(client).to receive(:get_object).and_raise(error)

      result = service.call(social_lead_id: social_lead_id, created_at_source: created_at_source)

      expect(result[:verification_status]).to eq('no_verificable_otro_error')
    end
  end
end
