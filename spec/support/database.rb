# frozen_string_literal: true

module PgCanarySpec
  module Database
    module_function

    def connect!
      ActiveRecord::Base.establish_connection(
        adapter: "postgresql",
        host: ENV.fetch("PG_CANARY_DB_HOST", "localhost"),
        port: ENV.fetch("PG_CANARY_DB_PORT", 5432),
        username: ENV.fetch("PG_CANARY_DB_USER", "canary"),
        password: ENV.fetch("PG_CANARY_DB_PASSWORD", "canary"),
        database: ENV.fetch("PG_CANARY_DB_NAME", "pg_canary_test")
      )
    end

    def load_schema!
      connection = ActiveRecord::Base.connection
      connection.execute(<<~SQL)
        CREATE EXTENSION IF NOT EXISTS pg_trgm;

        DROP TABLE IF EXISTS users, orders, prefectures CASCADE;

        CREATE TABLE users (
          id bigserial PRIMARY KEY,
          name varchar,
          email varchar,
          bio text,
          age integer,
          score numeric,
          prefecture_id bigint,
          settings jsonb,
          preferences jsonb,
          metadata jsonb,
          tags text[],
          badges text[],
          created_at timestamp
        );
        CREATE INDEX index_users_on_email ON users (email);
        CREATE INDEX index_users_on_bio_trgm ON users USING gin (bio gin_trgm_ops);
        CREATE INDEX index_users_on_lower_email ON users (lower(email));
        CREATE INDEX index_users_on_preferences ON users USING gin (preferences);
        CREATE INDEX index_users_on_metadata_plan ON users ((metadata ->> 'plan'));
        CREATE INDEX index_users_on_badges ON users USING gin (badges);

        CREATE TABLE orders (
          id bigserial PRIMARY KEY,
          user_id bigint,
          status varchar,
          total numeric,
          created_at timestamp
        );
        CREATE INDEX index_orders_on_user_id_and_created_at ON orders (user_id, created_at);

        CREATE TABLE prefectures (
          id bigserial PRIMARY KEY,
          name varchar
        );
      SQL
    end
  end
end

class User < ActiveRecord::Base; end
class Order < ActiveRecord::Base; end
class Prefecture < ActiveRecord::Base; end
