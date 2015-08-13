module Rie
  module Model
    def self.included(base)
      base.class_eval do
        @attributes = {}
        @base_attributes = {}
        @defaults = {}
        @validator = Validator.new(base)

        const_set :Finder, Class.new(BaseFinder) {
          # we use a constant here so that `super` works
          # in overriding generated methods
          const_set :AttributeMethods, Module.new
          include self::AttributeMethods
          define_method(:model) { base }
        }

        const_set :Changer, Class.new(BaseChanger) {
          # as above
          const_set :AttributeMethods, Module.new
          include self::AttributeMethods
          define_method(:model) { base }
        }

        extend Rie::Model::ClassMethods
      end
    end

    @registry = {}
    @logger = Logger.new($stderr)
    @logger.level = Logger::WARN

    class << self
      attr_reader :registry

      def install_schemas!
        registry.values.each(&:install_schema!)
      end

      def install_bases!
        registry.values.each(&:install_base!)
      end

      def install!
        install_bases!
        install_schemas!
      end

      attr_accessor :namespace, :partition, :uri, :logger
      def configure(&b)
        yield self
      end
    end

    module ClassMethods
      attr_reader :attributes
      attr_reader :defaults
      attr_reader :validator
      attr_reader :datomic_name
      attr_reader :namespace
      attr_reader :partition
      attr_reader :base_attributes

      def transact(edn)
        Model.logger.info("datomic.transact #{Dalton::Connection.convert_datoms(edn).to_edn}")
        connection.transact(edn)
      end

      def base_attribute(key, val)
        @base_attributes.merge!(key => val)
      end

      def uri(arg=nil)
        @uri = arg if arg
        @uri or Model.uri or raise "you must specify a datomic uri for #{self}"
      end

      def connection
        Dalton::Connection.connect(uri)
      end

      def datomic_type
        :"#{namespace}.type/#{datomic_name}"
      end

      def datomic_type_key
        :"#{namespace}/type"
      end

      def attribute(attr, datomic_key=nil, opts={})
        if datomic_key.is_a? Hash
          opts = datomic_key
          datomic_key = nil
        end

        datomic_key ||= "#{self.namespace}.#{self.datomic_name}/#{attr.to_s.tr('_', '-')}"
        define_attribute(attr, datomic_key, opts)
      end

      def define_attribute(key, datomic_key, opts={})
        @attributes[key] = Attribute.new(self, key, opts.merge(datomic_attribute: datomic_key))
        @defaults[key] = opts[:default]

        define_method(key) { self[key] }

        self::Finder::AttributeMethods.class_eval do
          define_method("by_#{key}") { |v| where(key => v) }
        end

        self::Changer::AttributeMethods.class_eval do
          define_method(key) { self[key] }
          define_method("#{key}=") { |v| self[key] = v }
        end
      end

      def get_attribute(key)
        @attributes.fetch(key) do
          raise ArgumentError, "Undefined attribute #{key} for #{self}"
        end
      end

      def finders(&b)
        self::Finder.class_eval(&b)
      end

      def changers(&b)
        self::Changer.class_eval(&b)
      end

      def validation(&b)
        @validator.specify(&b)
      end

      def finder(db, constraints=[])
        self::Finder.new(db).where(constraints)
      end

      def create!(&b)
        self::Changer.new(Dalton::Utility.tempid(partition), defaults).change!(&b)
      end

      def create(&b)
        self::Changer.new(Dalton::Utility.tempid(partition), defaults).change(&b)
      end
    end

    attr_reader :finder, :entity
    def initialize(entity)
      @entity = entity
      @finder = self.class::Finder.new(entity.db)
    end

    def inspect
      return "#<#{id}>" if Thread.current[:rie_model_inspect]

      Thread.current[:rie_model_inspect] = true

      "#<#{self.class.name} #{id} #{attributes.inspect[1..-2].strip}>"
    ensure
      Thread.current[:rie_model_inspect] = false
    end

    def id
      entity.get(:'db/id')
    end

    def db
      entity.db
    end

    def at(db)
      self.class::Finder.new(db).entity(self.id)
    end

    def [](key)
      definition = self.class.get_attribute(key)

      definition.load(entity.get(definition.datomic_attribute), db)
    end

    def interpret_value(value)
      case value
      when Enumerable
        value.lazy.map { |e| interpret_value(e) }
      when Java::DatomicQuery::EntityMap
        self.class.interpret_entity(value)
      when Numeric, String, Symbol, true, false, nil
        value
      else
        raise TypeError.new("unknown value type: #{value.inspect}")
      end
    end

    def attributes
      out = {}

      self.class.attributes.each do |attr, _|
        out[attr] = send(attr)
      end

      out
    end

    def to_h
      attributes.merge(:id => id)
    end

    # TODO: fix this implementation
    def updated_at
      txid = db.q('[:find (max ?t) :in $ ?e :where [?e _ _ ?t]]', self.id).first.first
      db.entity(txid).get(:'db/txInstant').to_time
    end

    def changer
      self.class::Changer.new(id, self)
    end

    def change(&b)
      changer.change(&b)
    end

    def change!(&b)
      changer.change!(&b)
    end

    def retract!
      self.class.transact([[:'db.fn/retractEntity', self.id]])
    end

    def ==(other)
      self.entity == other.entity
    end
  end
end
