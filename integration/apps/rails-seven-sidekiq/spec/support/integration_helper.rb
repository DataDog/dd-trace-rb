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
end
