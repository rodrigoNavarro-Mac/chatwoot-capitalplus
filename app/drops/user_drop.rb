class UserDrop < BaseDrop
  def name
    @obj.try(:name).try(:split).try(:map, &:capitalize).try(:join, ' ')
  end

  def available_name
    @obj.try(:available_name)
  end

  def email
    @obj.try(:email)
  end

  def first_name
    @obj.try(:name).try(:split).try(:first).try(:capitalize)
  end

  def last_name
    name_parts = @obj.try(:name).try(:split)
    name_parts.try(:last).try(:capitalize) if name_parts.try(:size).to_i > 1
  end
end
