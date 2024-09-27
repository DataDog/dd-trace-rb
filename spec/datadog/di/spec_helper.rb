module DIHelpers
  module ClassMethods
    def di_test
      if PlatformHelpers.jruby?
        before(:all) do
          skip "Dynamic instrumentation is not supported on JRuby"
        end
      end
      if RUBY_VERSION < '2.6'
        before(:all) do
          skip "Dynamic instrumentation requires Ruby 2.6 or higher"
        end
      end
    end
  end
end

RSpec.configure do |config|
  config.extend DIHelpers::ClassMethods
end
