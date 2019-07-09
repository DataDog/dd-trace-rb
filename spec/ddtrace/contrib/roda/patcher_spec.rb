require 'spec_helper'
require 'ddtrace'
require 'rack/test'
require 'roda'
require 'pry'

RSpec.describe 'Roda instrumentation' do
	include Rack::Test::Methods

	# Gets a faux writer from TracerHelper module
	let(:tracer) { get_test_tracer }
	let(:configuration_options) { { tracer: tracer } }
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

	# Basic hello world application
	shared_context 'Roda hello world app' do
		# On GET /, returns "Hello World!"
		let(:app) do
			Class.new(Roda) do
				route do |r|
					r.root do
						r.get do
							"Hello World!"
						end
					end
				end
			end
		end
	end

	context 'when a basic request is made' do

		include_context 'Roda hello world app'
		subject(:response) {get '/'}
		it do
			is_expected.to be_ok
			expect(response.header).to eq({"Content-Type"=>"text/html", "Content-Length"=>"12"})
			expect(spans).to have(1).items
		end

	end




end
