# frozen_string_literal: true

module PgCanary
  # Global settings, exposed through PgCanary.configure.
  class Configuration
    # nil means "not explicitly configured" — the Railtie then enables
    # pg_canary in development/test only.
    attr_accessor :enabled

    # False-positive controls
    attr_accessor :ignore_tables, :table_size_hints, :size_rule_threshold

    attr_accessor :logger, :app_root
    attr_reader :rules

    def initialize
      @enabled = nil
      @ignore_tables = %w[schema_migrations ar_internal_metadata]
      @table_size_hints = {}
      @size_rule_threshold = 10_000
      @rules = RulesConfig.new
      @logger = nil
      @app_root = nil
    end

    def ignore_table?(table)
      table && ignore_tables.map(&:to_s).include?(table.to_s)
    end

    # Whether a size-dependent (Tier 2) rule should look at this table.
    # With no hints configured, every table qualifies (which is exactly why
    # Tier 2 rules are opt-in).
    def size_hint_allows?(table)
      hints = table_size_hints || {}
      return true if hints.empty?

      hints[table.to_s].to_i >= size_rule_threshold
    end
  end

  # Exposes one RuleConfig per built-in rule, both as methods and via [].
  #
  #   config.rules.unindexed_where.enabled = true
  #   config.rules[:leading_wildcard_like].severity = :error
  class RulesConfig
    def initialize
      @configs = {}
      Rules::Base.all.each do |klass|
        rule_config = RuleConfig.new(klass.options)
        @configs[klass.rule_name] = rule_config
        define_singleton_method(klass.rule_name) { rule_config }
      end
    end

    def [](name)
      @configs.fetch(name.to_sym)
    end
  end

  # Per-rule settings. `enabled` / `severity` default to nil, meaning
  # "use the rule class's default". Accessors for rule-specific options
  # (e.g. config.rules.deep_offset.threshold = 2000) are generated from the
  # rule class's declared options, so a typo raises NoMethodError instead of
  # silently creating a setting nobody reads.
  class RuleConfig
    attr_accessor :enabled, :severity

    def initialize(option_defaults = {})
      @options = option_defaults.dup
      @options.each_key do |name|
        define_singleton_method(name) { @options[name] }
        define_singleton_method(:"#{name}=") { |value| @options[name] = value }
      end
    end

    def [](key)
      @options.fetch(key.to_sym)
    end
  end
end
