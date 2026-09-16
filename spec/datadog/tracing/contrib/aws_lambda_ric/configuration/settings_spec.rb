# frozen_string_literal: true

require "datadog/tracing/contrib/aws_lambda_ric/configuration/settings"
require "datadog/tracing/contrib/shared_settings_examples"

RSpec.describe Datadog::Tracing::Contrib::AwsLambdaRic::Configuration::Settings do
  it_behaves_like "with on_error setting"
end
