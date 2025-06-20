RSpec.describe 'Single step instrument', skip: !Process.respond_to?(:fork) do
  subject(:single_step_instrument) { load 'datadog/single_step_instrument.rb' }

  before do
    # Store the original state if needed
    @original_single_step_instrument = defined?(Datadog::SingleStepInstrument) ? Datadog::SingleStepInstrument : nil
  end

  after do
    # Remove the constant to clean up
    Datadog::SingleStepInstrument.send(:remove_const, :LOADED) if defined?(Datadog::SingleStepInstrument::LOADED)

    # If the entire module was created by the load, remove it too
    Datadog.send(:remove_const, :SingleStepInstrument) if defined?(Datadog::SingleStepInstrument)

    # Restore original state if it existed
    Datadog.const_set(:SingleStepInstrument, @original_single_step_instrument) if @original_single_step_instrument
  end

  it do
    expect_in_fork do
      expect_any_instance_of(Object)
        .to receive(:require_relative).with('auto_instrument').and_raise(LoadError)

      expect do
        single_step_instrument
      end.to output(/Single step instrumentation failed/).to_stderr
    end
  end

  it do
    expect_in_fork do
      expect_any_instance_of(Object)
        .to receive(:require_relative).with('auto_instrument').and_raise(StandardError)

      expect do
        single_step_instrument
      end.to output(/Single step instrumentation failed/).to_stderr
    end
  end

  it 'LOADED variable' do
    single_step_instrument
    expect(Datadog::SingleStepInstrument::LOADED).to eq(true)
  end
end
