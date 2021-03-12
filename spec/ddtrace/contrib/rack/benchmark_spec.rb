# require 'ddtrace/contrib/support/spec_helper'
require 'rack/test'
require 'securerandom'

require 'rack'
require 'ddtrace'
require 'ddtrace/contrib/rack/middlewares'

RSpec.describe 'Rack benchmark' do
  include Rack::Test::Methods

  let(:rack_options) { {} }

  before do
    tracer = self.tracer
    Datadog.configure do |c|
      c.use :rack, rack_options
      c.tracer = tracer
    end
  end

  let(:app) do
    app_routes = routes
    instrument = self.instrument

    Rack::Builder.new do
      use Datadog::Contrib::Rack::TraceMiddleware if instrument
      instance_eval(&app_routes)
    end.to_app
  end

  let(:instrument) { true }

  context 'with a basic route' do
    let(:routes) do
      proc do
        map '/success/' do
          run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, ['OK']] })
        end
      end
    end

    describe 'GET request' do
      subject(:response) { get route }

      context 'with query string parameters' do
        let(:route) { '/success?foo=bar' }

        it do
          is_expected.to be_ok
          expect(spans).to have(1).items

          expect(span.name).to eq('rack.request')
          expect(span.span_type).to eq('web')
          expect(span.service).to eq('rack')
          expect(span.resource).to eq('GET 200')
          expect(span.get_tag('http.method')).to eq('GET')
          expect(span.get_tag('http.status_code')).to eq('200')
          # Since REQUEST_URI isn't available in Rack::Test by default (comes from WEBrick/Puma)
          # it reverts to PATH_INFO, which doesn't have query string parameters.
          expect(span.get_tag('http.url')).to eq('/success')
          expect(span.get_tag('http.base_url')).to eq('http://example.org')
          expect(span.status).to eq(0)
          expect(span.parent).to be nil
        end

        shared_context 'distributed tracing headers' do
          let(:trace_id) { "8694058539399423136" }
          let(:parent_id) { "3605612475141592985" }
          let(:sampling_priority) { Datadog::Ext::Priority::AUTO_KEEP.to_s }
          let(:origin) { 'synthetics' }

          before do
            header Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID, trace_id
            header Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID, parent_id
            header Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY, sampling_priority
            header Datadog::Ext::DistributedTracing::HTTP_HEADER_ORIGIN, origin
          end
        end

        let(:rack_options) { super().merge(request_queuing: true, analytics_enabled: true,
                                           headers: {
                                             request: [Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID],
                                             response: ['content-type'],
                                           }) }
        before do
          header 'X-Request-Start', "t=#{Time.now.to_f}"
        end

        context 'benchmark' do
          require 'spec/ddtrace/benchmark/support/benchmark_helper'

          # Remove objects created during specs from memory results
          let(:ignore_files) { %r{(/spec/)} }
          let(:steps) { [1] }

          def subject(_i)
            get '/success?foo=bar#frag'
            writer.clear
            # tracer.provider.context = nil
          end

          let(:tracer) { new_tracer(writer: writer) }
          let(:writer) { FauxWriter.new(call_original: false) }

          puts "REMOVE MOCK ON TRACER#WRITE"

          xcontext 'without instrumentation (baseline)' do
            let(:instrument) { false }
            # include_examples 'benchmark', only: [:ruby_prof, :timing]
            # include_examples 'benchmark', only: [:ruby_prof]
            # include_examples 'benchmark', only: [:timing]
            include_examples 'benchmark', only: [:memory_report]
          end

          include_context 'distributed tracing headers'

          context 'with instrumentation' do
            let(:instrument) { true }
            # include_examples 'benchmark', only: [:ruby_prof, :timing]
            # include_examples 'benchmark', only: [:ruby_prof]
            include_examples 'benchmark', only: [:timing]
            include_examples 'benchmark', only: [:memory_report]
          end

          # baseline with all code paths - no instrumentation
          # 1     13.895k (± 2.3%) i/s -     69.666k in   5.016292s

          # Tracer with all code paths (old writer)
          # 1      2.991k (± 9.5%) i/s -     14.880k in   5.026251s
          # + configuration.to_h (old writer)
          # 1      3.303k (±11.0%) i/s -     16.445k in   5.054499s
          # + set_tag only span.rb
          # 1      3.688k (±12.8%) i/s -     18.113k in   5.013802s
          # + restoring old tracer improvements PR
          # 1      3.945k (±11.4%) i/s -     19.497k in   5.023252s
          # + remove now_allocations
          # 1      3.931k (±10.6%) i/s -     19.392k in   5.000654s
          # + cached rack distributed header
          # 1      4.139k (±11.5%) i/s -     20.691k in   5.085760s
          # + integer header parsing
          # 1      4.210k (±10.5%) i/s -     20.827k in   5.009664s
          # + b3 header naming cache
          # 1      4.147k (±11.1%) i/s -     20.440k in   5.003644s
          # + quantitize short circuit
          # 1      4.267k (±11.0%) i/s -     21.228k in   5.048626s
          # + request header processed cached values
          # 1      4.440k (±10.3%) i/s -     22.302k in   5.088874s
          # + response header any?
          # 1      4.496k (±11.5%) i/s -     22.440k in   5.075714s
          # + response header cache
          # 1      4.526k (±11.0%) i/s -     22.387k in   5.019871s
          # + analytics condition order
          # 1      4.586k (±10.7%) i/s -     22.800k in   5.040415s
          # + base_url cache
          # 1      4.729k (±10.9%) i/s -     23.664k in   5.074413s
          # + remove dup
          # 1      4.751k (±11.2%) i/s -     23.769k in   5.081703s
          # + remove .nil?
          # 1      4.878k (±11.4%) i/s -     24.360k in   5.072605s
          # + no .utc (HUGE)
          # 1      5.137k (± 3.7%) i/s -     25.758k in   5.021417s
          # + common precomputed resource name
          # 1      5.189k (± 2.2%) i/s -     26.265k in   5.064537s
          # + faster proxy header time extraction
          # 1      5.289k (± 1.8%) i/s -     26.624k in   5.035659s




          # with distributed (cheap) + request queueing
          # 1      3.091k (±10.3%) i/s -     15.276k in   5.008786s
          # + req resp headers (no tomfoolery)
          # 1      2.989k (±10.9%) i/s -     14.940k in   5.071763s
          # + req resp headers (w/ tomfoolery: case insensitive response)
          # 1      3.012k (±10.0%) i/s -     15.000k in   5.045500s

          # baseline (simple case) - no instrumentation
          # 1     16.097k (± 2.3%) i/s -     80.622k in   5.011147s

          # current full tracer
          # 1      3.699k (± 8.8%) i/s -     18.624k in   5.091065s
          # tracer.tracer = nil
          # 3.0k
          # 1      9.655k (± 2.2%) i/s -     48.692k in   5.045683s
          # + no distributed extractor
          # 2.2K
          # 1     11.811k (± 2.8%) i/s -     59.143k in   5.011693s
          # + no tracer instance fetch from config
          # 1.6K
          # 1     13.400k (± 1.7%) i/s -     68.068k in   5.081236s
          # + no config access at all
          # 1.9K
          # 1     15.241k (± 4.4%) i/s -     77.428k in   5.091032s
          # + no duping env
          # 1.0K
          # 1     16.218k (± 1.3%) i/s -     81.938k in   5.053316s
        end
      end
    end
  end
end
