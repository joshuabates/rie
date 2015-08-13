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
  attribute :bar, 'rie.sample/bar-custom-key'
  attribute :overrideable
  attribute :parent, :type => [:ref, Sample]
  attribute :children, 'rie.sample/_parent', :type => [:set, [:ref, Sample]]

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
