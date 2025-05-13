module ErrortrackingHelpers
  def error_tracking_test
    if PlatformHelpers.jruby?
      before(:all) do
        skip 'Error Tracking is not supported on JRuby'
      end
    end
    if RUBY_VERSION < '2.6'
      before(:all) do
        skip 'Error Tracking requires Ruby 2.6 or higher'
      end
    end
  end
end

RSpec.configure do |config|
  config.extend ErrortrackingHelpers
end
