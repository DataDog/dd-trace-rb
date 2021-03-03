module Contrib
  # Contrib-specific tracer helpers.
  # For contrib, we only allow one tracer to be active:
  # the global +Datadog.tracer+.
  #
  module TracerHelpers
    RSpec.configure do |config|
      config.include_context 'completed traces'

      config.before do
        allow(Datadog).to receive(:tracer).and_return(tracer)
      end

      # config.around do |example|
      #   # Execute shutdown! after the test has finished
      #   # teardown and mock verifications.
      #   #
      #   # Changing this to `config.after(:each)` would
      #   # put shutdown! inside the test scope, interfering
      #   # with mock assertions.
      #   example.run.tap do
      #     Datadog.trace_writer.stop(true, 5)
      #   end
      # end
    end

    # # TODO: Move this to spec/support/tracer_helpers.rb?
    # #       Could use a function like this to implement a tracer + writer
    # #       instead of using a test buffer for integration testing.
    # # Useful for integration testing.
    # def use_real_tracer!
    #   @use_real_tracer = true
    #   allow(Datadog::Tracer).to receive(:new).and_call_original
    # end
  end
end
