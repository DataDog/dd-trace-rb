require 'spec_helper'
require 'roda'
require 'ddtrace'
require 'ddtrace/contrib/roda/instrumentation'
require 'ddtrace/contrib/roda/ext'

RSpec.describe Datadog::Contrib::Roda::Instrumentation do
	describe 'when implemented in Roda' do
		let(:test_class) {Class.new(Roda)}
		let(:env) {{:REQUEST_METHOD =>'GET'}}
		let(:roda) {test_class.new(env)}

		after(:each) do
			Datadog.registry[:roda].reset_configuration!
		end

		describe '#datadog_pin' do
			subject(:datadog_pin) {roda.datadog_pin}

			context 'when roda is configured' do

				context 'tracer is enabled' do
					before {Datadog.configure {|c| c.use :roda}}
					it 'enables the tracer' do
						expect(datadog_pin.tracer.enabled).to eq(true)
					end
					it 'has a web app type' do
						expect(datadog_pin.app_type).to eq(Datadog::Ext::AppTypes::WEB)
					end
				end

				context 'with a custom service name' do
					let(:custom_service_name) {"custom service name"}

					before {Datadog.configure {|c| c.use :roda, service_name: custom_service_name}}
					it 'sets a custom service name' do
						expect(datadog_pin.service_name).to eq(custom_service_name)
					end
				end

				context 'without a service name' do
					before {Datadog.configure {|c| c.use :roda}}
					it 'sets a default' do
						expect(datadog_pin.service_name).to eq(Datadog::Contrib::Roda::Ext::SERVICE_NAME)
					end
				end
			end
		end


		# describe '#call' do
		# 	subject(:datadog_pin) {roda.datadog_pin}
		# TODO
		# 	it 'does a thing' do
		# 	end
		# end
	end
end