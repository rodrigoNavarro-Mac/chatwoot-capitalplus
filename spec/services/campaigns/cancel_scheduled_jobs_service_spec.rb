require 'rails_helper'

RSpec.describe Campaigns::CancelScheduledJobsService do
  let(:account) { create(:account) }
  let(:campaign) { create(:campaign, account: account) }
  let(:other_campaign) { create(:campaign, account: account) }

  # Sidekiq::Testing.disable! hace que Sidekiq::Client.push realmente toque Redis en vez de
  # acumularse en el array fake — necesario para que Sidekiq::ScheduledSet refleje los jobs.
  #
  # No usamos Campaigns::SendCampaignContactJob.set(wait_until:).perform_later aqui: bajo RSpec,
  # ActiveJob::TestHelper (incluido globalmente en rails_helper.rb) resetea el adapter de la
  # clase a TestAdapter en su propio hook before_setup, que corre DESPUES de que este around
  # ya asigno :sidekiq pero ANTES del cuerpo del test — dejando el resultado inconsistente
  # (algunos jobs llegan a Redis, otros no, dependiendo de orden de ejecucion). En vez de
  # depender de esa resolucion de adapter, empujamos directo a Sidekiq simulando el mismo
  # formato de JobWrapper que produce ActiveJob con el adapter real (ver Sidekiq::JobRecord
  # #display_class/#display_args en la gema sidekiq, que es justo lo que este servicio usa).
  around { |example| Sidekiq::Testing.disable!(&example) }

  after { Sidekiq::ScheduledSet.new.clear }

  def schedule_job(target_campaign, contact_id, at:)
    Sidekiq::Client.push(
      'class' => 'ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper',
      'wrapped' => 'Campaigns::SendCampaignContactJob',
      'queue' => 'low',
      'args' => [Campaigns::SendCampaignContactJob.new(target_campaign.id, contact_id).serialize],
      'at' => at.to_f
    )
  end

  it 'deletes only the scheduled jobs belonging to the given campaign' do
    schedule_job(campaign, 1, at: 1.hour.from_now)
    schedule_job(campaign, 2, at: 2.hours.from_now)
    schedule_job(other_campaign, 3, at: 1.hour.from_now)

    expect(Sidekiq::ScheduledSet.new.size).to eq 3

    cancelled = described_class.new(campaign: campaign).perform

    expect(cancelled).to eq 2
    remaining_campaign_ids = Sidekiq::ScheduledSet.new.map { |job| job.display_args.first }
    expect(remaining_campaign_ids).to eq [other_campaign.id]
  end

  it 'is idempotent' do
    schedule_job(campaign, 1, at: 1.hour.from_now)

    described_class.new(campaign: campaign).perform
    second_pass = described_class.new(campaign: campaign).perform

    expect(second_pass).to eq 0
  end
end
