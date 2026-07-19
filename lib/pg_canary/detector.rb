# frozen_string_literal: true

require "active_support/backtrace_cleaner"

using PgCanary::PgQueryRefinement

module PgCanary
  # Parses an event's SQL, runs every enabled rule against it, and filters
  # ignored tables. Each returned Detection carries the query's fingerprint,
  # so a consumer that sees the same query and rule repeatedly (e.g. an N+1
  # loop within one request) can collapse them — see Middleware.
  class Detector
    # Swallows the configuration whole at construction: pg_canary treats it
    # as fixed after boot (set in an initializer).
    def initialize(config)
      @config = config
      @rule_classes = Rules::Base.all.select { |klass| klass.enabled?(config) }
      @backtrace_cleaner = build_backtrace_cleaner(config.app_root)
    end

    # => [Detection] the detections that should be notified.
    def call(payload)
      state = build_state(payload)
      return [] unless state

      location = nil
      fingerprint = nil
      @rule_classes.flat_map do |klass|
        detections = check_rule(klass, state)
        next [] if detections.empty?

        location ||= source_location
        fingerprint ||= PgQuery.fingerprint(state[:sql])
        detections.each do |d|
          d.location = location
          d.fingerprint = fingerprint
        end
      end
    end

    private

      # nil for anything that is not a plain SELECT (or fails to parse).
      def build_state(payload)
        parse_result = PgQuery.parse(payload[:sql])
        stmt = parse_result.tree.stmts.first&.stmt&.unwrap
        return nil unless stmt.is_a?(PgQuery::SelectStmt)

        {
          sql: payload[:sql],
          config: @config,
          connection: payload[:connection],
          parse_result: parse_result,
          scopes: build_scopes(parse_result),
          binds: payload[:binds],
          type_casted_binds: payload[:type_casted_binds]
        }
      rescue PgQuery::ParseError
        nil
      end

      # All SELECT scopes in the statement, including CTEs, subqueries in
      # FROM/WHERE and UNION branches.
      def build_scopes(parse_result)
        stmts = []
        parse_result.tree.stmts.each do |raw|
          raw.stmt.walk { |msg| stmts << msg if msg.is_a?(PgQuery::SelectStmt) }
        end
        stmts.map { |s| Rules::Scope.new(s) }
      end

      def check_rule(klass, state)
        klass.new(**state).check.reject { |d| ignored?(d, state[:scopes]) }
      rescue StandardError => e
        PgCanary.internal_error(e)
        []
      end

      def ignored?(detection, scopes)
        return true if @config.ignore_table?(detection.table)

        # Table-less detections (e.g. ORDER BY RANDOM() over a subquery) are
        # dropped when every table in the query is ignored.
        if detection.table.nil?
          tables = scopes.flat_map(&:tables).uniq
          return tables.any? && tables.all? { |t| @config.ignore_table?(t) }
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
