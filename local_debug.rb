require_relative 'mock_backend'

MockBackend::Boot.boot

i = 0
loop do
  sleep 1
  i += 1
  puts 'loop' if (i % 100).zero?
end
