module TelemetryHelpers
  module ClassMethods
    def mark_telemetry_started
      before do
        Datadog::Core::Telemetry::Worker::TELEMETRY_STARTED_ONCE.run do
          true
        end
      end
    end
  end

  def self.included(base)
    base.extend(ClassMethods)
  end
end
