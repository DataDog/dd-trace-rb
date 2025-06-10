require 'datadog/core'
require 'support/platform_helpers'

module LibdatadogHelpers
  def self.supported?
    # Only works with MRI on Linux
    if PlatformHelpers.mri? && PlatformHelpers.linux?
      if Datadog::Core::LIBDATADOG_API_FAILURE
        raise "Libdatadog does not seem to be available: #{Datadog::Core::LIBDATADOG_API_FAILURE}. " \
          'Try running `bundle exec rake compile` before running this test.'
      end
      true
    else
      false
    end
  end
end
