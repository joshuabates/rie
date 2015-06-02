describe Rie::Model do
  Rie::Model.configure do |m|
    m.namespace = :dalton
    m.partition = :spec
    m.uri = 'datomic:mem://spec'
  end

  Object.send(:remove_const, :Sample) if defined?(Sample)
  class Sample
    include Rie::Model

    schema do
      attribute :foo, :value_type => :string
      attribute :'bar-custom-key', :value_type => :string, :doc => "the #bar attribute"
      attribute :name, :value_type => :string, :unique => :value
      attribute :parent, :value_type => :ref
      attribute :overrideable, :value_type => :string
    end

    attribute :foo
    attribute :name
    attribute :bar, 'dalton.sample/bar-custom-key'
    attribute :overrideable
    attribute :parent, :type => [:ref, Sample]
    attribute :children, 'dalton.sample/_parent', :type => [:set, [:ref, Sample]]

    changers do
      def overrideable=(v)
        super
        self.foo = "overridden with #{v}"
      end
    end

    finders do
      def by_foo_and_bar(foo_and_bar)
        foo, bar = foo_and_bar.split('/')
        where(:foo => foo, :bar => bar)
      end
    end

    validation do
      validate :foo do |foo|
        if foo =~ /invalid/
          invalid! "must not contain the string 'invalid'"
        end
      end
    end
  end

  before do
    Rie::Model.install_bases!
    Rie::Model.install_schemas!
  end

  after do
    Sample.connection.destroy
  end

  describe 'basic model' do
    let(:model) do
      Sample.create! do |m|
        m.bar = 'bar-value'
      end
    end

    describe '.create!' do
      it 'creates a model' do
        assert { model.is_a? Sample }
        assert { model.foo == nil }
        assert { model.bar == 'bar-value' }
      end
    end

    describe '#change' do
      it 'returns a new model with the changes' do
        next_model = model.change! do |m|
          m.foo = 'new-foo-value'
        end

        assert { next_model.is_a? Sample }
        assert { next_model.foo == 'new-foo-value' }
        assert { next_model.bar == 'bar-value' }
        assert { model.foo == nil }
      end

      it 'allows `super` in overridden methods' do
        next_model = model.change! do |m|
          m.overrideable = 'x'
        end

        assert { next_model.overrideable == 'x' }
        assert { next_model.foo == 'overridden with x' }
      end
    end

    describe '#retract!' do
      let(:txn) { model.retract! }

      it 'retracts the model' do
        error = rescuing { model.at(txn.db_after) }
        assert { Rie::NotFound === error }
      end
    end

    describe '#updated_at' do
      it 'returns a Time' do
        assert { model.updated_at.is_a? Time }
      end
    end

    describe 'validations' do
      describe 'on values' do
        let(:validation_error) do
          rescuing {
            model.change! do |m|
              m.foo = 'invalid-foo-value'
            end
          }
        end

        it 'raises a validation error' do
          assert { validation_error.is_a? Rie::ValidationError }
          assert { validation_error.errors.length == 1 }
          assert { validation_error.errors_on(:foo) == ["must not contain the string 'invalid'"] }
          assert { validation_error.changes.change_in(:foo) == [nil, 'invalid-foo-value'] }
        end
      end

      describe 'on transactions' do
        before do
          model.change! { |m| m.name = 'unique-name' }
        end

        let(:validation_error) do
          rescuing do
            Sample.create! { |m| m.name = 'unique-name' }
          end
        end

        it 'raises a validation error' do
          assert { validation_error.is_a? Rie::ValidationError }
        end
      end
    end

    describe 'finders' do
      let(:finder) do
        model.finder
      end

      describe '#entity' do
        it 'returns the same model' do
          refreshed = finder.entity(model.id)
          assert { refreshed == model }
        end
      end

      describe '#by_{attribute}' do
        it 'returns the same model' do
          by_bar = finder.by_bar('bar-value')
          assert { by_bar.first == model }
        end
      end

      describe '#where' do
        it 'returns the same model' do
          by_bar = finder.where(:bar => 'bar-value')
          assert { by_bar.first == model }
        end

        it 'works on refs' do
          next_model = model.change! { |m| m.parent = model }
          result = next_model.finder.where(:parent => model)
          assert { result.first == next_model }
        end
      end

      describe 'custom finders' do
        let(:finder) { model.change! { |m| m.foo = 'foo-value' }.finder }

        it 'runs custom finders' do
          result = finder.by_foo_and_bar('foo-value/bar-value')
          assert { result.first == model }
        end
      end
    end

    describe 'relations' do
      it 'starts out empty' do
        assert { model.parent == nil }
        assert { model.children.to_a == [] }
      end

      it 'sets a one-to-many relation' do
        next_model = model.change! do |m|
          m.parent = model
        end

        assert { next_model.parent == next_model }
        assert { next_model.children.to_a == [next_model] }
      end

      it 'sets a many-to-one relation' do
        next_model = model.change! do |m|
          m.children = [model]
        end

        assert { next_model.parent == next_model }
        assert { next_model.children.to_a == [next_model] }
      end

      it 'creates sub-entities' do
        next_model = model.change! do |m|
          m.parent = Sample.create { |p| p.foo = 'parent' }
          m.foo = 'child'
        end

        assert { next_model.parent.is_a? Sample }
        assert { next_model.parent.foo == 'parent' }
        assert { next_model.parent.id.is_a? Fixnum }
      end

      it 'creates sub-entities from reverse collections' do
        next_model = model.change! do |m|
          m.children = %w(a b c).map do |v|
            Sample.create { |c| c.foo = v }
          end
          m.foo = 'parent'
        end

        assert { next_model.children.count == 3 }
        assert { next_model.children.map(&:foo).to_a.sort == %w(a b c) }
      end

      it 'changes sub-entities' do
        first_model = model.change! do |m|
          m.foo = 'child'
          m.change_ref(:parent) { |p| p.foo = 'parent' }
        end

        assert { first_model.parent }
        assert { first_model.parent.foo == 'parent' }

        next_model = first_model.change! do |m|
          m.change_ref(:parent) { |p| p.foo = 'parent-changed' }
        end

        assert { next_model.parent.foo == 'parent-changed' }
      end
    end
  end
end
