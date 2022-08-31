require 'datadog/demo_env'
require_relative 'app/datadog'
require_relative 'app/acme'

use Datadog::Tracing::Contrib::Rack::TraceMiddleware if Datadog::DemoEnv.feature?('tracing')
use Datadog::AppSec::Contrib::Rack::RequestMiddleware if Datadog::DemoEnv.feature?('appsec')
run Acme::Application.new
