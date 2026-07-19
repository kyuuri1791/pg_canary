# frozen_string_literal: true

module PgCanary
  module Rules
    # A scalar subquery in the SELECT list that references the outer table
    # runs once per result row (N+1 inside a single query).
    class CorrelatedSubqueryInSelect < Base
      default_enabled true

      using PgCanary::PgQueryRefinement

      def check
        detections = []
        each_scope do |scope|
          scope.stmt.target_list.each do |target|
            res_target = target.unwrap
            next unless res_target.is_a?(PgQuery::ResTarget)

            res_target.val.walk_scope do |node|
              next unless node.is_a?(PgQuery::SubLink) && node.sub_link_type == :EXPR_SUBLINK

              table, column = correlated_reference(node, scope)
              next unless table && column
              next unless applicable_table?(table)

              detections << detection(
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
          subselect = sublink.subselect&.unwrap
          return nil unless subselect.is_a?(PgQuery::SelectStmt)

          inner_names = inner_relation_names(subselect)
          found = nil
          subselect.walk do |node|
            next unless found.nil? && node.is_a?(PgQuery::ColumnRef)

            fields = node.field_names
            next unless fields && fields.length >= 2
            next if inner_names.include?(fields[-2])

            found = outer_scope.resolve(node)
          end
          found
        end

        # Every relation name/alias visible anywhere inside the subquery.
        def inner_relation_names(subselect)
          names = []
          subselect.walk do |node|
            next unless node.is_a?(PgQuery::RangeVar)

            names << node.relname
            names << node.alias.aliasname if node.alias
          end
          names
        end
    end
  end
end
