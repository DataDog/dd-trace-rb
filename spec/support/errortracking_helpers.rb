require 'datadog/core/errortracking/component'
require 'support/platform_helpers'

module ErrortrackingHelpers
  def self.supported?
    if Datadog::Core::Errortracking::Component::ERRORTRACKING_FAILURE
      raise " does not seem to be available: #{Datadog::Core::Errortracking::Component::ERRORTRACKING_FAILURE}. " \
        'Try running `bundle exec rake compile` before running this test.'
    end
    true
  end
end
