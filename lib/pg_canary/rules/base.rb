# frozen_string_literal: true

using PgCanary::PgQueryRefinement

module PgCanary
  module Rules
    # Base class for detection rules.
    #
    # A rule implements #check(query) and returns an array of Detection.
    # Configuration flows in explicitly through the QueryContext
    # (query.config); rules never reach for global state themselves.
    class Base
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

        def option(name, default:)
          options[name] = default
        end

        def options
          @options ||= {}
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

      private

        def rule_config(query)
          query.config.rules[self.class.rule_name]
        end

        def applicable_table?(query, table)
          !query.config.ignore_table?(table)
        end

        def detection(query, message:, suggestion: nil, table: nil, columns: nil)
          Detection.new(
            rule_name: self.class.rule_name,
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
