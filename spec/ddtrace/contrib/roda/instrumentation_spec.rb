require 'spec_helper'
# require 'ddtrace/contrib/analytics_examples'
require 'roda'
require 'ddtrace'
require 'ddtrace/contrib/roda/instrumentation'
require 'ddtrace/contrib/roda/ext'

RSpec.describe Datadog::Contrib::Roda::Instrumentation do
	describe 'when implemented in Roda' do
		let(:test_class) {Class.new(Roda)}
		let(:env) {{:REQUEST_METHOD =>'GET'}}
		let(:roda) {test_class.new(env)}

		describe '#datadog_pin' do
			subject(:datadog_pin) {roda.datadog_pin}

				context 'when roda is configured' do
					context 'with a service name' do
						let(:custom_service_name) {"custom service name"}
						let(:default_service_name) {Datadog::Contrib::Roda::Ext::SERVICE_NAME}
					
						# before {Datadog.configure {|c| c.use :roda, service_name: custom_service_name}}
						it 'sets a custom service name' do
							Datadog.configure {|c| c.use :roda, service_name: custom_service_name}
							expect(datadog_pin.service_name).to eq(custom_service_name)
						end

						# before {Datadog.configure {|c| c.use :roda}}
						it 'sets a default service name' do
							Datadog.configure {|c| c.use :roda}
							expect(datadog_pin.service_name).to eq(default_service_name)
						end
					end
				end
		end
	end
end