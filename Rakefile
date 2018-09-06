require 'rake/testtask'
require 'rubocop/rake_task'

task default: %i[test rubocop]

desc 'Execute unit tests'
Rake::TestTask.new do |t|
  t.libs << 'spec'
  t.test_files = FileList['spec/spec_*.rb']
  t.verbose = true
  t.warning = false
end

desc 'Execute RuboCop static code analysis'
RuboCop::RakeTask.new(:rubocop) do |t|
  t.options = %w[-D]
  t.fail_on_error = true
end
