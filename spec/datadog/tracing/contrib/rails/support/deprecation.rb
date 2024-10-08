# Raises error when a deprecation would be emitted
def raise_on_rails_deprecation!
  # DEV: In Rails 6.1 `ActiveSupport::Deprecation.disallowed_warnings`
  #      was introduced that allows fine grain configuration
  #      of which warnings are allowed, in case we need
  #      such feature.
  #
  # In Rails 7.1 calling ActiveSupport::Deprecation.behavior= is deprecated
  if defined?(Rails) && Rails.gem_version >= Gem::Version.new(7.1)
    Rails.deprecator.behavior = :raise
  else
    ActiveSupport::Deprecation.behavior = :raise
  end
end
