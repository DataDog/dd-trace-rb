# typed: false

require 'spec_helper'
require 'datadog/profiling/spec_helper'

require 'datadog/profiling/encoding/profile'
require 'datadog/profiling/flush'
require 'datadog/profiling/transport/http/api/endpoint'
require 'datadog/profiling/transport/http/response'
require 'datadog/profiling/transport/request'
require 'ddtrace/transport/http/env'

RSpec.describe Datadog::Profiling::Transport::HTTP::API::Endpoint do
  subject(:endpoint) { described_class.new(path, encoder) }

  let(:path) { double('path') }
  let(:encoder) { class_double(Datadog::Profiling::Encoding::Profile::Protobuf) }

  describe '#initialize' do
    it do
      is_expected.to have_attributes(
        verb: :post,
        path: path,
        encoder: encoder
      )
    end
  end

  describe '#call' do
    subject(:call) { endpoint.call(env, &block) }

    shared_examples_for 'profile request' do
      let(:env) { Datadog::Transport::HTTP::Env.new(request) }
      let(:request) { Datadog::Profiling::Transport::Request.new(flush) }
      let(:flush) { get_test_profiling_flush }

      let(:pprof) { instance_double(Datadog::Profiling::Pprof::Payload, data: data) }
      let(:data) { 'pprof_string_data' }
      let(:http_response) { instance_double(Datadog::Profiling::Transport::HTTP::Response) }

      let(:block) do
        proc do
          http_response
        end
      end

      before do
        allow(encoder).to receive(:encode)
          .with(flush)
          .and_return(pprof)
      end

      it 'fills the env with data' do
        is_expected.to be_a(Datadog::Profiling::Transport::HTTP::Response)
        expect(env.verb).to be(:post)
        expect(env.path).to be(path)
        expect(env.body).to be nil
        expect(env.headers).to eq({})

        expect(env.form).to include(
          'version' => '3',
          'data[rubyprofile.pprof]' => kind_of(Datadog::Core::Vendor::Multipart::Post::UploadIO),
          'start' => flush.start.utc.iso8601,
          'end' => flush.finish.utc.iso8601,
          'family' => flush.language,
          'tags' => array_including(
            "runtime:#{flush.language}",
            "runtime-id:#{flush.runtime_id}",
            "runtime_engine:#{flush.runtime_engine}",
            "runtime_platform:#{flush.runtime_platform}",
            "runtime_version:#{flush.runtime_version}",
            "pid:#{Process.pid}",
            "profiler_version:#{flush.profiler_version}",
            "language:#{flush.language}",
            "host:#{flush.host}"
          )
        )
      end
    end

    context 'by default' do
      it_behaves_like 'profile request'
    end

    context 'when code provenance data is available' do
      it_behaves_like 'profile request' do
        let(:code_provenance) { 'code_provenance_json' }

        let(:flush) { get_test_profiling_flush(code_provenance: code_provenance) }

        it 'includes code provenance data in the form' do
          call

          expect(env.form)
            .to include('data[code-provenance.json]' => kind_of(Datadog::Core::Vendor::Multipart::Post::UploadIO))
        end
      end
    end

    context 'when additional tags are provided' do
      it_behaves_like 'profile request' do
        let(:tags) { { 'test_tag_key' => 'test_tag_value', 'another_tag_key' => :another_tag_value } }

        before do
          flush.tags = tags
        end

        it 'reports the additional tags as part of the tags field' do
          call

          expect(env.form).to include('tags' => array_including(
            'test_tag_key:test_tag_value', 'another_tag_key:another_tag_value'
          ))
        end
      end
    end

    context 'when service/env/version are available' do
      let(:service) { 'test-service' }
      let(:env_name) { 'test-env' }
      let(:version) { '1.2.3' }

      it_behaves_like 'profile request' do
        before do
          flush.service = service
          flush.env = env_name
          flush.version = version
        end

        it 'includes service/env/version as tags' do
          call
          expect(env.form).to include(
            'tags' => array_including(
              "service:#{flush.service}",
              "env:#{flush.env}",
              "version:#{flush.version}"
            )
          )
        end

        context 'when service/env/version were configured via tags' do
          # NOTE: In normal operation, flush.tags SHOULD never be different from flush.service/env/version because we set
          # the service/env/version in the settings object from the tags if they are available (see settings.rb).
          # But simulating them being different here makes it easier to test that no duplicates are added -- that
          # effectively the tag versions are ignored and we only include the top-level flush versions.
          let(:tags) do
            { 'service' => 'service_tag', 'env' => 'env_tag', 'version' => 'version_tag',
              'some_other_tag' => 'some_other_value' }
          end

          before do
            flush.tags = tags
          end

          it 'includes the flush.service / flush.env / flush.version values for these tags' do
            call

            expect(env.form).to include(
              'tags' => array_including(
                "service:#{flush.service}",
                "env:#{flush.env}",
                "version:#{flush.version}"
              )
            )
          end

          it 'does not include the values for these tags from the flush.tags hash' do
            call

            expect(env.form.fetch('tags')).to_not include('service:service_tag', 'env:env_tag', 'version:version_tag')
          end

          it 'includes other defined tags' do
            call

            expect(env.form.fetch('tags')).to include('some_other_tag:some_other_value')
          end
        end
      end
    end
  end
end
