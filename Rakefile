# frozen_string_literal: true

require "bundler"
require "rake/extensiontask"
require "rake/testtask"

begin
  Bundler.setup :default, :development
  Bundler::GemHelper.install_tasks
rescue Bundler::BundlerError => error
  warn error.message
  warn "Run `bundle install` to install missing gems"
  exit error.status_code
end

Rake::ExtensionTask.new("safe_image_native") do |ext|
  ext.lib_dir = "lib"
  ext.ext_dir = "ext/safe_image_native"
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
end

task test: :compile
task default: :test
