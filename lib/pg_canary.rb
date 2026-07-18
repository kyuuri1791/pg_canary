# frozen_string_literal: true

require "active_support"
require "pg_query"

require_relative "pg_canary/version"
require_relative "pg_canary/configuration"
require_relative "pg_canary/pg_query_support"
require_relative "pg_canary/schema_introspection"
require_relative "pg_canary/rules/detection"
require_relative "pg_canary/rules/query_context"
require_relative "pg_canary/rules/base"
require_relative "pg_canary/rules/index_predicates"
Dir[File.join(__dir__, "pg_canary", "rules", "definitions", "*.rb")].each { |file| require file }
require_relative "pg_canary/detector"
require_relative "pg_canary/subscriber"
require_relative "pg_canary/middleware"

module PgCanary
  class Error < StandardError; end

  @config = Configuration.new

  class << self
    attr_reader :config

    def configure
      yield config
    end

    # Reports an internal pg_canary failure without ever breaking the host app.
    def internal_error(error)
      warn_once("[PgCanary] internal error (detection skipped): #{error.class}: #{error.message}")
    end

    private

    def logger
      config.logger || default_logger
    end

    def default_logger
      @default_logger ||= begin
        require "logger"
        ::Logger.new($stderr)
      end
    end

    def warn_once(message)
      @warned ||= {}
      return if @warned[message]

      @warned[message] = true
      logger.warn(message)
    end
  end

  if defined?(Rails::Railtie)
    class Railtie < Rails::Railtie
      initializer "pg_canary.app_root", before: :load_config_initializers do
        PgCanary.config.app_root ||= Rails.root.to_s
      end

      initializer "pg_canary.middleware" do |app|
        app.middleware.use PgCanary::Middleware
      end

      config.after_initialize do
        config = PgCanary.config
        config.enabled = Rails.env.development? || Rails.env.test? if config.enabled.nil?
        config.logger ||= Rails.logger
        Subscriber.subscribe! if config.enabled
      end
    end
  end
end
