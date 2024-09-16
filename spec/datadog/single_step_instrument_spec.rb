RSpec.describe 'Single step instrument' do
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
