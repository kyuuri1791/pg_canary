# frozen_string_literal: true

require "cgi"

module PgCanary
  # Rack middleware: collects the detections raised while the request runs
  # (via the thread-local collector .collect appends to), collapses repeats
  # of the same query within that request, and injects a footer panel into
  # HTML responses.
  class Middleware
    COLLECTOR_KEY = :pg_canary_request_detections

    def self.collect(detections)
      Thread.current[COLLECTOR_KEY]&.concat(detections)
    end

    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) unless active?

      detections = []
      previous = Thread.current[COLLECTOR_KEY]
      Thread.current[COLLECTOR_KEY] = detections
      status, headers, body = @app.call(env)
      detections = dedup(detections)
      return [status, headers, body] if detections.empty?

      inject(status, headers, body, detections)
    ensure
      Thread.current[COLLECTOR_KEY] = previous
    end

    private

    def active?
      PgCanary.config.enabled
    end

    # Collapses repeats of the same (query, rule) — e.g. an N+1 loop — into
    # a single panel entry. Scoped to this one request: a fresh page load
    # (or a reload of the same page) always shows detections again.
    def dedup(detections)
      detections.uniq { |d| [d.fingerprint, d.rule_name] }
    end

    def inject(status, headers, body, detections)
      return [status, headers, body] unless html_response?(headers)

      content = +""
      body.each { |part| content << part }
      body.close if body.respond_to?(:close)

      snippet = footer_panel(detections)
      if content.include?("</body>")
        content = content.sub("</body>", "#{snippet}</body>")
      else
        content << snippet
      end

      headers = headers.merge("Content-Length" => content.bytesize.to_s) if content_length?(headers)
      [status, headers, [content]]
    end

    def html_response?(headers)
      headers.any? { |k, v| k.to_s.casecmp("content-type").zero? && v.to_s.include?("text/html") }
    end

    def content_length?(headers)
      headers.any? { |k, _| k.to_s.casecmp("content-length").zero? }
    end

    def footer_panel(detections)
      items = detections.map do |d|
        <<~HTML
          <div style="padding:8px 12px;border-top:1px solid #444;">
            <div>
              <strong style="color:#{d.severity == :error ? "#ff6b6b" : "#ffd93d"};">#{h(d.rule_name)}</strong>
              <span style="opacity:.7;">(#{h(d.severity)})</span>
              #{subject_span(d)}
            </div>
            <pre style="margin:4px 0;white-space:pre-wrap;color:#9ecbff;">#{h(d.truncated_sql)}</pre>
            <div style="white-space:pre-wrap;">→ #{h(d.message)}</div>
            #{%(<pre style="margin:4px 0;white-space:pre-wrap;color:#98c379;">#{h(d.suggestion)}</pre>) if d.suggestion}
            #{%(<div style="opacity:.7;">at #{h(d.location)}</div>) if d.location}
          </div>
        HTML
      end

      <<~HTML
        <div id="pg-canary-panel" style="position:fixed;left:0;right:0;bottom:0;max-height:45vh;overflow-y:auto;z-index:2147483647;background:#1e1e1e;color:#eee;font:12px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;box-shadow:0 -2px 8px rgba(0,0,0,.4);">
          <div style="display:flex;justify-content:space-between;align-items:center;padding:6px 12px;background:#2d2d2d;">
            <strong>🐤 PgCanary — #{detections.size} anti-pattern#{"s" if detections.size > 1} detected</strong>
            <button onclick="document.getElementById('pg-canary-panel').remove()" style="background:none;border:1px solid #666;color:#eee;cursor:pointer;padding:2px 8px;">×</button>
          </div>
          #{items.join}
        </div>
      HTML
    end

    def subject_span(detection)
      return "" unless detection.table

      subject = detection.table
      subject += ".#{detection.columns.join(", ")}" if detection.columns.any?
      %(<span style="opacity:.8;"> — #{h(subject)}</span>)
    end

    def h(value)
      CGI.escapeHTML(value.to_s)
    end
  end
end
