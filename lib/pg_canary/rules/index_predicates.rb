# frozen_string_literal: true

module PgCanary
  module Rules
    # Predicates over index metadata, for rules that stay silent when a
    # suitable index exists. Include only in rules that need them.
    module IndexPredicates
      TRGM_ACCESS_METHODS = %w[gin gist].freeze

      private

        def trgm_index?(table, column)
          indexes(table).any? do |index|
            TRGM_ACCESS_METHODS.include?(index.using) &&
              index.columns.include?(column) &&
              index.opclasses[column].to_s.include?("trgm")
          end
        end

        def gin_index_on?(table, column)
          indexes(table).any? { |index| index.using == "gin" && index.columns.include?(column) }
        end

        # Any expression index whose expression mentions the column.
        # Deliberately loose (column-level word match, not expression
        # equality) to avoid false positives.
        def expression_index_referencing?(table, column)
          indexes(table).any? do |index|
            index.expressions&.match?(/\b#{Regexp.escape(column)}\b/)
          end
        end

        # Whether any index's leading column is +column+ (leftmost-prefix rule).
        def index_leading_with?(table, column)
          indexes(table).any? { |index| index.leading_column == column }
        end
    end
  end
end
