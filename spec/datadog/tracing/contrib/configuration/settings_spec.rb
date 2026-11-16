require "datadog/tracing/contrib/support/spec_helper"

require "datadog"

RSpec.describe Datadog::Tracing::Contrib::Configuration::Settings do
  subject(:settings) { described_class.new }

  it { is_expected.to be_a_kind_of(Datadog::Core::Configuration::Base) }

  describe "#service_name" do
    subject(:service_name) { settings.service_name }

    it { expect(settings.service_name).to be nil }
    it { expect(settings[:service_name]).to be nil }
  end

  describe "#analytics_enabled" do
    subject(:analytics_enabled) { settings.analytics_enabled }

    it { expect(settings.analytics_enabled).to be false }
    it { expect(settings[:analytics_enabled]).to be false }
  end

  describe "#analytics_sample_rate" do
    subject(:analytics_sample_rate) { settings.analytics_sample_rate }

    it { expect(settings.analytics_sample_rate).to eq 1.0 }
    it { expect(settings[:analytics_sample_rate]).to eq 1.0 }
  end

  describe "#configure" do
    subject(:configure) { settings.configure(options) }

    context "given an option" do
      let(:options) { {service_name: service_name} }
      let(:service_name) { "service_name" }

      before { allow(settings).to receive(:set_option).and_call_original }

      it "doesn't initialize other options" do
        expect { configure }
          .to change { settings.service_name }
          .from(nil)
          .to(service_name)

        expect(settings).to_not have_received(:set_option).with(:tracer, any_args)
      end
    end
  end

  describe "#copy_configured_options" do
    subject(:copy_configured_options) { target_settings.copy_configured_options(source_settings, [:example_option]) }

    let(:source_settings) do
      Class.new(described_class) do
        option :example_option do |o|
          o.type :string
          o.env "TEST_ENV_VAR"
          o.default "default value"
        end
      end.new
    end

    let(:target_settings) do
      Class.new(described_class) do
        option :example_option do |o|
          o.type :string
          o.default "default value"
        end
      end.new
    end

    context "when the source option is at its default" do
      before { target_settings.example_option = "target value" }

      it "leaves the target option unchanged" do
        expect { copy_configured_options }.to_not(change { target_settings.example_option })
      end
    end

    context "when the source option is set in code" do
      before { source_settings.example_option = "source value" }

      context "and the target option is at its default" do
        it "copies the value" do
          expect { copy_configured_options }
            .to change { target_settings.example_option }.from("default value").to("source value")
        end
      end

      context "and the target option is set in code" do
        before { target_settings.example_option = "target value" }

        it "replaces the target value" do
          expect { copy_configured_options }
            .to change { target_settings.example_option }.from("target value").to("source value")
        end
      end
    end

    context "when the source option is set by environment variable" do
      with_env "TEST_ENV_VAR" => "source value"

      context "and the target option is at its default" do
        it "copies the value" do
          expect { copy_configured_options }
            .to change { target_settings.example_option }.from("default value").to("source value")
        end
      end

      context "and the target option is set in code" do
        before { target_settings.example_option = "target value" }

        it "leaves the target value set in code" do
          expect { copy_configured_options }.to_not(change { target_settings.example_option })
        end
      end
    end
  end
end
