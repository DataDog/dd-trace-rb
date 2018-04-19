require 'spec_helper'

require 'ddtrace/contrib/active_record/utils'

RSpec.describe Datadog::Contrib::ActiveRecord::Utils do
  describe 'regression: retrieving database without an active connection does not raise an error' do
    before(:each) do
      ActiveRecord::Base.establish_connection('mysql2://root:root@127.0.0.1:53306/mysql')
      ActiveRecord::Base.remove_connection
    end

    after(:each) { ActiveRecord::Base.establish_connection('mysql2://root:root@127.0.0.1:53306/mysql') }

    it do
      expect { described_class.adapter_name }.to_not raise_error
      expect { described_class.adapter_host }.to_not raise_error
      expect { described_class.adapter_port }.to_not raise_error
      expect { described_class.database_name }.to_not raise_error
    end
  end
end
