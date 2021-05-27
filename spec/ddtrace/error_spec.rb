RSpec.describe Datadog::Error do
  context 'with default values' do
    let(:error) { described_class.new }

    it do
      expect(error.type).to be_empty
      expect(error.message).to be_empty
      expect(error.backtrace).to be_empty
    end

    # Empty strings were being interpreted as ASCII strings breaking `msgpack`
    # decoding on the agent-side.
    it 'encodes default values in UTF-8' do
      error = described_class.new

      expect(error.type.encoding).to eq(::Encoding::UTF_8)
      expect(error.message.encoding).to eq(::Encoding::UTF_8)
      expect(error.backtrace.encoding).to eq(::Encoding::UTF_8)
    end
  end

  context 'with all values provided' do
    let(:error) { described_class.new('ErrorClass', 'message', %w[line1 line2 line3]) }

    it do
      expect(error.type).to eq('ErrorClass')
      expect(error.message).to eq('message')
      expect(error.backtrace).to eq("line1\nline2\nline3")
    end
  end

  describe '.build_from' do
    subject(:error) { described_class.build_from(value) }

    context 'with an exception' do
      let(:value) { begin 1 / 0; rescue => e; e; end }
      it do
        expect(error.type).to eq('ZeroDivisionError')
        expect(error.message).to eq('divided by 0')
        expect(error.backtrace).to include('error_spec.rb')
      end

      context 'with a cause' do
        let(:clazz) do
          Class.new do
            def root
              raise 'root cause'
            end

            def wrapper
              root
            rescue
              raise 'wrapper layer'
            end

            def call
              wrapper
            rescue => e
              e
            end
          end
        end

        let(:value) do
          begin
            clazz.new.call
          rescue => e
            e
          end
        end

        it 'reports nested errors' do
          expect(error.type).to eq('RuntimeError')
          expect(error.message).to eq('wrapper layer')

          wrapper_error_message = /error_spec.rb:\d+:in.*wrapper': wrapper layer \(RuntimeError\)/
          caller_stack = /from.*error_spec.rb:\d+:in `call'/
          root_error_message = /error_spec.rb:\d+:in.*root': root cause \(RuntimeError\)/
          wrapper_stack = /from.*error_spec.rb:\d+:in `wrapper'/

          expect(error.backtrace)
            .to match(/
                       #{wrapper_error_message}.*
                       #{caller_stack}.*
                       #{root_error_message}.*
                       #{wrapper_stack}.*
                       #{caller_stack}.*
                       /mx)

          # Expect 2 "first-class" exception lines: 'root cause' and 'wrapper layer'.
          expect(error.backtrace.each_line.reject { |l| l.start_with?("\tfrom") }).to have(2).items
        end

        context 'that is reused' do
          before { skip("This version of Ruby doesn't support setting exception cause") if RUBY_VERSION < '2.2.0' }

          let(:value) do
            begin
              begin
                raise 'first error'
              rescue => e
                raise 'second error' rescue ex2 = $ERROR_INFO
                raise e, cause: ex2 # raises ArgumentError('circular causes') on Ruby >= 2.6
              end
            rescue => e
              e
            end
          end

          it 'reports errors only once', if: (RUBY_VERSION < '2.6.0' || PlatformHelpers.truffleruby?) do
            expect(error.type).to eq('RuntimeError')
            expect(error.message).to eq('first error')

            expect(error.backtrace).to match(/first error \(RuntimeError\).*second error \(RuntimeError\)/m)

            # Expect 2 "first-class" exception lines: 'first error' and 'second error'.
            expect(error.backtrace.each_line.reject { |l| l.start_with?("\tfrom") }).to have(2).items
          end

          it 'reports errors only once', if: (RUBY_VERSION >= '2.6.0' && !PlatformHelpers.truffleruby?) do
            expect(error.type).to eq('ArgumentError')
            expect(error.message).to eq('circular causes')

            expect(error.backtrace).to match(/circular causes \(ArgumentError\).*first error \(RuntimeError\)/m)

            # Expect 2 "first-class" exception lines: 'circular causes' and 'first error'.
            # Ruby doesn't report 'second error' as it was never successfully set as the cause of 'first error'.
            expect(error.backtrace.each_line.reject { |l| l.start_with?("\tfrom") }).to have(2).items
          end
        end

        context 'with nil message' do
          let(:cause) do
            Class.new(StandardError) do
              def message; end
            end
          end
          let(:value) { begin; raise cause; rescue => e; e; end }
          before do
            stub_const('NilMessageError', cause)
          end

          it 'is expected to message is empty' do
            expect(error.type).to eq('NilMessageError')
            expect(error.message).to eq('')
            expect(error.backtrace).to include('error_spec.rb')
          end

          it 'is expected to include class name in backtrace' do
            expect(error.backtrace).to include(':  (NilMessageError)') # :[space][nil][space](NilMessageError)
          end
        end

        context 'benchmark' do
          before { skip('Benchmark results not currently captured in CI') if ENV.key?('CI') }

          it do
            require 'benchmark/ips'

            Benchmark.ips do |x|
              x.config(time: 8, warmup: 2)

              x.report 'build_from' do
                described_class.build_from(value)
              end

              x.compare!
            end
          end
        end
      end
    end

    context 'with an array' do
      let(:value) { ['ZeroDivisionError', 'divided by 0'] }

      it do
        expect(error.type).to eq('ZeroDivisionError')
        expect(error.message).to eq('divided by 0')
        expect(error.backtrace).to be_empty
      end
    end

    context 'with a custom object responding to :message' do
      let(:value) do
        # RSpec 'double' hijacks the #class method, thus not allowing us
        # to organically test the `Error#type` inferred for this object.
        clazz = stub_const('Test::CustomMessage', Struct.new(:message))
        clazz.new('custom msg')
      end

      it do
        expect(error.type).to eq('Test::CustomMessage')
        expect(error.message).to eq('custom msg')
        expect(error.backtrace).to be_empty
      end
    end

    context 'with nil' do
      let(:value) { nil }

      it do
        expect(error.type).to be_empty
        expect(error.message).to be_empty
        expect(error.backtrace).to be_empty
      end
    end

    context 'with a utf8 incompatible message' do
      let(:value) { StandardError.new("\xC2".force_encoding(::Encoding::ASCII_8BIT)) }

      it 'discards unencodable value' do
        expect(error.type).to eq('StandardError')
        expect(error.message).to be_empty
        expect(error.backtrace).to be_empty
      end
    end
  end
end
