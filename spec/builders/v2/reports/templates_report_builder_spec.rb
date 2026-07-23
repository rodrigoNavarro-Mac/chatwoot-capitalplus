require 'rails_helper'

RSpec.describe V2::Reports::TemplatesReportBuilder do
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:contact) { create(:contact, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  def send_template(template_name, status: 'sent', at: Time.current, conv: conversation)
    create(:message, account: account, inbox: conv.inbox, conversation: conv,
                      message_type: :outgoing, status: status, created_at: at,
                      additional_attributes: { template_params: { name: template_name } })
  end

  def receive_reply(at:, conv: conversation)
    create(:message, account: account, inbox: conv.inbox, conversation: conv,
                      message_type: :incoming, created_at: at)
  end

  let(:params) { {} }
  let(:builder) { described_class.new(account: account, params: params) }

  describe '#build' do
    subject(:report) { builder.build }

    it 'returns an empty array when no template was ever sent' do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)

      expect(report).to eq([])
    end

    it 'aggregates sent/delivered/read/failed by template name' do
      send_template('bienvenida', status: 'sent')
      send_template('bienvenida', status: 'delivered')
      send_template('bienvenida', status: 'read')
      send_template('bienvenida', status: 'failed')

      row = report.find { |r| r[:template_name] == 'bienvenida' }
      expect(row[:sent]).to eq(4)
      expect(row[:delivered]).to eq(2) # delivered + read
      expect(row[:read]).to eq(1)
      expect(row[:failed]).to eq(1)
    end

    it 'keeps different templates as separate rows' do
      send_template('bienvenida')
      send_template('seguimiento_1')

      expect(report.map { |r| r[:template_name] }).to contain_exactly('bienvenida', 'seguimiento_1')
    end

    it 'marks a template send as responded when the lead replies afterwards' do
      send_template('bienvenida', at: 2.hours.ago)
      receive_reply(at: 1.hour.ago)

      row = report.find { |r| r[:template_name] == 'bienvenida' }
      expect(row[:responded]).to eq(1)
      expect(row[:response_rate]).to eq(100.0)
    end

    it 'does not mark a template send as responded when there is no reply' do
      send_template('bienvenida', at: 2.hours.ago)

      row = report.find { |r| r[:template_name] == 'bienvenida' }
      expect(row[:responded]).to eq(0)
      expect(row[:response_rate]).to eq(0.0)
    end

    it 'does not attribute a reply to an earlier template once a newer one was sent in between' do
      send_template('bienvenida', at: 3.hours.ago)
      send_template('seguimiento_1', at: 2.hours.ago)
      receive_reply(at: 1.hour.ago)

      bienvenida = report.find { |r| r[:template_name] == 'bienvenida' }
      seguimiento = report.find { |r| r[:template_name] == 'seguimiento_1' }

      expect(bienvenida[:responded]).to eq(0)
      expect(seguimiento[:responded]).to eq(1)
    end

    it 'does not count messages from another account' do
      other_account = create(:account)
      other_inbox = create(:inbox, account: other_account)
      other_conversation = create(:conversation, account: other_account, inbox: other_inbox)
      create(:message, account: other_account, inbox: other_inbox, conversation: other_conversation,
                        message_type: :outgoing,
                        additional_attributes: { template_params: { name: 'bienvenida' } })

      expect(report).to eq([])
    end

    context 'when filtering by date range' do
      let(:params) do
        { since: 2.days.ago.beginning_of_day.to_i.to_s, until: Time.current.end_of_day.to_i.to_s }
      end

      it 'only counts template sends within the range' do
        send_template('bienvenida', at: 1.day.ago)
        send_template('bienvenida', at: 2.weeks.ago)

        row = report.find { |r| r[:template_name] == 'bienvenida' }
        expect(row[:sent]).to eq(1)
      end
    end
  end

  describe '#timeseries' do
    subject(:series) { builder.timeseries }

    it 'groups sends by day and template name' do
      send_template('bienvenida', at: 2.days.ago.noon)
      send_template('bienvenida', at: 2.days.ago.noon)
      send_template('bienvenida', at: 1.day.ago.noon)

      day_2 = series.find { |row| row[:period] == 2.days.ago.to_date.to_s }
      day_1 = series.find { |row| row[:period] == 1.day.ago.to_date.to_s }

      expect(day_2[:sent]).to eq(2)
      expect(day_1[:sent]).to eq(1)
    end
  end
end
