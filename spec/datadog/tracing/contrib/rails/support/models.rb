RSpec.shared_context 'Rails models' do
  let(:application_record) do
    unless (defined? no_db) && no_db
      stub_const(
        'ApplicationRecord',
        Class.new(ActiveRecord::Base) do
          self.abstract_class = true
        end
      )
    end
  end
end
