describe Rie::Query do
  uses_rie

  let(:one) { Sample.create! { |m| m.foo = 'one' } }
  let(:two) { Sample.create! { |m| m.foo = 'two'; m.parent = one } }

  let(:db) { one; two; Sample.connection.db }

  it 'queries' do
    results = db.find(:e).where(:e, Sample[:foo], 'one').to_a
    assert { results.size == 1 }

    result = results[0]
    assert { result.is_a? Sample }
    assert { result.foo == 'one' }
    assert { result.id == one.id }
    assert { result.db == db }
  end

  it 'binds variables' do
    results = db.find(:v)
      .where(:e, Sample[:foo], :v)
      .where(:e, Sample[:parent], :p)
      .where(:p, Sample[:foo], 'one')
      .to_a

    assert { results.size == 1 }
    assert { results[0] == 'one' }
  end

  it 'binds multiple results' do
    results = db.find(:e, :v)
      .where(:e, Sample[:foo], :v)
      .where(:e, Sample[:parent], :p)
      .where(:p, Sample[:foo], 'one')
      .to_a

    assert { results.size == 1 }
    assert { results[0].keys.sort == [:e, :v] }
    assert { results[0][:v] == 'one' }
    assert { results[0][:e].id == one.id }
  end

  it 'manages manual datoms' do
    results = db.find('?e')
      .where('?e rie.sample/foo "one"').to_a

    assert { results.size == 1 }
    assert { results[0].id == one.id }
  end

  it 'binds values' do
    results = db.find(:e).in(:foo)
      .where(:e, Sample[:foo], :foo)
      .with(:foo => 'one')
      .to_a

    assert { results.size == 1 }
    assert { results[0].id == one.id }
  end

  it 'casts values' do
    results = db.find(:e).in(:parent)
      .where(:e, Sample[:parent], :parent)
      .with(:parent => one)
      .to_a

    assert { results.size == 1 }
    assert { results[0].is_a?(Sample) }
    assert { results[0].id == two.id }
  end

  it 'handles type declaration in `find`' do
    results = db.find(:v => [:string])
      .where('?e :rie.sample/parent ?p')
      .where('?e :rie.sample/foo "two"')
      .where('?p :rie.sample/foo ?v')
      .to_a

    assert { results.size == 1 }
    assert { results[0] == 'one' }
  end

  it 'handles type declaration in `in`' do
    results = db.find(:v).in(:parent => [:ref, Sample])
      .where('?e :rie.sample/parent ?parent')
      .where('?e :rie.sample/foo ?v')
      .with(:parent => one)
      .to_a

    assert { results.size == 1 }
    assert { results[0] == 'two' }
  end

  it 'applies an `or-join`' do
    results = db.find(:e)
      .where(:e, Sample[:_type], Sample)
      .join(:or, :e) { |q| [ q.where(:e, Sample[:foo], 'one'), q.where(:e, Sample[:foo], 'two') ] }
      .to_a

    assert { results.size == 2 }
    assert { results.map(&:id).sort == [one.id, two.id].sort }
  end

  it 'applies a `not-join`' do
    results = db.find(:e)
      .where(:e, Sample[:_type], Sample)
      .join(:not, :e) { |q| q.where(:e, Sample[:foo], 'one') }
      .to_a

    assert { results.size == 1 }
    assert { results[0].id == two.id }
  end
end
