require 'spec_helper'
require 'ddtrace'
require 'rack/test'
require 'roda'

RSpec.describe 'Roda analytics configuration' do
	include Rack::Test::Methods

	let(:tracer) { get_test_tracer }
	let(:configuration_options) { { tracer: tracer, analytics_enabled: true } }
	let(:spans) { tracer.writer.spans }
	let(:span) { spans.first }

	before(:each) do
		Datadog.configure do |c|
			c.use :roda, configuration_options
		end
	end

	around do |example|
		Datadog.registry[:roda].reset_configuration!
		example.run
		Datadog.registry[:roda].reset_configuration!
	end

	shared_context 'Roda app with two endpoints' do
		let(:app) do
			Class.new(Roda) do
				route do |r|
					r.root do
						# GET /
						r.get do
							"Hello World!"
						end
					end
					# GET /worlds/1
					r.get "worlds", Integer do |world|
						"Hello, world #{world}"
					end
				end
			end
		end
	end

	context 'when analytics is enabled' do

		include_context 'Roda app with two endpoints'
		subject(:response) {get '/'}

		it do
			expect(response.status).to eq(200)
			expect(response.header).to eq({"Content-Type"=>"text/html", "Content-Length"=>"12"})
			expect(spans).to have(1).items
			expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(1)
			expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE_INBOUND)
			expect(span.status).to eq(0)
			expect(span.resource).to eq("GET")
			expect(span.name).to eq("roda.request")
			expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
			expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/')
			expect(span.parent).to be nil
		end
	end
end