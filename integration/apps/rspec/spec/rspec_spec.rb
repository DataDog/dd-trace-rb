# Test some RSpec behavior
# NOTE: This file is expected to always produce some test errors!
#       So that we can 
RSpec.describe 'RSpec behavior' do
  shared_examples_for 'correct behavior' do
    it 'passes' do
      expect(1).to be < 2
    end
  end
  
  shared_examples_for 'incorrect behavior' do
    it 'fails' do
      expect(2).to be < 1
    end
  end

  it 'passes correct assertions' do
    expect(1).to be < 2
  end

  it 'fails incorrect assertions' do
    expect(2).to be < 1
  end

  it_behaves_like 'correct behavior'
  it_behaves_like 'incorrect behavior'

  context 'context' do
    it_behaves_like 'correct behavior'
    it_behaves_like 'incorrect behavior'
  end

  context 'in a' do
    context 'deeply' do
      context 'nested' do
        context 'context' do
          it 'passes correct assertions' do
            expect(1).to be < 2
          end

          it 'fails incorrect assertions' do
            expect(2).to be < 1
          end
        end
      end
    end
  end

  context 'when calling traced code' do
    it 'wraps the RSpec instrumentation around the traced code' do
      Datadog::Tracing.trace('code_under_test') do |span|
        time_to_run = rand
        sleep(rand)
        span.set_tag('run_time', time_to_run)
      end
    end
  end
end
