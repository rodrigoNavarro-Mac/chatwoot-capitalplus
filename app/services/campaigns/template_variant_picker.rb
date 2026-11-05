# Decides which template a recipient gets in a WhatsApp campaign A/B test. The bucket comes from
# a hash of the campaign and the phone's last 10 digits instead of a random draw, so a contact
# always lands on the same variant even if the campaign is paused, resumed or re-scheduled, and
# never receives both templates.
class Campaigns::TemplateVariantPicker
  Variant = Struct.new(:key, :template_params, :message)

  pattr_initialize [:campaign!]

  def self.ab_test?(campaign)
    campaign.template_variant_b.is_a?(Hash) && campaign.template_variant_b['template_params'].present?
  end

  def ab_test?
    self.class.ab_test?(campaign)
  end

  def for_phone(phone)
    return Variant.new(nil, campaign.template_params, campaign.message) unless ab_test?

    bucket(phone) < campaign.ab_split ? variant_a : variant_b
  end

  private

  def variant_a
    Variant.new('A', campaign.template_params, campaign.message)
  end

  def variant_b
    variant = campaign.template_variant_b
    Variant.new('B', variant['template_params'], variant['message'].presence || campaign.message)
  end

  def bucket(phone)
    Zlib.crc32("#{campaign.id}:#{Campaigns::RecipientEligibility.phone_key(phone)}") % 100
  end
end
