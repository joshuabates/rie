Rie::Model.configure do |m|
  m.namespace = :rie
  m.partition = :spec
  m.uri = 'datomic:mem://spec'
end

module Minitest::Spec::DSL
  def uses_rie
    before do
      Rie::Model.install_bases!
      Rie::Model.install_schemas!
    end

    after do
      Rie::Model.registry.values.map(&:uri).uniq.each do |uri|
        Dalton::Connection.connect(uri).destroy
      end
    end
  end
end
