# frozen_string_literal: true

module PgCanary
  module Rules
    # Tier 2 (opt-in): equality/range predicates on columns with no index
    # whose leading column could serve them. Depends on production table
    # size — a 30-row lookup table is fine without indexes — hence disabled
    # by default and gated by config.table_size_hints.
    class UnindexedWhere < Base
      def default_enabled
        false
      end

      def size_dependent?
        true
      end

      def check(query)
        query.each_scope.with_object([]) do |scope, detections|
          next unless scope.where_clause

          predicate_columns(query, scope).each do |table, columns|
            next unless applicable_table?(query, table)
            next if served_by_index?(query, table, columns)

            detections << build(query, table, columns)
          end
        end
      end

      private

      # => { table => [column, ...] } for plain-column predicates in WHERE.
      def predicate_columns(_query, scope)
        result = Hash.new { |h, k| h[k] = [] }
        walk_within_scope(scope.where_clause) do |node|
          next unless node.is_a?(PgQuery::A_Expr) && indexable_predicate?(node)

          [node.lexpr, node.rexpr].each do |side|
            column_ref = unwrap_node(side)
            next unless column_ref.is_a?(PgQuery::ColumnRef)
            next unless constant_side?(node, side)

            table, column = scope.resolve(column_ref)
            result[table] << column if table && column
          end
        end
        result.transform_values(&:uniq)
      end

      def indexable_predicate?(a_expr)
        comparison_expr?(a_expr) ||
          %i[AEXPR_IN AEXPR_BETWEEN AEXPR_LIKE AEXPR_ILIKE].include?(a_expr.kind)
      end

      # Only count `column <op> constant-ish` predicates; column-to-column
      # comparisons (join conditions in WHERE) are not our business here.
      def constant_side?(a_expr, column_side)
        other = a_expr.lexpr.equal?(column_side) ? a_expr.rexpr : a_expr.lexpr
        node = strip_type_casts(other)
        case node
        when PgQuery::A_Const, PgQuery::ParamRef
          true
        when PgQuery::List
          node.items.all? { |i| strip_type_casts(i).is_a?(PgQuery::A_Const) || strip_type_casts(i).is_a?(PgQuery::ParamRef) }
        else
          false
        end
      end

      # Leftmost-prefix rule: an index helps when its leading column is one
      # of the predicate columns.
      def served_by_index?(query, table, columns)
        query.indexes(table).any? do |index|
          index.leading_column && columns.include?(index.leading_column)
        end
      end

      def build(query, table, columns)
        column_list = columns.join(", ")
        detection(
          query,
          table: table,
          columns: columns,
          message: "No index leads with any of the WHERE predicate columns (#{table}.#{column_list}). " \
                   "Depending on production row counts, this becomes a full scan.",
          suggestion: <<~SUGGESTION.chomp
            Consider adding an index (equality columns first):
              CREATE INDEX index_#{table}_on_#{columns.join("_and_")} ON #{table} (#{column_list});
          SUGGESTION
        )
      end
    end
  end
end
