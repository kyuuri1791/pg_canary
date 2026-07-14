# frozen_string_literal: true

module PgCanary
  module Rules
    # Tier 2 (opt-in): UNION without ALL deduplicates the combined result by
    # sorting/hashing all rows. When the branches cannot overlap (or
    # duplicates are acceptable), UNION ALL skips that work. Whether
    # deduplication is intended is the author's call, hence opt-in.
    class UnionInsteadOfUnionAll < Base
      def default_enabled
        false
      end

      def size_dependent?
        false
      end

      def check(query)
        union = query.scopes.find { |scope| scope.stmt.op == :SETOP_UNION && !scope.stmt.all }
        return [] unless union

        [detection(
          query,
          message: "UNION (without ALL) sorts/hashes the entire combined result to remove duplicates.",
          suggestion: "If the branches cannot produce overlapping rows — or duplicates are acceptable — use UNION ALL."
        )]
      end
    end
  end
end
