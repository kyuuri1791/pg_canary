# frozen_string_literal: true

module PgCanary
  class Configuration
    attr_accessor :enabled, :ignore_tables, :logger, :app_root
    attr_reader :rules

    def initialize
      @enabled = nil
      @ignore_tables = %w[schema_migrations ar_internal_metadata]
      @rules = RulesConfig.new
      @logger = nil
      @app_root = nil
    end

    def ignore_table?(table)
      table && ignore_tables.map(&:to_s).include?(table.to_s)
    end
  end

  class RulesConfig
    def initialize
      Rules::Base.all.each do |klass|
        rule_config = RuleConfig.new(klass.options)
        define_singleton_method(klass.rule_name) { rule_config }
      end
    end
  end

  class RuleConfig
    attr_accessor :enabled

    def initialize(option_defaults = {})
      @options = option_defaults.dup
      @options.each_key do |name|
        define_singleton_method(name) { @options[name] }
        define_singleton_method(:"#{name}=") { |value| @options[name] = value }
      end
    end
  end
end
