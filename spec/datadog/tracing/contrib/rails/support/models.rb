RSpec.shared_context 'Rails models' do
  let(:application_record) do
    stub_const(
      'ApplicationRecord',
      Class.new(ActiveRecord::Base) do
        self.abstract_class = true
      end
    )
  end
end
