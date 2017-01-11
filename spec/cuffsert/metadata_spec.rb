require 'cuffsert/metadata'
require 'spec_helpers'
require 'tempfile'

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

    it { should have_attributes(:stackname =>'updated') }
    it { should have_attributes(:parameters => {'P1' => 'new'}) }
    it { should have_attributes(:tags => {'T1' => 'updated',  'T2' => 'V2', 'T3' => 'new'}) }
  end

  it 'given explicit stackname, suffix is ignored' do
    config = described_class.new
    config.suffix = 'suffix'
    config.stackname = 'stackname'
    expect(config.stackname).to eq('stackname')
  end

  it 'absent explicit stackname, one is calculated' do
    config = described_class.new
    config.append_path('foo')
    config.append_path('bar')
    config.suffix = 'baz'
    expect(config.stackname).to eq('foo-bar-baz')
  end
end

describe CuffSert do
  include_context 'yaml configs'
  context '#load_config' do
    subject do
      io = StringIO.new(config_yaml)
      CuffSert.load_config(io)
    end

    it 'converts config keys to symbols' do
      result = subject[:variants][:level1_b][:defaultpath]
      expect(result).to eq('level2_a')
    end
  end

  context '#load_config fails on' do
    subject { |example| CuffSert.load_config(example.metadata[:io]) }

    it 'no data', :io => StringIO.new('') do
      expect { subject }.to raise_error(/hash/)
    end

    it 'unknown version', :io => StringIO.new('Format: foo') do
      expect { subject }.to raise_error(/Format: v1/)
    end
  end

  context '#meta_for_path returned meta' do
    let(:config) { CuffSert.load_config(StringIO.new(config_yaml)) }

    subject do |example|
      CuffSert.meta_for_path(config, example.metadata[:path])
    end

    it 'from empty path', :path => [] do
      expect { subject }.to raise_error(/no.defaultpath.*level1_a/i)
    end

    context 'from "level1_a"', :path => ['level1_a'] do
      it { should have_attributes(:tags => {'tlevel' => 'level1_a'}) }
      it { should have_attributes(:parameters => {'plevel' => 'top'}) }
      it { should have_attributes(:stackname => 'level1_a') }
    end

    context 'defaults to "level1_b/level2_a"', :path => ['level1_b'] do
      it { should have_attributes(:tags => {'tlevel' => 'top'}) }
      it { should have_attributes(:parameters => {'plevel' => 'level2_a'}) }
      it { should have_attributes(:stackname => 'level1_b-level2_a-stack') }
    end

    context 'from "level1_b/level2_b"', :path => ['level1_b', 'level2_b'] do
      it { should have_attributes(:tags => {'tlevel' => 'top'}) }
      it { should have_attributes(:parameters => {'plevel' => 'level2_b'}) }
      it { should have_attributes(:stackname => 'level1_b-level2_b-stack') }
    end
  end

  describe '#build_meta' do
    include_context 'yaml configs'

    let :cli_args do
      {
        :metadata => config_file.path,
        :selector => ['level1_a'],
        :overrides => overrides
      }
    end
    let(:overrides) { {} }

    subject { CuffSert.build_meta(cli_args) }

    context 'reads metadata file and allows overrides' do
      let(:overrides) { {:stackname => 'customname', :tags => {'another' => 'tag'}} }
      it { should have_attributes(:stackname => 'customname') }
      it { should have_attributes(:tags => include('tlevel' => 'level1_a')) }
      it { should have_attributes(:tags => include('another' => 'tag')) }
    end

    context 'defaults suffix from config file name because level1_a has no declared suffix' do
      it { should have_attributes(:stackname => "level1_a-#{File.basename(config_file.path, '.yml')}") }
    end

    context 'safe by default' do
      it { should have_attributes(:dangerous_ok => false) }
    end

    context 'given cil arg' do
      let(:cli_args) { super().merge({:dangerous_ok => true }) }

      it { should have_attributes(:dangerous_ok => true) }
    end
  end
end
