# frozen_string_literal: true

module PgCanary
  module Rules
    MAX_SQL_LENGTH = 500

    # What a rule's #check returns: one anti-pattern finding — which rule
    # fired, on which query, which table/columns are involved, why it is a
    # problem, and how to fix it.
    Detection = Struct.new(
      :rule_name, :sql, :table, :columns,
      :message, :suggestion, :location, :fingerprint,
      keyword_init: true
    ) do
      def truncated_sql
        squashed = sql.to_s.strip.gsub(/\s+/, " ")
        squashed.length > MAX_SQL_LENGTH ? "#{squashed[0, MAX_SQL_LENGTH]}…" : squashed
      end
    end
  end
end
