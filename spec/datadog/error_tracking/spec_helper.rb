# frozen_string_literal: true
module ErrorTrackingHelpers
  def error_tracking_test
    if PlatformHelpers.jruby?
      before(:all) do
        skip 'Error Tracking is not supported on JRuby'
      end
    end
    if RUBY_VERSION < '2.7'
      before(:all) do
        skip 'Error Tracking requires Ruby 2.7 or higher'
      end
    end
  end
end

RSpec.configure do |config|
  config.extend ErrorTrackingHelpers
end
