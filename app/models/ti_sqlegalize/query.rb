# encoding: utf-8
module TiSqlegalize
  class Query
    @queue = :query

    META_REVISION = 1
    DEFAULT_QUOTA = 100_000
    DEFAULT_TTL = 3600
    CURSOR_BATCH = 1024

    attr_accessor :id, :statement, :status, :quota, :count, :schema, :message

    def initialize(statement, quota: DEFAULT_QUOTA, ttl: DEFAULT_TTL)
      @statement = statement.to_s
      @quota = quota.to_i
      @count = 0
      @ttl = ttl
      @schema = []
      @message = ''
    end

    def create!
      unless id
        token = SecureRandom.hex(16)
        seq = Resque.redis.incr('ti_sqlegalize:query:seq')
        @id = [token, seq].join('_')
        @status = :created
        save!
      end
    end

    def save!
      k = self.class.meta_key id
      Resque.redis.set(k, meta.to_json) if k
    end

    def meta
      {
        status: status.to_s,
        statement: statement.to_s,
        count: count.to_i,
        quota: quota.to_i,
        schema: schema.map { |c| [c.name, c.domain.name] },
        message: message.to_s
      }
    end

    def [](offset, limit)
      k = self.class.main_key id
      if k
        Resque.redis.lrange(k, offset, offset + limit - 1).map do |r|
                                                             MultiJson.load r
                                                           end
      else
        []
      end
    end

    def <<(rows)
      k = self.class.main_key id
      if k && !rows.empty?
        self.count, _ = Resque.redis.multi do |r|
                          r.rpush(k, rows.map(&:to_json))
                          r.expire(k, @ttl)
                        end
      end
    end

    def time_left
      k = self.class.main_key id
      Resque.redis.ttl(k) if k
    end

    def expire_after(timeout)
      k = self.class.main_key id
      Resque.redis.expire(k, timeout) if k
    end

    def enqueue!
      Resque.enqueue(self.class, id) if id
    end

    def execute(statement)
      @db ||= TiSqlegalize::Config.database
      @db.execute statement
    end

    def close
      @db.close if @db && @db.respond_to?(:close)
    end

    def run
      begin
        cursor = execute statement
        if cursor.has_more?
          self.status = :running
          self.schema = cursor.schema.map do |name, type|
            domain = Domain.find(type)
            Column.new(name: name, domain: domain)
          end
          save!
          fetch cursor
        end
      rescue
        Rails.logger.error "Error while executing query #{statement}: #{$!} (#{$!.message})\n#{$!.backtrace.join("\n")}"
        self.status = :error
        self.message = $!.message
        save!
      else
        self.status = :finished
        save!
        if cursor.respond_to?(:close) && cursor.respond_to?(:open?)
          cursor.close if cursor.open?
        end
      end
    end

    def fetch(cursor)
      cursor.each_slice(CURSOR_BATCH) do |chunk|
        rows = if count + chunk.length <= quota
                 chunk
               else
                 chunk.take(quota - count)
               end
        self << rows
        break if count >= quota
      end
    end

    def self.find(id)
      k = meta_key id
      m = Resque.redis.get(k) if k
      if m
        meta = MultiJson.load m
        query = new(meta['statement'], quota: meta['quota'])
        query.id = id
        query.status = meta['status'].to_sym
        query.count = meta['count']
        query.schema = meta['schema'].map do |name, type|
                         Column.new(name: name, domain: Domain.find(type))
                       end
        query.message = meta['message']
        query
      end
    end

    def self.main_key(id)
      "ti_sqlegalize:query:#{META_REVISION}:#{id}" if id
    end

    def self.meta_key(id)
      "ti_sqlegalize:query:#{META_REVISION}:#{id}:meta" if id
    end

    def self.perform(id)
      query = find id
      if query
        Rails.logger.info "Job #{id}: #{query.statement}"
        query.run
      end
    end
  end
end
