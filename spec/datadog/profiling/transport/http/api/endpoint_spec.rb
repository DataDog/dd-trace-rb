# typed: false

require 'spec_helper'
require 'datadog/profiling/spec_helper'

require 'datadog/profiling/stack_recorder'
require 'datadog/profiling/exporter'
require 'datadog/profiling/collectors/code_provenance'

require 'datadog/profiling/encoding/profile'
require 'datadog/profiling/flush'
require 'datadog/profiling/transport/http/api/endpoint'
require 'datadog/profiling/transport/http/response'
require 'ddtrace/transport/http/env'

RSpec.describe Datadog::Profiling::Transport::HTTP::API::Endpoint do
  subject(:endpoint) { described_class.new(path) }

  let(:path) { double('path') }

  describe '#initialize' do
    it do
      is_expected.to have_attributes(
        verb: :post,
        path: path,
      )
    end
  end

  describe '#call' do
    subject(:call) { endpoint.call(env, &block) }

    shared_examples_for 'profile request' do
      let(:env) { Datadog::Transport::HTTP::Env.new(flush) }
      let(:flush) { get_test_profiling_flush }

      let(:http_response) { instance_double(Datadog::Profiling::Transport::HTTP::Response) }

      let(:block) do
        proc do
          http_response
        end
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
          'family' => get_flush_tag('language'),
          'tags' => array_including(
            "runtime:#{get_flush_tag('language')}",
            "runtime-id:#{get_flush_tag('runtime-id')}",
            "runtime_engine:#{get_flush_tag('runtime_engine')}",
            "runtime_platform:#{get_flush_tag('runtime_platform')}",
            "runtime_version:#{get_flush_tag('runtime_version')}",
            "process_id:#{Process.pid}",
            "profiler_version:#{get_flush_tag('profiler_version')}",
            "language:#{get_flush_tag('language')}",
            "host:#{get_flush_tag('host')}"
          )
        )
      end

      def get_flush_tag(tag)
        flush.tags_as_array.find { |key, _| key == tag }.last
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
          flush.tags_as_array.push(*tags.to_a)
        end

        it 'reports the additional tags as part of the tags field' do
          call

          expect(env.form).to include('tags' => array_including(
            'test_tag_key:test_tag_value', 'another_tag_key:another_tag_value'
          ))
        end
      end
    end
  end

  def get_test_profiling_flush(code_provenance: nil)
    start = Time.now.utc
    finish = start + 10

    pprof_recorder = instance_double(
      Datadog::Profiling::StackRecorder,
      serialize: [start, finish, 'fake_compressed_encoded_pprof_data'],
    )

    code_provenance_collector =
      if code_provenance
        instance_double(Datadog::Profiling::Collectors::CodeProvenance, generate_json: code_provenance).tap do |it|
          allow(it).to receive(:refresh).and_return(it)
        end
      end

    Datadog::Profiling::Exporter.new(
      pprof_recorder: pprof_recorder,
      code_provenance_collector: code_provenance_collector,
    ).flush
  end
end
