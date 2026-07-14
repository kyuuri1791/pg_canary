# frozen_string_literal: true

require_relative "lib/pg_canary/version"

Gem::Specification.new do |spec|
  spec.name = "pg_canary"
  spec.version = PgCanary::VERSION
  spec.authors = ["kyuuri1791"]

  spec.summary = "Detects SQL anti-patterns that can become slow queries in production, while you develop."
  spec.description = "pg_canary watches queries executed in development/test, parses them with PostgreSQL's " \
                     "own parser (pg_query), and combines the AST with schema metadata (indexes, column types) " \
                     "to warn about anti-patterns that can become slow queries in production: leading-wildcard " \
                     "LIKEs, function-wrapped columns in WHERE, ORDER BY RANDOM(), NOT IN (SELECT ...), and more."
  spec.homepage = "https://github.com/kyuuri1791/pg_canary"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[spec/ .git .github .rspec .rubocop Gemfile Rakefile docker-compose])
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.0"
  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "pg_query", ">= 5.0"
end
