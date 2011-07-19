# 
# To change this template, choose Tools | Templates
# and open the template in the editor.
 

require 'rubygems'
require 'rake'
require 'rake/clean'
require 'rake/gempackagetask'
require 'rake/rdoctask'
require 'rake/testtask'

spec = Gem::Specification.new do |s|
  s.name = 'CloudyScripts'
  s.version = '1.8.30'
  s.has_rdoc = true
  s.extra_rdoc_files = ['README.rdoc', 'LICENSE']
  s.summary = 'Scripts to facilitate programming for infrastructure clouds.'
  s.description = s.summary
  s.homepage = "http://elastic-security.com"
  s.rubyforge_project = "cloudyscripts"
  s.author = 'Matthias Jung'
  s.email = 'matthias.jung@gmail.com'
  # s.executables = ['your_executable_here']
  s.files = %w(LICENSE README.rdoc Rakefile) + Dir.glob("{bin,lib,spec}/**/*")
  s.require_path = "lib"
  s.bindir = "bin"
  s.has_rdoc = true
  s.add_dependency("amazon-ec2")
  s.add_dependency("net-ssh")
  s.add_dependency("net-scp")
end

Rake::GemPackageTask.new(spec) do |p|
  p.gem_spec = spec
  p.need_tar = true
  p.need_zip = true
end

Rake::RDocTask.new do |rdoc|
  files =['README', 'LICENSE', 'lib/**/*.rb']
  rdoc.rdoc_files.add(files)
  rdoc.main = "README" # page to start on
  rdoc.title = "CloudyScripts Docs"
  rdoc.rdoc_dir = 'doc/rdoc' # rdoc output folder
  rdoc.options << '--line-numbers'
end

Rake::TestTask.new do |t|
  t.test_files = FileList['test/**/*.rb']
end
