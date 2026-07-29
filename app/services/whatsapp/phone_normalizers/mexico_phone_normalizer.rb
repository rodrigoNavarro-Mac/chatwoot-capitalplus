# Handles Mexico phone number normalization
#
# Mexican mobile WhatsApp numbers can appear with or without a legacy "1" mobile prefix
# right after the country code (52 1 XX XXXX XXXX vs 52 XX XXXX XXXX) — a long-standing
# WhatsApp/Meta quirk for MX numbers, analogous to Argentina's "9" prefix. This normalizer
# removes the "1" when present to create a consistent format: 52 + area + number (10 digits).
class Whatsapp::PhoneNormalizers::MexicoPhoneNormalizer < Whatsapp::PhoneNormalizers::BasePhoneNormalizer
  def normalize(waid)
    return waid unless handles_country?(waid)

    # Only strip when it leaves a 10-digit local number, to avoid stripping a real leading
    # "1" from the subscriber number itself.
    waid.length == 13 ? waid.sub(/^521/, '52') : waid
  end

  private

  def country_code_pattern
    /^52/
  end
end
