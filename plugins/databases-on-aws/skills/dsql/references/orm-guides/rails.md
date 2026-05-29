# Ruby on Rails Migration Guide for DSQL

How to run Rails applications against Aurora DSQL.

Sources:

- [Rails Sample](https://github.com/aws-samples/aurora-dsql-samples/tree/main/ruby/rails)
- [Ruby pg Driver Sample](https://github.com/aws-samples/aurora-dsql-samples/tree/main/ruby/ruby-pg)
- [Rails with IAM Auth](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/SECTION_program-with-ruby-rails.html)

---

## 1. Dependencies

```ruby
# Gemfile
gem 'pg'
gem 'aws-sdk-dsql'
```

## 2. Database Configuration

```yaml
# config/database.yml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: 10
  host: <%= ENV['DSQL_ENDPOINT'] %>
  port: 5432
  database: postgres
  sslmode: require
```

### IAM Token Initializer

```ruby
# config/initializers/dsql_auth.rb
require 'aws-sdk-dsql'

ActiveSupport.on_load(:active_record) do
  ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.class_eval do
    private
    alias_method :original_connect, :connect
    def connect
      client = Aws::DSQL::Client.new(region: ENV['AWS_REGION'] || 'us-east-1')
      @connection_parameters[:password] = client.generate_db_connect_admin_auth_token(
        hostname: ENV['DSQL_ENDPOINT']
      )
      @connection_parameters[:user] = 'admin'
      original_connect
    end
  end
end
```

## 3. Model Changes

### UUID Primary Keys

```ruby
# config/initializers/generators.rb
Rails.application.config.generators do |g|
  g.orm :active_record, primary_key_type: :uuid
end
```

### Associations Without FK Constraints

```ruby
class Ticket < ApplicationRecord
  belongs_to :organization, class_name: 'Organization', foreign_key: 'org_id', optional: false
  # Rails belongs_to works without DB FK — just does SELECT to load

  validate :validate_foreign_keys

  private
  def validate_foreign_keys
    errors.add(:org_id, 'does not exist') unless Organization.exists?(org_id)
  end
end
```

### ENUM → String + Validation

```ruby
class Ticket < ApplicationRecord
  STATUSES = %w[open in_progress resolved closed].freeze
  validates :status, inclusion: { in: STATUSES }
end
```

## 4. Migrations (One DDL Per File)

```ruby
# BAD: Multiple DDL in one migration
class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users, id: :uuid do |t|
      t.string :email, null: false
    end
    add_index :users, :email, unique: true  # Second DDL — fails
  end
end

# GOOD: Separate migrations
class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users, id: :uuid do |t|
      t.string :email, null: false
    end
  end
end

class AddUsersEmailIndex < ActiveRecord::Migration[7.1]
  def up
    execute "CREATE UNIQUE INDEX ASYNC idx_users_email ON users (email)"
  end
  def down
    execute "DROP INDEX IF EXISTS idx_users_email"
  end
end
```

**Remove all `foreign_key: true` from migrations.**

## 5. OCC Retry Concern

```ruby
# app/models/concerns/occ_retryable.rb
module OccRetryable
  extend ActiveSupport::Concern

  class_methods do
    def with_occ_retry(max_retries: 5, &block)
      attempt = 0
      begin
        ActiveRecord::Base.transaction(&block)
      rescue ActiveRecord::SerializationFailure => e
        attempt += 1
        if attempt < max_retries
          sleep([0.05 * (2 ** attempt) + rand(0.0..0.05), 5.0].min)
          retry
        else
          raise
        end
      end
    end
  end
end

# Usage:
class TicketService
  include OccRetryable
  def self.create_ticket(params)
    with_occ_retry { Ticket.create!(params) }
  end
end
```

## 6. Things to Avoid

| Rails Feature                   | Issue                     | Alternative                       |
| ------------------------------- | ------------------------- | --------------------------------- |
| `foreign_key: true`             | Not supported             | Model validations                 |
| `add_foreign_key`               | Not supported             | Skip                              |
| `dependent: :destroy` (with FK) | No DB cascade             | `before_destroy` callback         |
| `add_index` (standard)          | Needs ASYNC               | `execute "CREATE INDEX ASYNC..."` |
| `change_column`                 | ALTER TYPE not supported  | Recreate table                    |
| `remove_column`                 | DROP COLUMN not supported | Recreate table                    |

## 7. Cascade Deletes (Without FK)

```ruby
class Organization < ApplicationRecord
  has_many :tickets, foreign_key: 'org_id'

  before_destroy :cascade_cleanup
  private
  def cascade_cleanup
    Ticket.where(org_id: id).update_all(status: 'cancelled')
  end
end
```

## 8. Checklist

- [ ] Add `aws-sdk-dsql` gem
- [ ] Configure IAM token initializer
- [ ] Set `database: postgres`, `sslmode: require`
- [ ] Use `id: :uuid` for all tables
- [ ] Remove all `foreign_key: true` from migrations
- [ ] Add model-level FK validation
- [ ] Split migrations to one DDL per file
- [ ] Use `execute "CREATE INDEX ASYNC..."` for indexes
- [ ] Add OCC retry concern
- [ ] Set `config.active_record.schema_format = :sql`
- [ ] Test `dependent: :destroy` via callbacks
