require 'spec_helper'
require 'ddtrace'
require 'rack/test'
require 'roda'

RSpec.describe 'Roda instrumentation' do
	include Rack::Test::Methods

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

	shared_context 'Roda app with 1 successful endpoint' do
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

	shared_context 'Roda app with server error' do
		let(:app) do
			Class.new(Roda) do
				route do |r|
					r.root do
						r.get do
							r.halt([500, {'Content-Type'=>'text/html'}, ['test']])
						end
					end
				end
			end
		end
	end

	context 'when a 200 status code request is made' do

		include_context 'Roda app with 1 successful endpoint'
		subject(:response) {get '/'}
		it do
			is_expected.to be_ok
			expect(response.header).to eq({"Content-Type"=>"text/html", "Content-Length"=>"12"})
			
			expect(spans).to have(1).items
			expect(span.span_type).to eq("http")
			expect(span.status).to eq(0)
			expect(span.name).to eq("roda.request")
			expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
			expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/')
			expect(span.parent).to be nil
		end
	end


	context 'when a 404 status code request is made' do

		include_context 'Roda app with 1 successful endpoint'
		subject(:response) {get '/unsuccessful_endpoint'}
		it do
			expect(response.status).to eq(404)
			expect(response.header).to eq({"Content-Type"=>"text/html", "Content-Length"=>"0"})
			
			expect(spans).to have(1).items
			expect(span.parent).to be nil
			expect(span.span_type).to eq("http")
			expect(span.name).to eq("roda.request")
			expect(span.status).to eq(0)
			expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
			expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/unsuccessful_endpoint')
		end
	end

	context 'when a 500 status code request is made' do

		include_context 'Roda app with server error'
		subject(:response) {get '/'}
		it do
			expect(response.status).to eq(500)
			expect(response.header).to eq({"Content-Type"=>"text/html", "Content-Length"=>"4"})
		 
			expect(spans).to have(1).items
			expect(span.parent).to be nil
			expect(span.span_type).to eq("http")
			expect(span.name).to eq("roda.request")
			expect(span.status).to eq(1)
			expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
			expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/')
		end
	end


	context 'when the tracer is disabled' do  
		include_context 'Roda app with 1 successful endpoint'
		subject(:response) {get '/'}

		let(:tracer) { get_test_tracer(enabled: false) }

		it do
			is_expected.to be_ok
			expect(spans).to be_empty
		end
	end
end