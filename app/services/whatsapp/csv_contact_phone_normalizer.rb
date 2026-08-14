# Fixes the long-standing WhatsApp/Meta quirk where Mexican numbers appear with or
# without the legacy "1" mobile prefix (52 1 XX... vs 52 XX...), or missing the "52"
# country code entirely on bare 10-digit local numbers, before a CSV campaign sends
# or checks a phone. Reuses the same per-country normalizer used for inbound contact
# matching so outbound sends and the WA_INVALID_PHONES lookup key agree on one format.
class Whatsapp::CsvContactPhoneNormalizer
  pattr_initialize [:inbox!]

  def normalize(phone)
    digits = phone.delete('+')
    normalized = Whatsapp::PhoneNumberNormalizationService.new(inbox).normalize(digits, :cloud)
    "+#{normalized}"
  end
end
