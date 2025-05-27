module TelemetryHelpers
  module ClassMethods
  end

  def self.included(base)
    base.extend(ClassMethods)
  end

  RSpec.shared_examples 'telemetry event with no attributes' do
    it 'all event instances to the same' do
      event1 = event_class.new
      event2 = event_class.new
      expect(event1).to eq(event2)
      expect(event1.hash).to eq(event2.hash)
    end
  end
end
