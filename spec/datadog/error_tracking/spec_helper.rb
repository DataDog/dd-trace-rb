module ErrorTrackingHelpers
  def error_tracking_test
    if PlatformHelpers.jruby?
      before(:all) do
        skip "Error Tracking is not supported on JRuby"
      end
    end
  end
end

RSpec.configure do |config|
  config.extend ErrorTrackingHelpers
end
