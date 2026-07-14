# frozen_string_literal: true

require "active_record"
require "pg_canary"

require_relative "support/database"

module PgCanarySpec
  module Helpers
    # Collects the detections triggered inside the block by intercepting
    # them at the collection boundary.
    def detections_for
      detections = []
      allow(PgCanary::Middleware).to receive(:collect) { |batch| detections.concat(batch) }
      yield
      detections
    end
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.disable_monkey_patching!
  config.order = :random
  config.include PgCanarySpec::Helpers

  config.before(:suite) do
    PgCanarySpec::Database.connect!
    PgCanarySpec::Database.load_schema!
    PgCanary::Subscriber.subscribe!
  end

  # Each example gets a fresh, enabled configuration and a fresh detector;
  # the stubs are removed automatically after the example, so nothing can
  # leak between examples. The detector is built lazily on the first query
  # so that per-example rule configuration (set in inner before hooks) is
  # respected.
  config.before do
    allow(PgCanary).to receive(:config).and_return(
      PgCanary::Configuration.new.tap { |c| c.enabled = true }
    )
    detector = nil
    allow(PgCanary::Subscriber).to receive(:detector) do
      detector ||= PgCanary::Detector.new(PgCanary.config)
    end
  end
end
