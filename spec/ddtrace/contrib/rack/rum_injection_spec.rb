require 'ddtrace/contrib/support/spec_helper'
require 'rack/test'
require 'securerandom'
require 'rack'
require 'ddtrace'
require 'ddtrace/contrib/rack/middlewares'
require 'ddtrace/contrib/rack/rum_injection'
require 'zlib'

RSpec.describe 'Rack integration tests' do
  include Rack::Test::Methods

  let(:rack_options) { { rum_injection_enabled: true } }

  before(:each) do
    # Undo the Rack middleware name patch
    Datadog.registry[:rack].patcher::PATCHERS.each do |patcher|
      remove_patch!(patcher)
    end

    Datadog.configure do |c|
      c.use :rack, rack_options
    end
  end

  after(:each) do
    Datadog.registry[:rack].reset_configuration!
  end

  context 'for an application' do
    let(:app) do
      app_routes = routes

      Rack::Builder.new do
        use Datadog::Contrib::Rack::TraceMiddleware
        use Datadog::Contrib::Rack::RumInjection
        instance_eval(&app_routes)
      end.to_app
    end

    context 'with a basic route' do
      let(:html_response) { '<html> <head>   </head> <body> <div> ok </div> </body> </html>' }
      let(:cache_control) { 'no-store max-age=0' }
      let(:content_type) { 'text/html' }
      let(:expires) { 'Thu, 01 Dec 1994 16:00:00 GMT' }
      let(:content_length) { html_response.bytesize.to_s }
      let(:transfer_encoding) { 'identity' }
      let(:content_disposition) {}
      let(:surrogate_control) {}
      let(:base_response_headers) do
        {
          'Content-Type' => content_type,
          'Cache-Control' => cache_control,
          'ETag' => '"737060cd8c284d8af7ad3082f209582d"',
          'Expires' => expires,
          'Last-Modified' => 'Tue, 15 Nov 1994 12:45:26 GMT',
          'X-Request-ID' => 'f058ebd6-02f7-4d3f-942e-904344e8cde5',
          'X-Fake-Response' => 'Don\'t tag me.',
          'Content-Length' => content_length,
          'Surrogate-Control' => surrogate_control,
          'Content-Disposition' => content_disposition,
          'Transfer-Encoding' => transfer_encoding

        }
      end

      let(:routes) do
        # set using self. to make sure the variables can be called from proc scope
        base_response_headers = self.base_response_headers
        html_response = self.html_response
        proc do
          map '/success/' do
            run(proc do |_env|
              response_headers = base_response_headers
              [200, response_headers, [html_response]]
            end)
          end
        end
      end

      before(:each) do
        is_expected.to be_ok
        expect(spans).to have(1).items
      end

      describe 'GET request' do
        subject(:response) { get route }

        context 'without parameters' do
          let(:route) { '/success/' }

          it 'injects the html comment containing trace_id' do
            expect(response.body).to include(span.trace_id.to_s)
          end

          it 'injects the html comment containing ms precision trace-time' do
            expect(response.body).to match(/.*;trace-time=\d{13}.*/)
          end

          it 'injects an html comment containing correct identifier' do
            expect(response.body).to match(/.*DATADOG.*/)
          end
        end

        context 'with rum_cached_pages' do
          subject(:response) { get '/success?foo=bar', {} }
          let(:rack_options) { { rum_cached_pages: ['/success'], rum_injection_enabled: true } }

          it 'filters trace_id injection based on route' do
            expect(response.body).to_not include(span.trace_id.to_s)
          end
        end

        context 'with rum_injection_enabled' do
          subject(:response) { get '/success?foo=bar', {} }
          let(:rack_options) { {} }

          it 'defaults to false' do
            expect(response.body).to_not include(span.trace_id.to_s)
          end

          context 'rum_injection_enabled set to true' do
            let(:rack_options) { { rum_injection_enabled: true } }

            it 'injects trace_id when set to true' do
              expect(response.body).to include(span.trace_id.to_s)
            end
          end
        end

        context 'with Content-Type headers' do
          let(:route) { '/success/' }

          context 'context-type undefined' do
            let(:content_type) {}

            it 'does not inject trace_id when set to true' do
              expect(response.body).to_not include(span.trace_id.to_s)
            end
          end

          context 'context-type xhtml' do
            let(:content_type) { 'application/xhtml+xml' }

            it 'inject trace_id when set to xhtml' do
              expect(response.body).to include(span.trace_id.to_s)
            end
          end

          context 'context-type json' do
            let(:content_type) { 'application/json' }

            it 'does not inject trace_id when set to json' do
              expect(response.body).to_not include(span.trace_id.to_s)
            end
          end

          context 'context-type css' do
            let(:content_type) { 'application/css' }

            it 'does not inject trace_id when set to css' do
              expect(response.body).to_not include(span.trace_id.to_s)
            end
          end
        end

        # TODO: account for surrogate-control and s-maxage logic
        context 'with Cache-Control headers' do
          let(:route) { '/success/' }

          context 'cache-control no-store' do
            let(:cache_control) { 'no-store' }

            it 'inject trace_id when cache-control is no-store' do
              expect(response.body).to include(span.trace_id.to_s)
            end
          end

          context 'cache-control no-cache' do
            let(:cache_control) { 'no-cache' }

            it 'inject trace_id when cache-control is no-cache' do
              expect(response.body).to include(span.trace_id.to_s)
            end
          end

          context 'cache-control private' do
            let(:cache_control) { 'private' }

            it 'inject trace_id when cache-control is private' do
              expect(response.body).to include(span.trace_id.to_s)
            end
          end

          context 'cache-control max-age>0' do
            let(:cache_control) { 'max-age=3600' }

            it 'do not inject trace_id when cache-control is max age > 0' do
              expect(response.body).to_not include(span.trace_id.to_s)
            end
          end

          context 'cache-control max-age=0' do
            let(:cache_control) { 'max-age=0' }

            it 'inject trace_id when cache-control is max-age=0' do
              expect(response.body).to include(span.trace_id.to_s)
            end
          end

          context 'cache-control s-maxage=0' do
            let(:cache_control_base) { 's-maxage=0' }
            let(:cache_control_additional) { '' }
            let(:cache_control) { cache_control_base + cache_control_additional }

            it 'does not inject trace_id when cache-control is s-maxage=0 and no other settings exist' do
              expect(response.body).to_not include(span.trace_id.to_s)
            end

            context 'cache-control s-maxage>0' do
              let(:cache_control_base) { 's-maxage=3600' }
              it 'does not inject trace_id when cache-control s-maxage>0' do
                expect(response.body).to_not include(span.trace_id.to_s)
              end
            end

            context 'cache-control s-maxage=0,max-age=0' do
              let(:cache_control_additional) { ',max-age=0' }
              it 'inject trace_id when cache-control s-maxage=0 and (max-age=0|no-cache|no-store|private)' do
                expect(response.body).to include(span.trace_id.to_s)
              end
            end

            context 'cache-control s-maxage=0,no-store' do
              let(:cache_control_additional) { ',max-age=0' }
              it 'inject trace_id when cache-control s-maxage=0 and (max-age=0|no-cache|no-store|private)' do
                expect(response.body).to include(span.trace_id.to_s)
              end
            end

            context 'cache-control s-maxage=0,no-cache' do
              let(:cache_control_additional) { ',max-age=0' }
              it 'inject trace_id when cache-control s-maxage=0 and (max-age=0|no-cache|no-store|private)' do
                expect(response.body).to include(span.trace_id.to_s)
              end
            end

            context 'cache-control s-maxage=0,max-age=0' do
              let(:cache_control_additional) { ',private' }
              it 'inject trace_id when cache-control s-maxage=0 and (max-age=0|no-cache|no-store|private)' do
                expect(response.body).to include(span.trace_id.to_s)
              end
            end

            context 'cache-control s-maxage=0,max-age>0' do
              let(:cache_control_additional) { ',max-age=3600' }
              it 'does inject trace_id when cache-control s-maxage=0 and != (max-age=0|no-cache|no-store|private)' do
                expect(response.body).to_not include(span.trace_id.to_s)
              end
            end
          end
        end

        context 'with Surrogate-Control headers' do
          let(:route) { '/success/' }

          context 'with Surrogate-Control max-age=0' do
            let(:surrogate_control) { 'max-age=0' }

            it 'injects trace_id when Surrogate-Control is max-age=0 and cache-control is no cache as well' do
              expect(response.body).to include(span.trace_id.to_s)
            end

            context 'with Cache-Control' do
              let(:cache_control) { 'max-age>3600' }

              it 'does not inject trace_id when Surrogate-Control is max-age=0, Cache-Control max-age>0' do
                expect(response.body).to_not include(span.trace_id.to_s)
              end

              context 'cache-control max-age=0' do
                let(:cache_control) { 'max-age=0' }

                it 'inject trace_id when Surrogate-Control is max-age=0 and cache-control max-age=0' do
                  expect(response.body).to include(span.trace_id.to_s)
                end
              end

              context 'cache-control no-cache' do
                let(:cache_control) { 'no-cache' }

                it 'inject trace_id when Surrogate-Control is max-age=0 and cache-control no-cache' do
                  expect(response.body).to include(span.trace_id.to_s)
                end
              end

              context 'cache-control no-store' do
                let(:cache_control) { 'no-store' }

                it 'inject trace_id when Surrogate-Control is max-age=0 and cache-control no-store' do
                  expect(response.body).to include(span.trace_id.to_s)
                end
              end

              context 'cache-control private' do
                let(:cache_control) { 'private' }

                it 'inject trace_id when Surrogate-Control is max-age=0 and cache-control private' do
                  expect(response.body).to include(span.trace_id.to_s)
                end
              end
            end
          end

          context 'with Surrogate-Control max-age>0' do
            let(:surrogate_control) { 'max-age=360' }

            it 'does not inject trace_id when Surrogate-Control is not max-age=0' do
              expect(response.body).to_not include(span.trace_id.to_s)
            end
          end
        end

        context 'with Expires headers' do
          let(:route) { '/success/' }
          let(:cache_control) {}

          context 'with Expires=0' do
            let(:expires) { '0' }

            it 'inject trace_id when Expires is max-age=0' do
              expect(response.body).to include(span.trace_id.to_s)
            end
          end
        end

        context 'with Content-Disposition headers' do
          let(:route) { '/success/' }

          context 'with Content-Disposition=attachment' do
            let(:content_disposition) { 'attachment' }

            it 'does not inject trace_id when Content-Disposition is attachment' do
              expect(response.body).to_not include(span.trace_id.to_s)
            end
          end
        end

        context 'with Transfer-Encoding headers' do
          let(:route) { '/success/' }

          context 'with Transfer-Encoding=chunked' do
            let(:transfer_encoding) { 'chunked' }

            it 'does not inject trace_id when Content-Disposition is attachment' do
              expect(response.body).to_not include(span.trace_id.to_s)
            end
          end
        end

        context 'with Content-Length headers' do
          let(:route) { '/success/' }

          it 'updates Content-Length header when injecting new html' do
            expect(response.body).to include(span.trace_id.to_s)
            expect(response.body.bytesize.to_s).to eq(response.headers['Content-Length'])
            expect(response.body.bytesize.to_i).to be > html_response.to_s.bytesize.to_i
          end

          context 'and no trace_id injection' do
            # to force injection not to occur
            let(:cache_control) { 'public' }

            it 'does not modify Content-Length header if injection does not occur' do
              expect(response.body).to_not include(span.trace_id.to_s)
              expect(response.headers['Content-Length']).to eq(html_response.bytesize.to_s)
            end
          end
        end
      end

      describe 'Content Encoding' do
        context 'response is gzipped before it is handled by rum middleware' do
          let(:app) do
            app_routes = routes

            Rack::Builder.new do
              use Datadog::Contrib::Rack::TraceMiddleware
              use Datadog::Contrib::Rack::RumInjection
              # we need to ensure the order here fo testing, rack middelware is executed top to bottom, and nested
              # [trace -> rum -> deflater -> app -> deflater -> rum -> trace]
              use Rack::Deflater
              instance_eval(&app_routes)
            end.to_app
          end

          subject(:response) { get '/success?foo=bar', {}, 'HTTP_ACCEPT_ENCODING' => 'gzip, compress, br' }

          it 'will not inject into gzipped responses received by rum injection middleware' do
            expect(response.body).to_not include(span.trace_id.to_s)
          end
        end

        context 'response is gzipped after it is handled by rum middleware' do
          let(:app) do
            app_routes = routes

            Rack::Builder.new do
              use Datadog::Contrib::Rack::TraceMiddleware
              # This is how rack setup should occur
              # [trace -> rum -> deflater -> app -> deflater -> rum -> trace]
              use Rack::Deflater
              use Datadog::Contrib::Rack::RumInjection
              instance_eval(&app_routes)
            end.to_app
          end

          subject(:response) { get '/success?foo=bar', {}, 'HTTP_ACCEPT_ENCODING' => 'gzip, compress, br' }

          it 'inject trace_id into responses recd by middleware that is not yet gzipped by downstream middleware' do
            gzipped_response = response.body

            # from https://github.com/rack/rack/blob/ab41dccfe287b7d2589778308cb297eb039e88c6/test/spec_deflater.rb#L67
            io = StringIO.new(gzipped_response)
            gz = Zlib::GzipReader.new(io)
            tmp = gz.read
            gz.close
            readable_body = tmp
            expect(readable_body).to include(span.trace_id.to_s)
          end
        end
      end
    end
  end
end
