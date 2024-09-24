module DIHelpers
  module ClassMethods
    def di_test
      if PlatformHelpers.jruby?
        before(:all) do
          skip "Dynamic instrumentation is not supported on JRuby"
        end
      end
    end
  end
end

RSpec.configure do |config|
  config.extend DIHelpers::ClassMethods
end
