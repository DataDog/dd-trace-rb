require 'spec_helper'
require 'ddtrace/profiling/spec_helper'

require 'ddtrace/profiling/encoding/profile'
require 'ddtrace/profiling/flush'
require 'ddtrace/profiling/transport/http/api/endpoint'
require 'ddtrace/profiling/transport/http/response'
require 'ddtrace/profiling/transport/request'
require 'ddtrace/transport/http/env'

# rubocop:disable Metrics/LineLength
RSpec.describe Datadog::Profiling::Transport::HTTP::API::Endpoint do
  subject(:endpoint) { described_class.new(path, encoder, options) }
  let(:path) { double('path') }
  let(:encoder) { class_double(Datadog::Profiling::Encoding::Profile::Protobuf) }
  let(:options) { {} }

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

      let(:pprof) { instance_double(Datadog::Profiling::Pprof::Payload, data: data, types: types) }
      let(:data) { 'pprof_string_data' }
      let(:types) { [:wall_time_ns] }
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
          Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_DATA => kind_of(Datadog::Vendor::Multipart::Post::UploadIO),
          Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_FORMAT => Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_FORMAT_PPROF,
          Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_RECORDING_START => flush.start.utc.iso8601,
          Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_RECORDING_END => flush.finish.utc.iso8601,
          Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_RUNTIME => flush.runtime,
          Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_RUNTIME_ID => flush.runtime_id,
          Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAGS => array_including(
            "#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_RUNTIME}:#{flush.runtime}",
            "#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_RUNTIME_VERSION}:#{flush.runtime_version}",
            "#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_PROFILER_VERSION}:#{flush.profiler_version}",
            "#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_LANGUAGE}:#{flush.language}",
            "#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_HOST}:#{flush.host}"
          )
        )
      end
    end

    context 'by default' do
      it_behaves_like 'profile request'
    end

    context 'when additional env tags are available' do
      let(:service) { 'test-service' }
      let(:env_name) { 'test-env' }
      let(:version) { '1.2.3' }

      it_behaves_like 'profile request' do
        before do
          flush.service = service
          flush.env = env_name
          flush.version = version
        end

        it 'includes env tags' do
          call
          expect(env.form).to include(
            Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAGS => array_including(
              "#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_SERVICE}:#{flush.service}",
              "#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_ENV}:#{flush.env}",
              "#{Datadog::Ext::Profiling::Transport::HTTP::FORM_FIELD_TAG_VERSION}:#{flush.version}"
            )
          )
        end
      end
    end

    context 'when the pprof contains wall & CPU time types' do
      it_behaves_like 'profile request' do
        let(:types) { [:wall_time_ns, :cpu_time_ns] }

        it 'includes env tags' do
          call
          expect(env.form).to include(
            'types[0]' => 'wall_time_ns,ruby-cpu'
          )
        end
      end
    end
  end
end
