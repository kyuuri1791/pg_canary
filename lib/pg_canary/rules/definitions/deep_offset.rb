# frozen_string_literal: true

module PgCanary
  module Rules
    # OFFSET-based pagination reads and throws away every skipped row, so
    # deep pages degrade linearly. The offset value is read from the runtime
    # bind ($n), which static SQL linters cannot do.
    # Threshold: config.rules.deep_offset.threshold (default 1000).
    class DeepOffset < Base
      def default_enabled
        true
      end

      def size_dependent?
        false
      end

      def self.options
        { threshold: 1000 }
      end

      def check(query)
        threshold = rule_config(query).threshold
        detections = []
        query.each_scope do |scope|
          next unless scope.stmt.limit_offset

          value = numeric_value(query, scope.stmt.limit_offset)
          next unless value && value >= threshold

          detections << detection(
            query,
            table: scope.tables.length == 1 ? scope.tables.first : nil,
            message: "OFFSET #{value} reads and discards #{value} rows before returning anything — " \
                     "offset pagination degrades linearly with page depth.",
            suggestion: <<~SUGGESTION.chomp
              Consider keyset pagination instead:
                WHERE (created_at, id) < (:last_seen_created_at, :last_seen_id) ORDER BY created_at DESC, id DESC LIMIT n
            SUGGESTION
          )
        end
        detections
      end

      private

      def numeric_value(query, node)
        node = strip_type_casts(node)
        case node
        when PgQuery::A_Const
          value = constant_value(node)
          value.is_a?(Numeric) ? value.to_i : nil
        when PgQuery::ParamRef
          begin
            Integer(query.bind_value(node.number), exception: false)
          rescue TypeError
            nil
          end
        end
      end
    end
  end
end
