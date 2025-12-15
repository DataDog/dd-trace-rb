require "datadog/profiling/collectors/code_provenance"
require "json-schema"
require "json"
require "yaml"
require "datadog/profiling/spec_helper"

RSpec.describe Datadog::Profiling::Collectors::CodeProvenance do
  before { skip_if_profiling_not_supported(self) }

  subject(:code_provenance) { described_class.new(ruby_native_filename: ruby_native_filename) }

  let(:ruby_native_filename) { "" }

  let(:generate_result) do
    JSON.parse(code_provenance.generate_json, symbolize_names: true).fetch(:v1)
  end

  describe "#refresh" do
    subject(:refresh) { code_provenance.refresh }

    it "records libraries that are currently loaded" do
      refresh

      expect(generate_result).to include(
        {
          kind: "standard library",
          name: "stdlib",
          version: RUBY_VERSION.to_s,
          paths: contain_exactly(start_with("/")),
        },
        {
          kind: "library",
          name: "datadog",
          version: Datadog::VERSION::STRING,
          paths: contain_exactly(
            start_with("/"),
            include("extensions").and(include(RUBY_PLATFORM)),
            "#{Gem.bindir}/ddprofrb",
            "#{Bundler.bin_path}/ddprofrb",
          ),
        },
        {
          kind: "library",
          name: "rspec",
          version: start_with("3."), # This will one day need to be bumped for RSpec 4
          paths: contain_exactly(start_with("/")),
        },
      )
    end

    it "includes the native extension directory for gems with native extensions" do
      refresh

      expect(generate_result.find { |it| it[:name] == "msgpack" }).to include(
        {
          kind: "library",
          name: "msgpack",
          version: MessagePack::VERSION,
          paths: contain_exactly(
            satisfy { |it| it.start_with?(Gem.dir) && !it.include?("extensions") },
            include("extensions").and(include(RUBY_PLATFORM)),
          ),
        }
      )
    end

    it "includes the executables for gems with executables" do
      refresh

      expect(generate_result.find { |it| it[:name] == "rspec-core" }.fetch(:paths)).to contain_exactly(
        Gem.loaded_specs.fetch("rspec-core").gem_dir,
        "#{Gem.bindir}/rspec",
        "#{Bundler.bin_path}/rspec",
      )

      # Sanity checks
      expect(Gem.bindir).to start_with("/")
      expect(Bundler.bin_path.to_s).to start_with("/")
    end

    it "records the correct path for datadog" do
      refresh

      current_file_directory = __dir__
      datadog_gem_root_directory = generate_result.find { |lib| lib.fetch(:name) == "datadog" }.fetch(:paths).first

      expect(current_file_directory).to start_with(datadog_gem_root_directory)
    end

    it "skips libraries not present in the loaded files" do
      code_provenance.refresh(
        loaded_files: ["/is_loaded/is_loaded.rb"],
        loaded_specs: [
          instance_double(
            Gem::Specification,
            name: "not_loaded",
            version: "not_loaded_version",
            gem_dir: "/not_loaded/",
            extensions: [],
            executables: [],
          ),
          instance_double(
            Gem::Specification,
            name: "is_loaded",
            version: "is_loaded_version",
            gem_dir: "/is_loaded/",
            extensions: [],
            executables: [],
          )
        ],
      )

      expect(generate_result).to have(1).item
      expect(generate_result.first).to match(
        kind: "library",
        name: "is_loaded",
        version: "is_loaded_version",
        paths: contain_exactly("/is_loaded/"),
      )
    end

    context "#bundler_bin_path" do
      let(:bundler_bin_path) { code_provenance.send(:bundler_bin_path) }

      it 'matches Bundler.bin_path' do
        expect(bundler_bin_path).to eq(Bundler.bin_path.to_s)
      end

      context 'when an exception gets raised' do
        before do
          allow(Bundler).to receive(:root).and_raise(Exception.new("test exception"))
        end

        it 'logs a debug message' do
          expect(Datadog.logger).to receive(:debug).with(/CodeProvenance#bundler_bin_path failed/)

          bundler_bin_path
        end

        it 'returns nil' do
          allow(Datadog.logger).to receive(:debug)

          expect(bundler_bin_path).to be_nil
        end
      end
    end

    context "when a native ruby filename is provided" do
      let(:ruby_native_filename) { "/some/path/to/libruby.so.1.2.3" }

      it "records the native ruby filename" do
        refresh

        expect(generate_result).to include(
          kind: "standard library",
          name: "stdlib",
          version: RUBY_VERSION.to_s,
          paths: contain_exactly(start_with("/"), ruby_native_filename),
        )
      end
    end

    it "returns self" do
      expect(code_provenance.refresh).to be code_provenance
    end

    context "when a gem's path is inside another gem's path" do
      # I'm not entirely sure if this can happen in end-user apps, but can happen in CI if bundler is configured to
      # install dependencies into a subfolder of datadog. In particular GitHub Actions does this.

      it "matches the loaded file to the longest matching path" do
        code_provenance.refresh(
          loaded_files: ["/dd-trace-rb/vendor/bundle/ruby/2.7.0/gems/byebug-11.1.3/lib/byebug.rb"],
          loaded_specs: [
            instance_double(
              Gem::Specification,
              name: "datadog",
              version: "1.2.3",
              gem_dir: "/dd-trace-rb",
              extensions: [],
              executables: [],
            ),
            instance_double(
              Gem::Specification,
              name: "byebug",
              version: "4.5.6",
              gem_dir: "/dd-trace-rb/vendor/bundle/ruby/2.7.0/gems/byebug-11.1.3",
              extensions: [],
              executables: [],
            )
          ],
        )

        expect(generate_result).to have(1).item
        expect(generate_result.first).to match(hash_including(name: "byebug"))
      end
    end
  end

  describe "#generate_json" do
    before { code_provenance.refresh }

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

    it "renders the list of loaded libraries as json" do
      expect(generate_result).to include(
        {
          name: "stdlib",
          kind: "standard library",
          version: RUBY_VERSION.to_s,
          paths: include(start_with("/")),
        },
        {
          name: "datadog",
          kind: "library",
          version: Datadog::VERSION::STRING,
          paths: include(start_with("/")),
        },
        {
          name: "rspec-core",
          kind: "library",
          version: start_with("3."), # This will one day need to be bumped for RSpec 4
          paths: include(start_with("/")),
        },
      )
    end

    it "renders the list of loaded libraries using the expected schema" do
      JSON::Validator.validate!(code_provenance_schema, code_provenance.generate_json)
    end

    # In PROF-9821 we run into an issue where some versions of OJ + activesupport + monkey patching the JSON gem
    # would result in our Library instance being encoded instance-field-by-instance-field instead of by calling #to_json.
    #
    # This would obviously result in broken code provenance files. To fix this, we've adjusted the class to make sure
    # that if you serialize it field-by-field, you still get a correct result.
    #
    # Reproducing this exact issue in CI is really annoying -- because it would be one more set of appraisails we'd run
    # just to reproduce it and test.
    #
    # So instead in this test we use YAML as an example of an encoder that doesn't use #to_json, and does it
    # field-by-field. Thus if the Library class doesn't match exactly what we want in the output, this test will fail.
    #
    # In case you want to reproduce the exact JSON issue, here's a reproducer:
    # ````ruby
    # require 'bundler/inline'
    #
    # gemfile do
    #   source 'https://rubygems.org'
    #   gem 'activesupport', '= 5.0.7.2'
    #   gem 'oj', '= 2.18.5'
    # end
    #
    # require 'json'
    #
    # class Example
    #   def initialize = @hello = 1
    #   def to_json(arg = nil) = {world: 2}.to_json(arg)
    # end
    #
    # example = Example.new
    # puts JSON.generate(example)
    #
    # require 'oj'
    # require 'active_support/core_ext/object/json'
    # Oj.mimic_JSON()
    #
    # puts JSON.generate(example)
    # ```
    #
    # Incorrect output:
    # {"world":2}
    # {"hello":1}
    #
    describe "when JSON encoder is broken and skips #to_json" do
      let(:library_class_without_to_json) do
        Class.new(Datadog::Profiling::Collectors::CodeProvenance::Library) do
          undef to_json
        end
      end

      it "is still able to correctly encode a library instance" do
        instance = library_class_without_to_json.new(
          name: "datadog",
          kind: "library",
          version: "1.2.3",
          path: "/example/path/to/datadog/gem",
          extra_paths: ["/example/path/to/datadog/extensions"],
        )

        serialized_without_to_json = YAML.dump(instance)
        # Remove class annotation, so it deserializes back as a hash and not an instance of our class
        serialized_without_to_json.gsub!(/---.*/, "---")

        expect(YAML.safe_load(serialized_without_to_json)).to eq(
          "name" => "datadog",
          "kind" => "library",
          "version" => "1.2.3",
          "paths" => ["/example/path/to/datadog/gem", "/example/path/to/datadog/extensions"],
        )
      end
    end
  end
end
