require 'cuffsert/messages'
require 'rx-rspec'

describe CuffSert::Abort do
  subject { described_class.new('badness') }

  describe '#===' do
    it { should ===(described_class.new('badness')) }
    it('matches regex left') do
      expect(subject === described_class.new(/ness/)).to be_truthy
    end
    it('matches regex right') do
      expect(described_class.new(/ness/) === subject).to be_truthy
    end
  end

  describe '#as_observable' do
    subject { described_class.new('badness').as_observable }
    it { should emit_exactly(CuffSert::Abort.new('badness')) }
  end
end

describe CuffSert::Report do
  subject { described_class.new('goodness') }

  describe '#===' do
    it { should ===(described_class.new('goodness')) }
    it { should_not ===(CuffSert::Abort.new('goodness')) }
    it('matches regex left') do
      expect(subject === described_class.new(/ness/)).to be_truthy
    end
    it('matches regex right') do
      expect(described_class.new(/ness/) === subject).to be_truthy
    end
  end

  describe '#as_observable' do
    subject { described_class.new('badness').as_observable }
    it { should emit_exactly(described_class.new('badness')) }
  end
end
