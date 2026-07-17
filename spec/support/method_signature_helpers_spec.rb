RSpec.describe Datadog::MethodSignatureHelpers do
  def method_for(&block)
    Class.new { define_method(:m, &block) }.instance_method(:m)
  end

  describe '.compatibility_violations' do
    context 'exact match' do
      it 'is compatible' do
        wrapper = method_for { |a, b = 1| }
        real = method_for { |a, b = 1| }

        expect(described_class.compatibility_violations(wrapper, real)).to be_empty
      end
    end

    context 'pure pass-through wrapper' do
      it 'is compatible with any real method' do
        wrapper = method_for { |*args, **kwargs, &block| }
        real = method_for { |a, b:, c: 1| }

        expect(described_class.compatibility_violations(wrapper, real)).to be_empty
      end
    end

    context 'wrapper requires more positional args than the real method' do
      it 'flags it' do
        wrapper = method_for { |a, b| }
        real = method_for { |a| }

        expect(described_class.compatibility_violations(wrapper, real))
          .to include(a_string_matching(/wrapper requires 2 positional args but real method requires 1/))
      end
    end

    context 'wrapper narrows a required positional arg to optional (drops it)' do
      it 'flags it, since bare super would forward the default even when unset' do
        wrapper = method_for { |a = nil| }
        real = method_for {}

        expect(described_class.compatibility_violations(wrapper, real))
          .to include(a_string_matching(/unset optional args/))
      end
    end

    context 'real method accepts more positional args than the wrapper forwards' do
      it 'flags a missing *args' do
        wrapper = method_for { |a| }
        real = method_for { |a, b| }

        expect(described_class.compatibility_violations(wrapper, real))
          .to include(a_string_matching(/missing \*args/))
      end
    end

    context 'wrapper accepts a required keyword the real method does not require' do
      it 'flags it' do
        wrapper = method_for { |topic:| }
        real = method_for {}

        expect(described_class.compatibility_violations(wrapper, real))
          .to include(a_string_matching(/wrapper requires keywords the real method doesn't require/))
      end
    end

    context 'real method requires a keyword the wrapper does not declare' do
      it 'flags it' do
        wrapper = method_for { |topic:| }
        real = method_for { |topic:, partition:| }

        expect(described_class.compatibility_violations(wrapper, real))
          .to include(a_string_matching(/real method requires keywords the wrapper doesn't declare.*partition/))
      end
    end

    context 'real method requires a keyword but the wrapper has **kwargs to forward it' do
      it 'is compatible' do
        wrapper = method_for { |topic:, **kwargs| }
        real = method_for { |topic:, partition:| }

        expect(described_class.compatibility_violations(wrapper, real)).to be_empty
      end
    end

    context 'wrapper mirrors the real method optional keyword exactly' do
      it 'is compatible' do
        wrapper = method_for { |timeout: nil| }
        real = method_for { |timeout: nil| }

        expect(described_class.compatibility_violations(wrapper, real)).to be_empty
      end
    end

    context 'wrapper declares an optional keyword the real method does not accept at all' do
      it 'flags it, since bare super would forward it even when unset' do
        wrapper = method_for { |timeout: nil| }
        real = method_for {}

        expect(described_class.compatibility_violations(wrapper, real))
          .to include(a_string_matching(/optional keywords the real method doesn't accept/))
      end
    end

    context 'real method has an open keyword surface the wrapper fails to forward' do
      it 'flags a missing **kwargs' do
        wrapper = method_for {}
        real = method_for { |**kwargs| }

        expect(described_class.compatibility_violations(wrapper, real))
          .to include(a_string_matching(/missing \*\*kwargs/))
      end
    end

    context 'wrapper has **kwargs but the real method has no keyword surface' do
      it 'flags an unexpected **kwargs' do
        wrapper = method_for { |**kwargs| }
        real = method_for {}

        expect(described_class.compatibility_violations(wrapper, real))
          .to include(a_string_matching(/unexpected \*\*kwargs/))
      end
    end
  end
end
