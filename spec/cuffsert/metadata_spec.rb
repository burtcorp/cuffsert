require 'cuffsert/metadata'
require 'tempfile'

 def cuffsert_yaml
  data = <<EOF
Format: v1
Tags:
  - Name: tlevel
    Value: top
Parameters:
  - Name: plevel
    Value: top
Variants:
  level1_a:
    Tags:
      - Name: tlevel
        Value: level1_a
  level1_b:
    DefaultPath: level2_a
    Variants:
      level2_a:
        Parameters:
          - Name: plevel
            Value: level2_a
      level2_b:
        Parameters:
          - Name: plevel
            Value: level2_b
EOF
end

describe CuffSert::StackConfig do
  context 'update_from merges' do
    subject do
      config = described_class.new
      config.stackname = 'stackname'
      config.tags = {'T1' => 'V1', 'T2' => 'V2'}
      config.update_from({
        :stackname => 'updated',
        :parameters => {'P1' => 'new'},
        :tags => {'T1' => 'updated', 'T3' => 'new'},
      })
      config
    end

    it { expect(subject.stackname).to eq('updated') }
    it { expect(subject.parameters).to eq({'P1' => 'new'}) }
    it { expect(subject.tags).to eq(
      {'T1' => 'updated',  'T2' => 'V2', 'T3' => 'new'}
    )}
  end
end

describe CuffSert do
  context '#load_config' do
    subject do
      io = StringIO.new(cuffsert_yaml)
      CuffSert.load_config(io)
    end

    it 'converts config keys to symbols' do
      result = subject[:variants][:level1_b][:defaultpath]
      expect(result).to eq('level2_a')
    end
  end

  context '#load_config fails on' do
    it 'no data' do
      io = StringIO.new('')
      expect { CuffSert.load_config(io) }.to raise_error(/hash/)
    end

    it 'unknown version' do
      io = StringIO.new('Format: foo')
      expect { CuffSert.load_config(io) }.to raise_error(/Format: v1/)
    end
  end

  context '#meta_for_path' do
    let :config do
      CuffSert.load_config(StringIO.new(cuffsert_yaml))
    end

    it 'finds default on ""' do
      result = CuffSert.meta_for_path(config, [])
      expect(result.tags).to eq({'tlevel' => 'top'})
      expect(result.parameters).to eq({'plevel' => 'top'})
      expect(result.stackname).to eq('')
    end

    it 'finds "level1_a"' do
      result = CuffSert.meta_for_path(config, ['level1_a'])
      expect(result.tags).to eq({'tlevel' => 'level1_a'})
      expect(result.parameters).to eq({'plevel' => 'top'})
      expect(result.stackname).to eq('level1_a')
    end

    it 'defaults to "level1_b/level2_a"' do
      result = CuffSert.meta_for_path(config, ['level1_b'])
      expect(result.tags).to eq({'tlevel' => 'top'})
      expect(result.parameters).to eq({'plevel' => 'level2_a'})
      expect(result.stackname).to eq('level1_b-level2_a')
    end

    it 'explicit reference to "level1_b/level2_b"' do
      result = CuffSert.meta_for_path(config, ['level1_b', 'level2_b'])
      expect(result.tags).to eq({'tlevel' => 'top'})
      expect(result.parameters).to eq({'plevel' => 'level2_b'})
      expect(result.stackname).to eq('level1_b-level2_b')
    end

     it 'explicit reference to "level1_b-level2_b"' do
      result = CuffSert.meta_for_path(config, ['level1_b', 'level2_b'])
      expect(result.parameters).to eq({'plevel' => 'level2_b'})
      expect(result.stackname).to eq('level1_b-level2_b')
    end
  end
end
