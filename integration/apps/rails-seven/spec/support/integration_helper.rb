require 'net/http'

module IntegrationHelper
  shared_context 'integration test' do
    before do
      skip 'Integration tests not enabled.' unless ENV['TEST_INTEGRATION']
    end

    def hostname
      ENV['TEST_HOSTNAME']
    end

    def port
      ENV['TEST_PORT']
    end

    def get(path)
      uri = URI("http://#{hostname}:#{port}/#{path}")
      Net::HTTP.get_response(uri)
    end
  end

  module ClassMethods
    def di_test
      if RUBY_ENGINE == 'jruby'
        before(:all) do
          skip "Dynamic instrumentation is not supported on JRuby"
        end
      end
      if RUBY_VERSION < "2.6"
        before(:all) do
          skip "Dynamic instrumentation requires Ruby 2.6 or higher"
        end
      end
    end
  end

  def self.included(base)
    base.extend(ClassMethods)
  end
end
