# frozen_string_literal: true

module PgCanary
  module Rules
    # LIKE / ILIKE with a leading wildcard ('%foo', '%foo%') cannot use a
    # btree index regardless of table size. Only a pg_trgm GIN/GiST index
    # helps, so we stay silent when one exists on the column.
    # Bind parameters ($1) are resolved from the event's binds.
    class LeadingWildcardLike < Base
      default_enabled true

      include IndexPredicates

      using PgCanary::PgQueryRefinement

      LIKE_KINDS = %i[AEXPR_LIKE AEXPR_ILIKE].freeze

      def check
        detections = []
        each_scope do |scope|
          next unless scope.where_clause

          scope.where_clause.walk_scope do |node|
            detections << inspect_expr(scope, node) if like_expr?(node)
          end
        end
        detections.compact
      end

      private

        def like_expr?(node)
          node.is_a?(PgQuery::A_Expr) && LIKE_KINDS.include?(node.kind)
        end

        def inspect_expr(scope, expr)
          column_ref = expr.lexpr&.strip_casts
          return nil unless column_ref.is_a?(PgQuery::ColumnRef)

          pattern = pattern_value(expr.rexpr)
          return nil unless pattern&.start_with?("%", "_")

          table, column = scope.resolve(column_ref)
          return nil unless table && column
          return nil unless applicable_table?(table)
          return nil if trgm_index?(table, column)

          operator = expr.kind == :AEXPR_ILIKE ? "ILIKE" : "LIKE"
          detection(
            table: table,
            columns: column,
            message: "Leading-wildcard #{operator} (#{pattern.inspect}) on #{table}.#{column} cannot use " \
                     "a btree index and will scan every row in production.",
            suggestion: <<~SUGGESTION.chomp
              Consider the pg_trgm extension with a GIN index:
                CREATE EXTENSION IF NOT EXISTS pg_trgm;
                CREATE INDEX index_#{table}_on_#{column}_trgm ON #{table} USING gin (#{column} gin_trgm_ops);
            SUGGESTION
          )
        end

        # Pattern string from a literal, a cast literal, or a bind parameter.
        def pattern_value(rexpr)
          node = rexpr&.strip_casts
          case node
          when PgQuery::A_Const
            value = node.value
            value.is_a?(String) ? value : nil
          when PgQuery::ParamRef
            value = bind_value(node.number)
            value.is_a?(String) ? value : nil
          end
        end
    end
  end
end
