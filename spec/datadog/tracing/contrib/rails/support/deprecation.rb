# Raises error when a deprecation would be emitted
def raise_on_rails_deprecation!
  # DEV: In Rails 6.1 `ActiveSupport::Deprecation.disallowed_warnings`
  #      was introduced that allows fine grain configuration
  #      of which warnings are allowed, in case we need
  #      such feature.
  #
  # In Rails 7.1 calling ActiveSupport::Deprecation.behavior= raises an exception.
  # The new way of configuring deprecation is per framework, and each framework has
  # its own deprecator object. If none of the frameworks have a deprecator object,
  # we must be on an older version of Rails, in which case we can configure the
  # deprecation behavior on ActiveSupport globally.
  executed = false
  if defined?(ActiveRecord) && ActiveRecord.respond_to?(:deprecator)
    ActiveRecord.deprecator.behavior = :raise
    executed = true
  end
  if defined?(ActiveModel) && ActiveModel.respond_to?(:deprecator)
    ActiveModel.deprecator.behavior = :raise
    executed = true
  end
  if defined?(ActionCable) && ActionCable.respond_to?(:deprecator)
    ActionCable.deprecator.behavior = :raise
    executed = true
  end
  if defined?(Rails) && Rails.respond_to?(:deprecator)
    Rails.deprecator.behavior = :raise
    executed = true
  end
  ActiveSupport::Deprecation.behavior = :raise unless executed
end
