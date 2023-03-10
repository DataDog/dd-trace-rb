require 'benchmark/ips'
require 'zlib'
require 'openssl'

DUMMY_INPUT = Random.new(0).bytes(512 * 1024)

def zlib_compression
  Zlib.deflate(DUMMY_INPUT, Zlib::BEST_SPEED)
end

def simple_sum
  res = 0
  100_000.times { res += 1 }
end

def fib(n)
  return n if n <= 1
  fib(n-1) + fib(n-2)
end

def fibonacci
  fib(20)
end

def openssl_key_generation
  OpenSSL::PKey::RSA.new(1024)
end

def openssl_encryption
  OpenSSL::Cipher.new("AES-256-CBC").tap do |it|
    it.encrypt
    it.key = "dummy key dummy key dummy key---"
    iv = it.random_iv
    result = it.update(DUMMY_INPUT) + it.final
    return result, iv
  end
end

ZLIB_COMPRESSED_INPUT = zlib_compression
OPENSSL_ENCRYPTED_INPUT, OPENSSL_ENCRYPTED_INPUT_IV = openssl_encryption

def zlib_decompression
  Zlib.inflate(ZLIB_COMPRESSED_INPUT)
end

def openssl_decryption
  OpenSSL::Cipher.new("AES-256-CBC").tap do |it|
    it.decrypt
    it.key = "dummy key dummy key dummy key---"
    it.iv = OPENSSL_ENCRYPTED_INPUT_IV
    it.update(OPENSSL_ENCRYPTED_INPUT)
    it.final
  end
end

Benchmark.ips do |x|
  COUNT = 7

  x.config(:time => ((60.0 - COUNT) / COUNT), :warmup => 1)

  x.report("zlib compression") { zlib_compression }
  x.report("zlib decompression") { zlib_decompression }
  x.report("simple sum") { simple_sum }
  x.report("fibonacci") { fibonacci }
  x.report("openssl key generation") { openssl_key_generation }
  x.report("openssl encryption") { openssl_encryption }
  x.report("openssl decryption") { openssl_decryption }
end
