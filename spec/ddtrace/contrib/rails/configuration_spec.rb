require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails configuration' do
  include_context 'Rails test application'

  let(:routes) { { '/' => 'test#index' } }
  let(:controllers) { [controller] }

  let(:controller) do
    stub_const('TestController', Class.new(ActionController::Base) do
      def index
        head :ok
      end
    end)
  end

  let(:tracer) { get_test_tracer }

  before do
    allow(Datadog.configuration).to receive(:use).and_call_original
    allow(Datadog.configuration).to receive(:set).and_call_original
  end

  around do |example|
    targets = [:rails] + Datadog::Contrib::Rails::Configuration::Settings::COMPONENTS

    # Reset before and after each example; don't allow global state to linger.
    targets.each { |t| Datadog.registry[t].reset_configuration! }
    example.run
    targets.each { |t| Datadog.registry[t].reset_configuration! }
  end

  describe 'for ActiveRecord' do
    let(:rails_config) { Datadog.configuration[:rails] }
    let(:active_record_config) { Datadog.configuration[:active_record] }

    context 'by default' do
      before do
        Datadog.configure do |c|
          c.use :rails
        end
      end

      it 'is activated with default settings' do
        # Load the app
        app

        expect(Datadog.configuration).to have_received(:use)
          .with(:active_record, *any_args)

        # Assert default settings
        expect(active_record_config.service_name).to eq(rails_config.database_service)
        expect(active_record_config.tracer).to eq(rails_config.tracer)
      end
    end

    context 'when set to false' do
      before do
        Datadog.configure do |c|
          c.use :rails do |rails|
            rails.active_record false
          end
        end
      end

      it 'prevents ActiveRecord from being configured or patched' do
        # Load the app
        app

        expect(Datadog.configuration).to_not have_received(:use)
          .with(:active_record, *any_args)

        expect(Datadog.configuration).to_not have_received(:set)
          .with(:active_record, *any_args)
      end
    end

    context 'when set to true' do
      before do
        Datadog.configure do |c|
          c.use :rails do |rails|
            rails.active_record true
          end
        end
      end

      it 'activates ActiveRecord instrumentation with default settings' do
        # Load the app
        app

        expect(Datadog.configuration).to have_received(:use)
          .with(:active_record, *any_args)

        # Assert default settings
        expect(active_record_config.service_name).to eq(rails_config.database_service)
        expect(active_record_config.tracer).to eq(rails_config.tracer)
      end
    end

    context 'when given options' do
      let(:options) { { service_name: service_name } }
      let(:service_name) { double('ActiveRecord service name') }

      before do
        Datadog.configure do |c|
          c.use :rails do |rails|
            rails.active_record options
          end
        end
      end

      it 'activates ActiveRecord instrumentation with given settings' do
        # Load the app
        app

        expect(Datadog.configuration).to have_received(:use)
          .with(:active_record, *any_args)

        # Applies the default settings with options as overrides
        expect(active_record_config.service_name).to eq(service_name)
        expect(active_record_config.tracer).to eq(rails_config.tracer)
      end
    end

    context 'when given a block' do
      let(:service_name) { double('ActiveRecord service name') }

      context 'with simple settings' do
        before do
          Datadog.configure do |c|
            c.use :rails do |rails|
              rails.active_record do |active_record|
                active_record.service_name = service_name
              end
            end
          end
        end

        it 'activates ActiveRecord instrumentation with default settings' do
          # Load the app
          app

          expect(Datadog.configuration).to have_received(:use)
            .with(:active_record, *any_args)

          # Applies the default settings with block as override
          expect(active_record_config.service_name).to eq(service_name)
          expect(active_record_config.tracer).to eq(rails_config.tracer)
        end
      end

      context 'that depends on Rails settings already being available' do
        before do
          Datadog.configure do |c|
            c.use :rails do |rails|
              rails.active_record do |active_record|
                active_record.service_name = "#{rails.service_name}-#{service_name}"
              end
            end
          end
        end

        it 'activates ActiveRecord instrumentation with given settings' do
          # Load the app
          app

          expect(Datadog.configuration).to have_received(:use)
            .with(:active_record, *any_args)

          # Applies the default settings with block as override
          expect(active_record_config.service_name).to eq("#{rails_config.service_name}-#{service_name}")
          expect(active_record_config.tracer).to eq(rails_config.tracer)
        end
      end
    end

    context 'when given multiple blocks that describe different databases' do
      let(:primary_service_name) { double('ActiveRecord primary service name') }
      let(:secondary_service_name) { double('ActiveRecord secondary service name') }

      before do
        # Stub ActiveRecord::Base, to pretend its been configured
        allow(ActiveRecord::Base).to receive(:configurations).and_return(
          'test' => {
            'adapter' => 'sqlite3',
            'pool' => 5,
            'timeout' => 5000,
            'database' => ':memory:'
          },
          'primary' => {
            'adapter' => 'sqlite3',
            'pool' => 5,
            'timeout' => 5000,
            'database' => ':memory_b:'
          },
          'secondary' => {
            'adapter' => 'sqlite3',
            'pool' => 5,
            'timeout' => 5000,
            'database' => ':memory_c:'
          }
        )

        Datadog.configure do |c|
          c.use :rails do |rails|
            rails.tracer = tracer

            rails.active_record describes: :primary do |primary|
              puts "\nPrimary: #{primary.object_id}\n"
              primary.service_name = primary_service_name
            end

            rails.active_record describes: :secondary do |secondary|
              puts "\nSecondary: #{secondary.object_id}\n"
              secondary.service_name = secondary_service_name
            end
          end
        end
      end

      it 'activates ActiveRecord instrumentation for each database with given settings' do
        # Load the app
        app

        expect(Datadog.configuration).to have_received(:use)
          .with(:active_record, *any_args)

        # Applies the default settings to default config
        expect(active_record_config.service_name).to eq(rails_config.database_service)
        expect(active_record_config.tracer).to be(tracer)

        # Applies the default settings with overrides to primary DB
        Datadog.configuration[:active_record, :primary].tap do |primary|
          expect(primary.service_name).to eq(primary_service_name)
          expect(primary.tracer).to be(tracer)
        end

        # Applies the default settings with overrides to secondary DB
        Datadog.configuration[:active_record, :secondary].tap do |secondary|
          expect(secondary.service_name).to eq(secondary_service_name)
          expect(secondary.tracer).to be(tracer)
        end
      end
    end
  end
end
