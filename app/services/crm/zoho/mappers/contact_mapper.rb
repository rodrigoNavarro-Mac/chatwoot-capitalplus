class Crm::Zoho::Mappers::ContactMapper
  def self.map(contact, module_name: 'Leads')
    new(contact, module_name).map
  end

  def initialize(contact, module_name)
    @contact = contact
    @module_name = module_name
  end

  def map
    if @module_name == 'Leads'
      lead_fields
    else
      contact_fields
    end
  end

  private

  attr_reader :contact

  def lead_fields
    {
      'First_Name' => first_name,
      'Last_Name' => last_name.presence || '(sin apellido)',
      'Email' => contact.email.presence,
      'Phone' => contact.phone_number.presence
    }.compact
  end

  def contact_fields
    {
      'First_Name' => first_name,
      'Last_Name' => last_name.presence || '(sin apellido)',
      'Email' => contact.email.presence,
      'Phone' => contact.phone_number.presence
    }.compact
  end

  def first_name
    parts = contact.name.to_s.split(' ', 2)
    parts.first.presence || contact.name
  end

  def last_name
    parts = contact.name.to_s.split(' ', 2)
    parts.last if parts.length > 1
  end
end
