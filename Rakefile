require 'pathname'

root = Pathname.new(__FILE__).dirname

task :spec do
  load root.join('spec/spec_helper.rb')
  FileList.new(ENV['files'] || './spec/**/*_spec.rb').each { |f| load f }
  Minitest::Unit.autorun
end

task :default => :spec
