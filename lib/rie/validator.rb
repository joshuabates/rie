module Rie
  class ValidationError < StandardError
    attr_reader :changes, :errors

    def initialize(changes, errors)
      @changes = changes
      @errors = errors
    end

    def errors_on(key, &b)
      return enum_for(:errors_on, key).to_a unless block_given?

      errors.each do |(keys, message)|
        yield message if keys.include? key
      end
    end

    def errors_on?(key)
      errors_on(key).any?
    end
  end

  class TransactionValidationError < ValidationError
    def initialize(changes, datomic_error)
      @changes = changes
      @datomic_error = datomic_error
    end

    def errors
      # TODO: translate this key
      [@datomic_error.attribute, @datomic_error.message]
    end

    def errors_on?(key)
      changes.model.get_attribute(key).datomic_attribute == @datomic_error.attribute
    end
  end

  class Validator
    # a definition of a validator.  the block gets run in the context of
    # a Scope, and may call `invalid!` with optional attributes and an
    # error message
    class Rule
      class Scope
        def initialize(attrs, validate, &report)
          @validate = validate
          @attrs = attrs
          @report = report
        end

        def invalid!(attr_names=nil, description)
          attr_names ||= @attrs
          attr_names = Array(attr_names)

          @report.call [attr_names, description]
        end

        def run(values)
          instance_exec(*values, &@validate)
        end
      end

      def initialize(*attrs, &block)
        @attrs = attrs
        @block = block
      end

      def run(changer, &out)
        values = @attrs.map { |a| changer.send(a) }
        Scope.new(@attrs, @block, &out).run(values)
      end
    end

    attr_reader :validators
    def initialize(model, &defn)
      @model = model
      @validators = []
      specify(&defn) if defn
    end

    def specify(&defn)
      instance_eval(&defn)
    end

    # define a validation on *attrs using &block.
    # See Rule
    def validate(*attrs, &block)
      validators << Rule.new(*attrs, &block)
    end

    # returns an enumerable of validation errors on the changeset,
    # which is empty if the changeset is valid
    def run_all(changer, &report)
      return enum_for(:run_all, changer).to_a unless block_given?

      validators.each { |v| v.run(changer, &report) }
    end

    # raises a ValidationError if the changeset is invalid
    def run_all!(changer)
      errors = run_all(changer)
      raise ValidationError.new(changer, errors) if errors.any?
    end
  end
end
