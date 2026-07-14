# frozen_string_literal: true

module PgCanary
  # Subscribes to sql.active_record, filters events down to likely SELECT
  # statements, and hands them to the Detector. Stateless per event, so
  # everything lives at class level.
  class Subscriber
    # Event names that never carry application SELECTs. "SCHEMA" also covers
    # the catalog queries ActiveRecord's schema cache runs on our behalf.
    IGNORED_NAMES = %w[SCHEMA TRANSACTION].freeze
    # Cheap pre-filter before paying for a real parse.
    SELECT_PREFIX = %r{\A\s*(?:/\*.*?\*/\s*)*(?:SELECT|WITH)\b}im

    class << self
      def subscribe!
        @subscribe ||= ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          next unless analysis_target?(payload)

          detections = detector.call(payload)
          Middleware.collect(detections) if detections.any?
        rescue StandardError => e
          PgCanary.internal_error(e)
        end
      end

      private

      def analysis_target?(payload)
        return false if payload[:cached]
        return false if payload[:name] && IGNORED_NAMES.include?(payload[:name])
        return false unless payload[:sql]&.match?(SELECT_PREFIX)

        !!payload[:connection]&.adapter_name&.match?(/postg/i)
      end

      def detector
        @detector ||= Detector.new(PgCanary.config)
      end
    end
  end
end
