require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/active_record/utils'

RSpec.describe Datadog::Tracing::Contrib::ActiveRecord::Utils do
  describe 'regression: retrieving database without an active connection does not raise an error' do
    before do
      root_pw = ENV.fetch('TEST_MYSQL_ROOT_PASSWORD', 'root')
      host = ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1')
      port = ENV.fetch('TEST_MYSQL_PORT', '3306')
      db = ENV.fetch('TEST_MYSQL_DB', 'mysql')
      ActiveRecord::Base.establish_connection("mysql2://root:#{root_pw}@#{host}:#{port}/#{db}")
      ActiveRecord::Base.remove_connection
    end

    after do
      root_pw = ENV.fetch('TEST_MYSQL_ROOT_PASSWORD', 'root')
      host = ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1')
      port = ENV.fetch('TEST_MYSQL_PORT', '3306')
      db = ENV.fetch('TEST_MYSQL_DB', 'mysql')
      ActiveRecord::Base.establish_connection("mysql2://root:#{root_pw}@#{host}:#{port}/#{db}")
    end

    it do
      expect { described_class.adapter_name }.to_not raise_error
      expect { described_class.adapter_host }.to_not raise_error
      expect { described_class.adapter_port }.to_not raise_error
      expect { described_class.database_name }.to_not raise_error
    end
  end
end
