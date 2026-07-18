# frozen_string_literal: true

module PgCanary
  module Rules
    # A scalar subquery in the SELECT list that references the outer table
    # runs once per result row (N+1 inside a single query).
    class CorrelatedSubqueryInSelect < Base
      def default_enabled
        true
      end

      def check(query)
        detections = []
        query.each_scope do |scope|
          scope.stmt.target_list.each do |target|
            res_target = unwrap_node(target)
            next unless res_target.is_a?(PgQuery::ResTarget)

            walk_within_scope(res_target.val) do |node|
              next unless node.is_a?(PgQuery::SubLink) && node.sub_link_type == :EXPR_SUBLINK

              table, column = correlated_reference(node, scope)
              next unless table && column
              next unless applicable_table?(query, table)

              detections << detection(
                query,
                table: table,
                columns: column,
                message: "Scalar subquery in the SELECT list references #{table}.#{column} from the " \
                         "outer query, so it executes once per returned row.",
                suggestion: "Rewrite as a JOIN + GROUP BY (or a LATERAL join) so the lookup runs " \
                            "once as a set operation."
              )
            end
          end
        end
        detections
      end

      private

        # [table, column] of the first outer-scope reference inside the
        # subquery, or nil when the subquery is self-contained.
        def correlated_reference(sublink, outer_scope)
          subselect = unwrap_node(sublink.subselect)
          return nil unless subselect.is_a?(PgQuery::SelectStmt)

          inner_names = inner_relation_names(subselect)
          found = nil
          walk_ast(subselect) do |node|
            next unless found.nil? && node.is_a?(PgQuery::ColumnRef)

            fields = column_ref_fields(node)
            next unless fields && fields.length >= 2
            next if inner_names.include?(fields[-2])

            found = outer_scope.resolve(node)
          end
          found
        end

        # Every relation name/alias visible anywhere inside the subquery.
        def inner_relation_names(subselect)
          names = []
          walk_ast(subselect) do |node|
            next unless node.is_a?(PgQuery::RangeVar)

            names << node.relname
            names << node.alias.aliasname if node.alias
          end
          names
        end
    end
  end
end
