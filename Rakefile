# frozen_string_literal: true

require "bundler"
require "rake/testtask"

begin
  Bundler.setup :default, :development
  Bundler::GemHelper.install_tasks
rescue Bundler::BundlerError => error
  warn error.message
  warn "Run `bundle install` to install missing gems"
  exit error.status_code
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
end

namespace :fuzz do
  desc "Run deterministic SVG fuzz tests. Tune with SAFE_IMAGE_FUZZ_SEEDS and *_FUZZ_* env vars."
  Rake::TestTask.new(:svg) do |t|
    t.libs << "test"
    t.test_files = FileList["test/svg_*fuzz_test.rb"]
  end
end

task default: :test
