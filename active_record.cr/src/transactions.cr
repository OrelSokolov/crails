# Transactions: BEGIN/COMMIT/SAVEPOINT on a connection pinned to the
# current fiber, + with_lock/lock!. Oracle-verified against
# activerecord 8.1.4 (tx_* cases in oracle/expected.yml).
#
# Reproduced semantics:
# - `ActiveRecord::Rollback` at the outermost level rolls back silently and
#   the block returns nil;
# - `ActiveRecord::Rollback` raised in a JOINED nested block is swallowed
#   and NOTHING is rolled back (verified on 8.1.4: writes before and after
#   the raise both commit);
# - `requires_new: true` → SAVEPOINT; Rollback/exception rolls back to the
#   savepoint only; other exceptions re-raise after the savepoint rollback;
# - after_commit fires on the real COMMIT (deferred from savepoints),
#   after_rollback on any rollback (including savepoint ones); without an
#   open transaction both fire per-op (implicit auto-commit tx).
#
# All model DB access routes through `Base.__session` so that queries
# issued inside a transaction reuse the pinned connection.

module ActiveRecord
  # Rails: `raise ActiveRecord::Rollback` to unwind silently.
  class Rollback < Exception
  end

  class Base
    # Receiver for queries: the pinned tx connection or the pool.
    alias TxSession = DB::Database | DB::Connection

    # Records mutated inside the transaction: {record, event} pairs, fired
    # as after_commit/after_rollback at COMMIT/ROLLBACK time.
    class TxContext
      getter fiber : Fiber
      getter conn : DB::Connection
      getter records = [] of Tuple(Base, Symbol)
      property depth = 0

      def initialize(@fiber, @conn)
      end
    end

    @@tx_stack = [] of TxContext

    ISOLATION_LEVELS = {
      read_uncommitted: "READ UNCOMMITTED",
      read_committed:   "READ COMMITTED",
      repeatable_read:  "REPEATABLE READ",
      serializable:     "SERIALIZABLE",
    }

    def self.__current_tx : TxContext?
      @@tx_stack.find { |tx| tx.fiber == Fiber.current }
    end

    def self.__session : TxSession
      if tx = __current_tx
        tx.conn
      else
        connection
      end
    end

    def self.transaction(requires_new : Bool = false, isolation : Symbol? = nil, &block)
      if tx = __current_tx
        raise ArgumentError.new("cannot set isolation with nested transaction") if isolation
        if requires_new
          __savepoint_transaction(tx, &block)
        else
          # Joined: Rollback is swallowed, the outer tx commits (8.1.4).
          begin
            yield
          rescue ex : Rollback
            nil
          end
        end
      else
        __outermost_transaction(isolation, &block)
      end
    end

    def self.__outermost_transaction(isolation : Symbol?, &block)
      conn = connection.checkout
      begin
        if iso = isolation
          level = ISOLATION_LEVELS[iso]?
          raise ArgumentError.new("invalid isolation level #{iso}") unless level
          conn.exec("BEGIN TRANSACTION ISOLATION LEVEL #{level}")
        else
          conn.exec("BEGIN")
        end
        tx = TxContext.new(Fiber.current, conn)
        @@tx_stack << tx
        begin
          result = yield
          conn.exec("COMMIT")
          __fire_after_commit(tx)
          result
        rescue ex : Rollback
          conn.exec("ROLLBACK") rescue nil
          __fire_after_rollback(tx)
          nil
        rescue ex
          conn.exec("ROLLBACK") rescue nil
          __fire_after_rollback(tx)
          raise ex
        ensure
          @@tx_stack.delete(tx)
        end
      ensure
        conn.release
      end
    end

    def self.__savepoint_transaction(tx : TxContext, &block)
      tx.depth += 1
      name = "ar_tx_sp_#{tx.depth}"
      conn = tx.conn
      scope = tx.records.size
      conn.exec("SAVEPOINT #{name}")
      begin
        result = yield
        conn.exec("RELEASE SAVEPOINT #{name}")
        # records stay registered: after_commit fires on the real COMMIT
        result
      rescue ex : Rollback
        conn.exec("ROLLBACK TO SAVEPOINT #{name}")
        conn.exec("RELEASE SAVEPOINT #{name}")
        __fire_after_rollback(tx, scope)
        nil
      rescue ex
        conn.exec("ROLLBACK TO SAVEPOINT #{name}") rescue nil
        conn.exec("RELEASE SAVEPOINT #{name}") rescue nil
        __fire_after_rollback(tx, scope)
        raise ex
      ensure
        tx.depth -= 1
      end
    end

    # Defers after_commit to the open transaction, no-op otherwise (the
    # caller fires the callback inline on auto-commit success).
    def self.__register_in_transaction(record : Base, event : Symbol) : Nil
      __current_tx.try { |tx| tx.records << {record, event} }
    end

    def self.__fire_after_commit(tx : TxContext) : Nil
      tx.records.each { |record, event| record.__run_after_commit(event) }
      tx.records.clear
    end

    # Fires after_rollback for records registered since `from` and removes
    # them (they must not double-fire at the outer rollback).
    def self.__fire_after_rollback(tx : TxContext, from : Int32 = 0) : Nil
      (tx.records.size - from).times do
        record, event = tx.records.pop
        record.__run_after_rollback(event)
      end
    end

    # `on:` filter for after_commit/after_rollback callbacks: accepts a
    # Symbol or an Array(Symbol) splat from the macro.
    def __tx_event_match?(event : Symbol, on : Symbol | Array(Symbol)) : Bool
      on.is_a?(Array) ? on.includes?(event) : on == event
    end

    def transaction(requires_new : Bool = false, isolation : Symbol? = nil, &block)
      self.class.transaction(requires_new: requires_new, isolation: isolation) { yield }
    end

    # SELECT ... FOR UPDATE on the current (pinned) connection; reloads the
    # row under lock, mirroring Rails `lock!`.
    def lock! : self
      raise ActiveRecordError.new("can't lock a new record") if new_record?
      pk = @id.not_nil!
      cols = self.class.__column_names.map { |c| %("#{c.gsub('"', "")}") }.join(", ")
      sql = "SELECT #{cols} FROM #{self.class.quoted_table_name} WHERE \"id\" = $1 FOR UPDATE"
      record = nil
      Base.__session.query(sql, args: [pk.as(DB::Any)]) do |rs|
        rs.each { record = self.class.__from_row(rs) }
      end
      record || raise RecordNotFound.new("Couldn't find #{self.class} with 'id'=#{pk}")
    end

    # Rails: reload + transaction(requires_new: true) + lock! + block.
    def with_lock(&) : Nil
      self.class.transaction(requires_new: true) do
        lock!
        yield
      end
    end
  end
end
