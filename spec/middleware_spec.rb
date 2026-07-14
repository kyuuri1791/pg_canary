# frozen_string_literal: true

RSpec.describe PgCanary::Middleware do
  def html_app(body = "<html><body><h1>hi</h1></body></html>")
    lambda do |_env|
      User.where("name LIKE ?", "%taro%").to_a
      [200, { "Content-Type" => "text/html", "Content-Length" => body.bytesize.to_s }, [body]]
    end
  end

  def run(app)
    described_class.new(app).call({})
  end

  it "injects the footer panel into HTML responses" do
    status, headers, body = run(html_app)
    content = body.join

    expect(status).to eq(200)
    expect(content).to include("pg-canary-panel")
    expect(content).to include("leading_wildcard_like")
    expect(content.index("pg-canary-panel")).to be < content.index("</body>")
    expect(headers["Content-Length"]).to eq(content.bytesize.to_s)
  end

  it "escapes HTML in detection content" do
    _, _, body = run(lambda do |_env|
      User.where("name LIKE ?", "%<script>alert(1)</script>").to_a
      [200, { "Content-Type" => "text/html" }, ["<html><body></body></html>"]]
    end)

    content = body.join
    expect(content).not_to include("<script>alert(1)")
    expect(content).to include("&lt;script&gt;")
  end

  it "leaves non-HTML responses untouched" do
    app = lambda do |_env|
      User.where("name LIKE ?", "%taro%").to_a
      [200, { "Content-Type" => "application/json" }, ['{"ok":true}']]
    end

    _, _, body = run(app)

    expect(body.join).to eq('{"ok":true}')
  end

  it "leaves responses untouched when nothing was detected" do
    app = ->(_env) { [200, { "Content-Type" => "text/html" }, ["<html><body></body></html>"]] }

    _, _, body = run(app)

    expect(body.join).not_to include("pg-canary-panel")
  end

  it "passes through when pg_canary is disabled" do
    PgCanary.config.enabled = false

    _, _, body = run(html_app)

    expect(body.join).not_to include("pg-canary-panel")
  end

  it "collapses repeats of the same query within one request (e.g. an N+1 loop)" do
    app = lambda do |_env|
      3.times { User.where("name LIKE ?", "%taro%").to_a }
      [200, { "Content-Type" => "text/html" }, ["<html><body></body></html>"]]
    end

    _, _, body = run(app)

    expect(body.join.scan("leading_wildcard_like").size).to eq(1)
  end

  it "shows the same detection again on a later request, not just once per process" do
    first_body = run(html_app).last.join
    second_body = run(html_app).last.join

    expect(first_body).to include("leading_wildcard_like")
    expect(second_body).to include("leading_wildcard_like")
  end
end
