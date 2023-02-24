require 'datadog/profiling/collectors/code_provenance'
require 'json-schema'

RSpec.describe Datadog::Profiling::Collectors::CodeProvenance do
  subject(:code_provenance) { described_class.new }

  describe '#refresh' do
    subject(:refresh) { code_provenance.refresh }

    it 'records libraries that are currently loaded' do
      refresh

      expect(code_provenance.generate).to include(
        have_attributes(
          kind: 'standard library',
          name: 'stdlib',
          version: RUBY_VERSION.to_s,
          path: start_with('/'),
        ),
        have_attributes(
          kind: 'library',
          name: 'ddtrace',
          version: DDTrace::VERSION::STRING,
          path: start_with('/'),
        ),
        have_attributes(
          kind: 'library',
          name: 'rspec-core',
          version: start_with('3.'), # This will one day need to be bumped for RSpec 4
          path: start_with('/'),
        )
      )
    end

    it 'records the correct path for ddtrace' do
      refresh

      current_file_directory = __dir__
      dd_trace_root_directory = code_provenance.generate.find { |lib| lib.name == 'ddtrace' }.path

      expect(current_file_directory).to start_with(dd_trace_root_directory)
    end

    it 'skips libraries not present in the loaded files' do
      code_provenance.refresh(
        loaded_files: ['/is_loaded/is_loaded.rb'],
        loaded_specs: [
          instance_double(
            Gem::Specification,
            name: 'not_loaded',
            version: 'not_loaded_version',
            gem_dir: '/not_loaded/'
          ),
          instance_double(
            Gem::Specification,
            name: 'is_loaded',
            version: 'is_loaded_version',
            gem_dir: '/is_loaded/'
          )
        ],
      )

      expect(code_provenance.generate).to have(1).item
      expect(code_provenance.generate.first).to have_attributes(
        name: 'is_loaded',
        version: 'is_loaded_version',
        path: '/is_loaded/',
        kind: 'library',
      )
    end

    it 'returns self' do
      expect(code_provenance.refresh).to be code_provenance
    end

    context "when a gem's path is inside another gem's path" do
      # I'm not entirely sure if this can happen in end-user apps, but can happen in CI if bundler is configured to
      # install dependencies into a subfolder of ddtrace. In particular GitHub Actions does this.

      it 'matches the loaded file to the longest matching path' do
        code_provenance.refresh(
          loaded_files: ['/dd-trace-rb/vendor/bundle/ruby/2.7.0/gems/byebug-11.1.3/lib/byebug.rb'],
          loaded_specs: [
            instance_double(
              Gem::Specification,
              name: 'ddtrace',
              version: '1.2.3',
              gem_dir: '/dd-trace-rb'
            ),
            instance_double(
              Gem::Specification,
              name: 'byebug',
              version: '4.5.6',
              gem_dir: '/dd-trace-rb/vendor/bundle/ruby/2.7.0/gems/byebug-11.1.3'
            )
          ],
        )

        expect(code_provenance.generate).to have(1).item
        expect(code_provenance.generate.first).to have_attributes(name: 'byebug')
      end
    end
  end

  describe '#generate_json' do
    before do
      code_provenance.refresh
    end

    let(:code_provenance_schema) do
      %(
        {
            "type": "object",
            "required": [
                "v1"
            ],
            "properties": {
                "v1": {
                    "type": "array",
                    "additionalItems": true,
                    "items": {
                        "anyOf": [
                            {
                                "type": "object",
                                "required": [
                                    "kind",
                                    "name",
                                    "version",
                                    "paths"
                                ],
                                "properties": {
                                    "kind": {
                                        "type": "string"
                                    },
                                    "name": {
                                        "type": "string"
                                    },
                                    "version": {
                                        "type": "string"
                                    },
                                    "paths": {
                                        "type": "array",
                                        "additionalItems": true,
                                        "items": {
                                            "anyOf": [
                                                {
                                                    "type": "string"
                                                }
                                            ]
                                        }
                                    }
                                },
                                "additionalProperties": true
                            }
                        ]
                    }
                }
            },
            "additionalProperties": true
        }
      ).freeze
    end

    it 'renders the list of loaded libraries as json' do
      expect(JSON.parse(code_provenance.generate_json).fetch('v1')).to include(
        hash_including(
          'name' => 'stdlib',
          'kind' => 'standard library',
          'version' => RUBY_VERSION.to_s,
          'paths' => include(start_with('/')),
        ),
        hash_including(
          'name' => 'ddtrace',
          'kind' => 'library',
          'version' => DDTrace::VERSION::STRING,
          'paths' => include(start_with('/')),
        ),
        hash_including(
          'name' => 'rspec-core',
          'kind' => 'library',
          'version' => start_with('3.'), # This will one day need to be bumped for RSpec 4
          'paths' => include(start_with('/')),
        )
      )
    end

    it 'renders the list of loaded libraries using the expected schema' do
      JSON::Validator.validate!(code_provenance_schema, code_provenance.generate_json)
    end
  end
end
