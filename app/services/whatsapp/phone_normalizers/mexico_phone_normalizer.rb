# Handles Mexico phone number normalization
#
# Mexican mobile WhatsApp numbers can appear with or without a legacy "1" mobile prefix
# right after the country code (52 1 XX XXXX XXXX vs 52 XX XXXX XXXX) — a long-standing
# WhatsApp/Meta quirk for MX numbers, analogous to Argentina's "9" prefix. This normalizer
# removes the "1" when present to create a consistent format: 52 + area + number (10 digits).
# Only strip when it leaves a 10-digit local number (13-digit WAID), to avoid stripping a
# real leading "1" from a shorter national number.
class Whatsapp::PhoneNormalizers::MexicoPhoneNormalizer < Whatsapp::PhoneNormalizers::BasePhoneNormalizer
  COUNTRY_CODE_WITH_MOBILE_LENGTH = 13

  def normalize(waid)
    return waid unless handles_country?(waid)
    return waid unless waid.length == COUNTRY_CODE_WITH_MOBILE_LENGTH

    waid.sub(/^521/, '52')
  end

  private

  def country_code_pattern
    /^52/
  end
end
