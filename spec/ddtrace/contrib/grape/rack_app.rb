require 'grape'
require 'ddtrace/contrib/grape/patcher'

# patch Grape before the application
Datadog::Contrib::Grape::Patcher.patch()

class RackTestingAPI < Grape::API
  desc 'Returns a success message'
  get :success do
    'OK'
  end

  desc 'Returns an error'
  get :hard_failure do
    raise StandardError, 'Ouch!'
  end
end
