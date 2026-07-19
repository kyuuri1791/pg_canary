# frozen_string_literal: true

require "active_support/core_ext/string/inflections"

module PgCanary
  module Rules
    # Base class for detection rules.
    #
    # A rule instance is built per analyzed query, holds that query's state,
    # and implements #check returning an array of Detection.
    class Base
      class << self
        def all
          subclasses.sort_by(&:name)
        end

        # :leading_wildcard_like for LeadingWildcardLike
        def rule_name
          @rule_name ||= name.demodulize.underscore.to_sym
        end

        def option(name, default:)
          options[name] = default
        end

        def options
          @options ||= {}
        end

        def default_enabled(value = nil)
          if value.nil?
            raise NotImplementedError, "#{self} must declare default_enabled" if @default_enabled.nil?

            @default_enabled
          else
            @default_enabled = value
          end
        end

        def enabled?(config)
          setting = config.rules.public_send(rule_name).enabled
          setting.nil? ? default_enabled : setting
        end

        def check(**state)
          new(**state).check
        end
      end

      def initialize(sql:, config:, connection:, parse_result:, scopes:, binds: [], type_casted_binds: nil)
        @sql = sql
        @config = config
        @connection = connection
        @parse_result = parse_result
        @scopes = scopes
        @binds = binds || []
        @type_casted_binds = type_casted_binds
      end

      def check
        raise NotImplementedError, "#{self.class} must implement #check"
      end

      private

        attr_reader :sql, :config, :connection, :parse_result, :scopes

        def each_scope(&)
          scopes.each(&)
        end

        # Value for a ParamRef ($n, 1-based). nil when unknown.
        def bind_value(number)
          index = number - 1
          return nil if index.negative?

          casted = @type_casted_binds
          return casted[index] if casted.is_a?(Array) && index < casted.length

          bind = @binds[index]
          return nil if bind.nil?

          bind.respond_to?(:value_for_database) ? bind.value_for_database : bind
        end

        def indexes(table)
          SchemaIntrospection.indexes(connection, table)
        end

        def column_type(table, column)
          SchemaIntrospection.column_type(connection, table, column)
        end

        # => { column_name => sql_type }
        def column_types(table)
          SchemaIntrospection.column_types(connection, table)
        end

        def rule_config
          config.rules.public_send(self.class.rule_name)
        end

        def applicable_table?(table)
          !config.ignore_table?(table)
        end

        def detection(message:, suggestion: nil, table: nil, columns: nil)
          Detection.new(
            rule_name: self.class.rule_name,
            sql: sql,
            table: table,
            columns: Array(columns),
            message: message,
            suggestion: suggestion
          )
        end
    end
  end
end
