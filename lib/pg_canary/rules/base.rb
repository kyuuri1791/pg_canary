# frozen_string_literal: true

module PgCanary
  module Rules
    # Base class for detection rules.
    #
    # A rule implements #check(query) and returns an array of Detection.
    # Configuration flows in explicitly through the QueryContext
    # (query.config); rules never reach for global state themselves.
    class Base
      include PgQuerySupport

      class << self
        def all
          subclasses.sort_by(&:name)
        end

        # :leading_wildcard_like for LeadingWildcardLike
        def rule_name
          @rule_name ||= name.split("::").last
                             .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                             .downcase.to_sym
        end

        # Rule-specific options and their defaults, e.g. { threshold: 1000 }.
        # Declared statically so RuleConfig can generate real accessors.
        def options
          {}
        end
      end

      def check(_query)
        raise NotImplementedError, "#{self.class} must implement #check"
      end

      def enabled?(config)
        setting = config.rules[self.class.rule_name].enabled
        setting.nil? ? default_enabled : setting
      end

      def default_enabled
        raise NotImplementedError, "#{self.class} must declare #default_enabled (true for Tier 1, false for Tier 2)"
      end

      def size_dependent?
        raise NotImplementedError, "#{self.class} must declare #size_dependent?"
      end

      private

      def rule_config(query)
        query.config.rules[self.class.rule_name]
      end

      # Tier 2 gate: with size hints configured, only tables hinted as large
      # are checked.
      def applicable_table?(query, table)
        return false if query.config.ignore_table?(table)
        return true unless size_dependent?

        query.config.size_hint_allows?(table)
      end

      def detection(query, message:, suggestion: nil, table: nil, columns: nil)
        Detection.new(
          rule_name: self.class.rule_name,
          severity: rule_config(query).severity || :warning,
          sql: query.sql,
          table: table,
          columns: Array(columns),
          message: message,
          suggestion: suggestion
        )
      end
    end
  end
end
