# frozen_string_literal: true

require 'datadog/symbol_database/file_hash'
require 'tempfile'

RSpec.describe Datadog::SymbolDatabase::FileHash do
  describe '.compute' do
    it 'returns nil for nil path' do
      expect(described_class.compute(nil)).to be_nil
    end

    it 'returns nil for non-existent file' do
      expect(described_class.compute('/path/that/does/not/exist.rb')).to be_nil
    end

    it 'computes hash for empty file' do
      Tempfile.create(['test', '.rb']) do |f|
        f.close

        hash = described_class.compute(f.path)

        expect(hash).to be_a(String)
        expect(hash.length).to eq(40)  # SHA-1 hex is 40 chars
        # Empty file: "blob 0\0" -> known hash
        expect(hash).to eq('e69de29bb2d1d6434b8b29ae775ad8c2e48c5391')
      end
    end

    it 'computes hash for file with content' do
      Tempfile.create(['test', '.rb']) do |f|
        f.write("puts 'hello'\n")
        f.close

        hash = described_class.compute(f.path)

        expect(hash).to be_a(String)
        expect(hash.length).to eq(40)
        expect(hash).to match(/^[0-9a-f]{40}$/)
      end
    end

    it 'computes hash matching git hash-object' do
      Tempfile.create(['test', '.rb']) do |f|
        content = "# frozen_string_literal: true\n\nclass MyClass\n  def my_method\n    42\n  end\nend\n"
        f.write(content)
        f.close

        our_hash = described_class.compute(f.path)

        # Compute git hash for comparison
        git_hash = `git hash-object #{f.path}`.strip

        expect(our_hash).to eq(git_hash) unless git_hash.empty?
      end
    end

    it 'handles different file sizes' do
      # Small file
      Tempfile.create(['small', '.rb']) do |f|
        f.write('x')
        f.close
        small_hash = described_class.compute(f.path)
        expect(small_hash).to be_a(String)
      end

      # Larger file
      Tempfile.create(['large', '.rb']) do |f|
        f.write('x' * 10000)
        f.close
        large_hash = described_class.compute(f.path)
        expect(large_hash).to be_a(String)
      end
    end

    it 'handles binary mode reading' do
      Tempfile.create(['test', '.rb']) do |f|
        # Write content with null byte
        f.write("before\0after")
        f.close

        hash = described_class.compute(f.path)

        expect(hash).to be_a(String)
        expect(hash.length).to eq(40)
      end
    end

    it 'returns nil and logs on read error' do
      # Stub File.read to raise an error
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:read).and_raise(Errno::EACCES, "Permission denied")

      expect(Datadog.logger).to receive(:debug).with(/File hash computation failed/)

      hash = described_class.compute('/fake/unreadable/file.rb')

      expect(hash).to be_nil
    end

    it 'handles UTF-8 content' do
      Tempfile.create(['test', '.rb']) do |f|
        f.write("# Encoding: UTF-8\nclass Café\nend\n")
        f.close

        hash = described_class.compute(f.path)

        expect(hash).to be_a(String)
        expect(hash.length).to eq(40)
      end
    end

    it 'handles files with different line endings' do
      Tempfile.create(['unix', '.rb']) do |f|
        f.write("line1\nline2\n")
        f.close
        unix_hash = described_class.compute(f.path)
        expect(unix_hash).to be_a(String)
      end

      Tempfile.create(['windows', '.rb']) do |f|
        f.write("line1\r\nline2\r\n")
        f.close
        windows_hash = described_class.compute(f.path)
        expect(windows_hash).to be_a(String)
      end

      # Different line endings should produce different hashes
      # (This is expected - Git treats them as different content)
    end
  end
end
