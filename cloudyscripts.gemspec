$LOAD_PATH.unshift File.expand_path('../lib', __FILE__)
require 'help/version'
require 'cloudyscripts'

Gem::Specification.new 'CloudyScripts', CloudyScripts::VERSION do |s|
  s.description       = "Scripts to facilitate programming for infrastructure clouds."
  s.summary           = "Scripts to facilitate programming for infrastructure clouds."
  s.authors           = ["Matthias Jung"]
  s.email             = "matthias.jung@gmail.com"
  s.homepage          = "http://elastic-security.com"
  s.files             = `git ls-files`.split("\n") - %w[.gitignore .travis.yml]
  s.test_files        = s.files.select { |p| p =~ /^test\/.*_test.rb/ }
  s.extra_rdoc_files  = s.files.select { |p| p =~ /^README/ } << 'LICENSE'
  s.rdoc_options      = %w[--line-numbers --inline-source --title CloudyScripts --main README.rdoc --encoding=UTF-8]

  s.add_dependency 'amazon-ec2'
  s.add_dependency 'net-ssh'
  s.add_dependency 'net-scp'
end