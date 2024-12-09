require 'datadog/core/crashtracking/component'
require 'support/platform_helpers'

module CrashtrackingHelpers
  def self.supported?
    # Only works with MRI on Linux
    if PlatformHelpers.mri? && PlatformHelpers.linux?
      if Datadog::Core::Crashtracking::Component::LIBDATADOG_API_FAILURE
        raise " does not seem to be available: #{Datadog::Core::Crashtracking::Component::LIBDATADOG_API_FAILURE}. " \
          'Try running `bundle exec rake compile` before running this test.'
      end
      true
    else
      false
    end
  end
end
