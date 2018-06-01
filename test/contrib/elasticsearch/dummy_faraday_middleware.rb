require 'faraday'

class DummyFaradayMiddleware < Faraday::Middleware
  def initialize(app)
    super(app)
  end

  def call(env)
    @app.call(env)
  end
end
