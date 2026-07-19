# frozen_string_literal: true

require "active_support/backtrace_cleaner"

using PgCanary::PgQueryRefinement

module PgCanary
  # Parses an event's SQL into a QueryContext, runs every enabled rule
  # against it, and filters ignored tables. Each returned Detection carries
  # the query's fingerprint, so a consumer that sees the same query and rule
  # repeatedly (e.g. an N+1 loop within one request) can collapse them —
  # see Middleware.
  class Detector
    # Swallows the configuration whole at construction: pg_canary treats it
    # as fixed after boot (set in an initializer).
    def initialize(config)
      @config = config
      @rules = Rules::Base.all.map(&:new).select { |rule| rule.enabled?(config) }
      @backtrace_cleaner = build_backtrace_cleaner(config.app_root)
    end

    # => [Detection] the detections that should be notified.
    def call(payload)
      query = build_query(payload)
      return [] unless query

      location = nil
      @rules.flat_map do |rule|
        detections = check_rule(rule, query)
        next [] if detections.empty?

        location ||= source_location
        detections.each do |d|
          d.location = location
          d.fingerprint = query.fingerprint
        end
      end
    end

    private

      # nil for anything that is not a plain SELECT (or fails to parse).
      def build_query(payload)
        parse_result = PgQuery.parse(payload[:sql])
        stmt = parse_result.tree.stmts.first&.stmt&.unwrap
        return nil unless stmt.is_a?(PgQuery::SelectStmt)

        Rules::QueryContext.new(
          sql: payload[:sql],
          connection: payload[:connection],
          parse_result: parse_result,
          config: @config,
          binds: payload[:binds],
          type_casted_binds: payload[:type_casted_binds]
        )
      rescue PgQuery::ParseError
        nil
      end

      def check_rule(rule, query)
        rule.check(query).reject { |d| ignored?(d, query) }
      rescue StandardError => e
        PgCanary.internal_error(e)
        []
      end

      def ignored?(detection, query)
        config = query.config
        return true if config.ignore_table?(detection.table)

        # Table-less detections (e.g. ORDER BY RANDOM() over a subquery) are
        # dropped when every table in the query is ignored.
        if detection.table.nil?
          tables = query.tables
          return tables.any? && tables.all? { |t| config.ignore_table?(t) }
        end

        false
      end

      def build_backtrace_cleaner(root)
        ActiveSupport::BacktraceCleaner.new.tap do |cleaner|
          cleaner.add_silencer { |line| line.include?("lib/pg_canary") }
          cleaner.add_filter { |line| line.delete_prefix("#{root}/") } if root
        end
      end

      # The application frame that triggered the query.
      def source_location
        line = @backtrace_cleaner.clean(caller).first
        line && line[/\A.+?:\d+/]
      end
  end
end
