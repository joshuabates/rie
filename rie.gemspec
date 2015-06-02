require './lib/rie/version'

Gem::Specification.new do |s|
  s.name = "rie"
  s.version = Rie.version
  s.authors = ["Jeanine Adkisson"]
  s.email = ["jneen@goodguide.com"]
  s.summary = "A modeling library for datomic"

  s.description = <<-desc.strip.gsub(/\s+/, ' ')
    Immutable models, first-class changesets, value-based programming
  desc

  # s.add_dependency 'dalton'

  s.homepage = "https://github.com/GoodGuide/rie"
  s.rubyforge_project = "rie"
  s.files = Dir['README.md', 'Gemfile', 'LICENSE', 'rie.gemspec', 'lib/**/*.rb']
  s.license = 'EPL'
end
