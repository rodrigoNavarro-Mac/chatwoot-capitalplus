require 'rails_helper'

describe Crm::Aircall::RecordingAttachmentService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:call) { create(:call, account: account, conversation: conversation, provider: :aircall) }

  # URL real de S3 pre-firmada tal como la manda Aircall en el call object — ya trae su propia
  # autenticación en la query string (X-Amz-*), a diferencia de la de Twilio.
  let(:recording_url) { 'https://production-fra-example.s3.eu-central-1.amazonaws.com/recording.mp3?X-Amz-Signature=abc123' }

  it 'downloads and attaches the recording WITHOUT sending any Authorization header' do
    stub = stub_request(:get, recording_url)
           .with { |request| request.headers['Authorization'].nil? }
           .to_return(status: 200, body: 'FAKE_AUDIO_BYTES', headers: { 'Content-Type' => 'audio/mpeg' })

    described_class.new(call: call, recording_url: recording_url).perform

    expect(stub).to have_been_requested
    expect(call.reload.recording).to be_attached
  end

  it 'does nothing when recording_url is blank' do
    described_class.new(call: call, recording_url: nil).perform

    expect(call.reload.recording).not_to be_attached
  end

  it 'does nothing when a recording is already attached' do
    call.recording.attach(io: StringIO.new('existing'), filename: 'existing.wav', content_type: 'audio/wav')

    expect(Net::HTTP).not_to receive(:start)

    described_class.new(call: call, recording_url: recording_url).perform
  end
end
