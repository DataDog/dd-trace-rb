module TelemetryHelpers
  module ClassMethods
    def mark_telemetry_started
      before do
        Datadog::Core::Telemetry::Worker::TELEMETRY_STARTED_ONCE.send(:reset_ran_once_state_for_tests)
        Datadog::Core::Telemetry::Worker::TELEMETRY_STARTED_ONCE.run do
          true
        end
        expect(Datadog::Core::Telemetry::Worker::TELEMETRY_STARTED_ONCE).to be_success
      end
    end
  end

  def self.included(base)
    base.extend(ClassMethods)
  end
end
