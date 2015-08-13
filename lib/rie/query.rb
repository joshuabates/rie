module Rie
  class Query
    def self.empty(db)
      new(db, nil, {}, [])
    end

    def initialize(db, find, in_, where, with)
      @db = db
      @find = find
      @in = in_
      @where = where
      @with = with
    end

    def vars
      where_datoms.flat_map do |datom|
        datom.select { |e| symbol?(e) && e.to_s.start_with?('?') }
      end.map(&method(:binder_to_sym))
    end

    def in(*args)
      declared = args.last.is_a?(Hash) ? args.pop : {}
      undeclared = args

      new_in = @in.merge(declared)

      undeclared.each { |a| new_in[a] = nil }

      Query.new(@db, @find, new_in, @where, @with)
    end

    def with(vars={})
      Query.new(@db, @find, @in, @where, @with.merge(vars))
    end

    def bind(new_constants)
      Query.new(constants.merge(new_constants))
    end

    def clause(entity, attr, value, transaction=nil)
      transaction ||= db.transaction
      Query.new(db, target, constants, clauses + [entity, attr, value, transaction])
    end

    def find(*new_target)
      Query.new(db, new_target, constants, clauses)
    end

    def in_vars
      @in_vars ||= @in.keys
    end

    def with_values
      @with_values ||= in_vars.map do |var|
        value = @with.fetch(var)
        type = type_for(var)

        type.dump(value)
      end
    end

    def free_vars
      in_vars - @with.keys
    end

    def type_for(var)
      raise 'TODO'
    end

    def to_edn
      {
        :find => find,
        :in => [:'$', *in_vars],
        :where => @where,
      }
    end

    def raw_results
      db.q(to_edn, *with_values)
    end

    include Enumerable
    def each(&b)
      raw_results.each do |e|
        out_hash = find.zip(e).each_with_object({}) do |out, (var, val)|
          out[var] = type_for(var).load(val)
        end

        yield out_hash
      end
    end
  end
end
