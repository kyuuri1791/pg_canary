# frozen_string_literal: true

module PgCanary
  module Rules
    # LIKE / ILIKE with a leading wildcard ('%foo', '%foo%') cannot use a
    # btree index regardless of table size. Only a pg_trgm GIN/GiST index
    # helps, so we stay silent when one exists on the column.
    # Bind parameters ($1) are resolved from the event's binds.
    class LeadingWildcardLike < Base
      include IndexPredicates

      def default_enabled
        true
      end

      LIKE_KINDS = %i[AEXPR_LIKE AEXPR_ILIKE].freeze

      def check(query)
        detections = []
        query.each_scope do |scope|
          next unless scope.where_clause

          walk_within_scope(scope.where_clause) do |node|
            detections << inspect_expr(query, scope, node) if like_expr?(node)
          end
        end
        detections.compact
      end

      private

        def like_expr?(node)
          node.is_a?(PgQuery::A_Expr) && LIKE_KINDS.include?(node.kind)
        end

        def inspect_expr(query, scope, expr)
          column_ref = strip_type_casts(expr.lexpr)
          return nil unless column_ref.is_a?(PgQuery::ColumnRef)

          pattern = pattern_value(query, expr.rexpr)
          return nil unless pattern&.start_with?("%", "_")

          table, column = scope.resolve(column_ref)
          return nil unless table && column
          return nil unless applicable_table?(query, table)
          return nil if trgm_index?(query, table, column)

          operator = expr.kind == :AEXPR_ILIKE ? "ILIKE" : "LIKE"
          detection(
            query,
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
        def pattern_value(query, rexpr)
          node = strip_type_casts(rexpr)
          case node
          when PgQuery::A_Const
            value = constant_value(node)
            value.is_a?(String) ? value : nil
          when PgQuery::ParamRef
            value = query.bind_value(node.number)
            value.is_a?(String) ? value : nil
          end
        end
    end
  end
end
