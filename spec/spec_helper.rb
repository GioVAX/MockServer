require 'minitest/autorun'
require 'minitest/reporters'

require_relative 'utils'
require_relative '../bootup_server_command'
require_relative '../mock_backend'

MockBackend::Boot.boot

Minitest::Reporters.use!([Minitest::Reporters::SpecReporter.new, Minitest::Reporters::JUnitReporter.new])
