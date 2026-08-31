# Service to handle phone number normalization for WhatsApp messages
# Currently supports Brazil, Argentina, and Mexico phone number format variations
# Supports both WhatsApp Cloud API and Twilio WhatsApp providers
class Whatsapp::PhoneNumberNormalizationService
  def initialize(inbox)
    @inbox = inbox
  end

  # @param raw_number [String] The phone number in provider-specific format
  #   - Cloud: "5541988887777" (clean number)
  #   - Twilio: "whatsapp:+5541988887777" (prefixed format)
  # @param provider [Symbol] :cloud or :twilio
  # @return [String] Normalized source_id in provider format or original if not found
  def normalize_and_find_contact_by_provider(raw_number, provider)
    clean_number = extract_clean_number(raw_number, provider)
    normalizer = find_normalizer_for_country(clean_number)
    return raw_number unless normalizer

    provider_format = format_for_provider(normalizer.normalize(clean_number), provider)
    existing_contact_inbox = find_existing_contact_inbox(provider_format)

    existing_contact_inbox&.source_id || raw_number
  end

  # Returns the number normalized and formatted for the given provider (e.g. clean digits
  # for :cloud, "whatsapp:+..." for :twilio), or the original raw_number unchanged if no
  # country-specific normalizer applies. Unlike normalize_and_find_contact_by_provider, this
  # does not require or look up an existing contact_inbox — useful for outbound sends (e.g.
  # CSV campaigns) where the recipient may not be a contact yet.
  def normalize(raw_number, provider)
    clean_number = extract_clean_number(raw_number, provider)
    normalizer = find_normalizer_for_country(clean_number)
    return raw_number unless normalizer

    format_for_provider(normalizer.normalize(clean_number), provider)
  end

  private

  attr_reader :inbox

  def find_normalizer_for_country(waid)
    NORMALIZERS.map(&:new)
               .find { |normalizer| normalizer.handles_country?(waid) }
  end

  def find_existing_contact_inbox(normalized_waid)
    inbox.contact_inboxes.find_by(source_id: normalized_waid)
  end

  # Extract clean number from provider-specific format
  def extract_clean_number(raw_number, provider)
    case provider
    when :twilio
      raw_number.gsub(/^whatsapp:\+/, '') # Remove prefix: "whatsapp:+5541988887777" → "5541988887777"
    else
      raw_number # Default fallback for unknown providers
    end
  end

  # Format normalized number for provider-specific storage
  def format_for_provider(clean_number, provider)
    case provider
    when :twilio
      "whatsapp:+#{clean_number}" # Add prefix: "5541988887777" → "whatsapp:+5541988887777"
    else
      clean_number # Default for :cloud and unknown providers: "5541988887777"
    end
  end

  NORMALIZERS = [
    Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer,
    Whatsapp::PhoneNormalizers::ArgentinaPhoneNormalizer,
    Whatsapp::PhoneNormalizers::MexicoPhoneNormalizer
  ].freeze
end
