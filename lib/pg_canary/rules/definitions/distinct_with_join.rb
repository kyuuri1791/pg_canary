# frozen_string_literal: true

module PgCanary
  module Rules
    # DISTINCT combined with JOIN. Frequently the DISTINCT
    # only exists to undo row fanout caused by the join — the work of
    # producing and then deduplicating the duplicates is wasted. Legitimate
    # uses exist, hence opt-in.
    class DistinctWithJoin < Base
      default_enabled false

      using PgCanary::PgQueryRefinement

      def check
        detections = []
        each_scope do |scope|
          next unless scope.stmt.distinct_clause.any?
          next unless joined?(scope)

          detections << detection(
            table: scope.tables.first,
            message: "DISTINCT combined with JOIN often hides row fanout from the join: duplicate rows " \
                     "are produced and then sorted/hashed away.",
            suggestion: "If DISTINCT only compensates for join duplication, rewrite the join as a " \
                        "semi-join: WHERE EXISTS (SELECT 1 FROM joined WHERE joined.ref_id = t.id)."
          )
        end
        detections
      end

      private

        def joined?(scope)
          scope.stmt.from_clause.any? { |item| item.unwrap.is_a?(PgQuery::JoinExpr) }
        end
    end
  end
end
