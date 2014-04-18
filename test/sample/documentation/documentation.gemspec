# -*- encoding: utf-8 -*-
$:.unshift 'lib'
require 'documentation/version'

spec = Gem::Specification.new do |s|
  s.name = "documentation"
  s.version = Documentation::VERSION
  s.author = "Debian Ruby Team"
  s.email = "pkg-ruby-extras-maintainers@lists.alioth.debian.org"
  s.homepage = "http://wiki.debian.org/Teams/Ruby"
  s.platform = Gem::Platform::RUBY
  s.summary = "Documentation test"
  s.files = ["documentation.gemspec", "lib/documentation.rb",
             "lib/documentation/version.rb"]
  s.require_path = "lib"
  s.description = "A simple test to check documentation generation."
end
