RSpec.shared_context 'Rails middleware' do
  let(:rails_middleware) { [] }

  let(:debug_middleware) do
    stub_const(
      'DebugMiddleware',
      Class.new do
        def initialize(app)
          @app = app
        end

        def call(env)
          @app.call(env)
          # rubocop:disable Lint/RescueException
        rescue Exception => _e
          raise
          # ruboco:enable Lint/RescueException
        end
      end
    )
  end
end
