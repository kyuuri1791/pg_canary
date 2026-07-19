# frozen_string_literal: true

using PgCanary::PgQueryRefinement

module PgCanary
  module Rules
    # join-condition columns with no index leading with
    # them. Unlike active_record_doctor's static association check, this
    # looks at joins that actually ran, so raw-SQL joins are covered too.
    class UnindexedJoin < Base
      default_enabled false

      include IndexPredicates

      def check
        detections = []
        each_scope do |scope|
          join_columns(scope).each do |table, column|
            next unless applicable_table?(table)
            next if index_leading_with?(table, column)

            detections << detection(
              table: table,
              columns: column,
              message: "Join condition on #{table}.#{column} has no index leading with it — " \
                       "joins on unindexed columns degrade as the tables grow.",
              suggestion: <<~SUGGESTION.chomp
                Consider indexing the join column:
                  CREATE INDEX index_#{table}_on_#{column} ON #{table} (#{column});
              SUGGESTION
            )
          end
        end
        detections
      end

      private

        # Unique [table, column] pairs appearing in cross-table equality
        # conditions (JOIN ... ON and comma joins connected in WHERE).
        def join_columns(scope)
          columns = []
          scope.stmt.from_clause.each do |item|
            collect_join_quals(item.unwrap) do |quals|
              columns.concat(equality_columns(scope, quals))
            end
          end
          columns.concat(equality_columns(scope, scope.where_clause)) if scope.where_clause
          columns.uniq
        end

        def collect_join_quals(node, &)
          return unless node.is_a?(PgQuery::JoinExpr)

          yield node.quals if node.quals
          collect_join_quals(node.larg&.unwrap, &)
          collect_join_quals(node.rarg&.unwrap, &)
        end

        def equality_columns(scope, clause)
          columns = []
          clause.walk_scope do |node|
            next unless node.is_a?(PgQuery::A_Expr) && node.kind == :AEXPR_OP && node.operator == "="

            left = node.lexpr&.unwrap
            right = node.rexpr&.unwrap
            next unless left.is_a?(PgQuery::ColumnRef) && right.is_a?(PgQuery::ColumnRef)

            left_resolved = scope.resolve(left)
            right_resolved = scope.resolve(right)
            next unless left_resolved && right_resolved
            next if left_resolved.first == right_resolved.first # same table: not a join condition

            columns << left_resolved << right_resolved
          end
          columns
        end
    end
  end
end
