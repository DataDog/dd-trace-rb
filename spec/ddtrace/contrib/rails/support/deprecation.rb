# Raises error when a deprecation would be emitted
def raise_on_rails_deprecation!
  # DEV: In Rails 6.1 `ActiveSupport::Deprecation.disallowed_warnings`
  # DEV: was introduced that allows fine grain configuration
  # DEV: of which warnings are allowed, in case we need
  # DEV: such feature.
  ActiveSupport::Deprecation.behavior = :raise
end
