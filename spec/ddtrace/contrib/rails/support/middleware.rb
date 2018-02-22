RSpec.shared_context 'Rails middleware' do
  let(:rails_middleware) { [] }

  let(:debug_middleware) do
    stub_const('DebugMiddleware', Class.new do
      def initialize(app)
        @app = app
      end

      def call(env)
        @app.call(env)
      rescue Exception => e
        raise
      end
    end)
  end
end
