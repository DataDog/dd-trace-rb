module TelemetryHelpers
  module ClassMethods
    def mark_telemetry_started
      before do
=begin
        Datadog::Core::Telemetry::Worker::TELEMETRY_STARTED_ONCE.send(:reset_ran_once_state_for_tests)
        Datadog::Core::Telemetry::Worker::TELEMETRY_STARTED_ONCE.run do
          true
        end
        expect(Datadog::Core::Telemetry::Worker::TELEMETRY_STARTED_ONCE).to be_success
=end
      end
    end
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
