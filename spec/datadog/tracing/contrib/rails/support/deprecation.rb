# Raises error when a deprecation would be emitted
def raise_on_rails_deprecation!
  # DEV: In Rails 6.1 `ActiveSupport::Deprecation.disallowed_warnings`
  #      was introduced that allows fine grain configuration
  #      of which warnings are allowed, in case we need
  #      such feature.
  ActiveSupport::Deprecation.behavior = :raise
end
