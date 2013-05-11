# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "em-http-fetcher"

Gem::Specification.new do |s|
  s.name        = "em-http-fetcher"
  s.version     = EventMachine::HttpFetcher::VERSION

  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Tatsuki Sugiura"]
  s.email       = ["sugi@nemui.org"]
  s.homepage    = "http://github.com/sugi/em-http-fetcher"
  s.summary     = "HTTP fetch client based on ruby EventMachne and EM-HTTP-Request"
  s.description = "HTTP fetch client based on ruby EventMachne and EM-HTTP-Request that has configureable concurrency regardless of EM's thread pool."

#  s.rubyforge_project = ""

  s.required_ruby_version = '>= 1.9.0'

  s.add_dependency "addressable", ">= 2.2.3"
  s.add_dependency "em-http-request", ">= 1.0.0"

#  s.add_development_dependency "rspec"
#  s.add_development_dependency "rake"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end

