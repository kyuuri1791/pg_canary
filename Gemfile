# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in pg_canary.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "pg", "~> 1.5"
gem "rspec", "~> 3.0"

gem "rubocop", "~> 1.21"

rails_version = ENV.fetch("RAILS_VERSION", nil)
if rails_version
  gem "activerecord", "~> #{rails_version}.0"
  gem "activesupport", "~> #{rails_version}.0"

  # Default gems that Rails < 7.2 relies on but no longer ships with newer Rubies
  if Gem::Version.new(rails_version) < Gem::Version.new("7.2")
    gem "base64"
    gem "bigdecimal"
    gem "drb"
    gem "logger"
    gem "mutex_m"
  end
end
