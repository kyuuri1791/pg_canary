# frozen_string_literal: true

using PgCanary::PgQueryRefinement

module PgCanary
  module Rules
    # Regular-expression search (~, ~*, SIMILAR TO) cannot use a plain btree
    # index; only a pg_trgm GIN/GiST index can serve it. The regex variant of
    # leading_wildcard_like.
    class RegexWithoutTrgm < Base
      default_enabled true

      include IndexPredicates

      REGEX_OPS = %w[~ ~* !~ !~*].freeze

      def check(query)
        detections = []
        query.each_scope do |scope|
          next unless scope.where_clause

          scope.where_clause.walk_scope do |node|
            next unless node.is_a?(PgQuery::A_Expr)

            operator = display_operator(node)
            next unless operator

            column_ref = node.lexpr&.strip_casts
            next unless column_ref.is_a?(PgQuery::ColumnRef)

            table, column = scope.resolve(column_ref)
            next unless table && column
            next unless applicable_table?(query, table)
            next if trgm_index?(query, table, column)

            detections << detection(
              query,
              table: table,
              columns: column,
              message: "Regular-expression search (#{operator}) on #{table}.#{column} cannot use " \
                       "a btree index and will scan every row in production.",
              suggestion: <<~SUGGESTION.chomp
                Consider the pg_trgm extension with a GIN index:
                  CREATE EXTENSION IF NOT EXISTS pg_trgm;
                  CREATE INDEX index_#{table}_on_#{column}_trgm ON #{table} USING gin (#{column} gin_trgm_ops);
              SUGGESTION
            )
          end
        end
        detections
      end

      private

        def display_operator(a_expr)
          case a_expr.kind
          when :AEXPR_OP
            operator = a_expr.operator
            REGEX_OPS.include?(operator) ? operator : nil
          when :AEXPR_SIMILAR
            "SIMILAR TO"
          end
        end
    end
  end
end
