RSpec.describe 'Single step instrument', skip: !Process.respond_to?(:fork) do
  it do
    expect_in_fork do
      expect_any_instance_of(Object)
        .to receive(:require_relative).with('auto_instrument').and_raise(LoadError)

      expect do
        load 'datadog/single_step_instrument.rb'
      end.to output(/Single step instrumentation failed/).to_stderr
    end
  end

  it do
    expect_in_fork do
      expect_any_instance_of(Object)
        .to receive(:require_relative).with('auto_instrument').and_raise(StandardError)

      expect do
        load 'datadog/single_step_instrument.rb'
      end.to output(/Single step instrumentation failed/).to_stderr
    end
  end
end

RSpec.describe 'LOADED variable' do
  subject(:single_step_instrument) { load 'datadog/single_step_instrument.rb' }

  before do
    # Store the original state if needed
    @original_loaded = defined?(Datadog::SingleStepInstrument::LOADED) ? Datadog::SingleStepInstrument::LOADED : nil
  end

  after do
    # Remove the constant to clean up
    Datadog::SingleStepInstrument.send(:remove_const, :LOADED) if defined?(Datadog::SingleStepInstrument::LOADED)

    # If the entire module was created by the load, remove it too
    Datadog.send(:remove_const, :SingleStepInstrument) if defined?(Datadog::SingleStepInstrument)
  end

  it do
    single_step_instrument
    expect(Datadog::SingleStepInstrument::LOADED).to eq(true)
  end
end
