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

describe 'CuffSert.validate_and_urlify' do
  let(:s3url) { 's3://ze-bucket/some/url' }
  let(:httpurl) { 'http://some.host/some/file' }

  it 'urlifies and normalizes files' do
    stack = Tempfile.new('stack')
    path = '/..' + stack.path
    result = CuffSert.validate_and_urlify(path)
    expect(result).to eq(URI.parse("file://#{stack.path}"))
  end

  it 'respects s3 urls' do
    expect(CuffSert.validate_and_urlify(s3url)).to eq(URI.parse(s3url))
  end

  it 'borks on non-existent local files' do
    expect {
      CuffSert.validate_and_urlify('/no/such/file')
    }.to raise_error(/local.*not exist/i)
  end

  it 'borks on unkown schemas' do
    expect {
      CuffSert.validate_and_urlify(httpurl)
    }.to raise_error(/.*http.*not supported/)
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

    context 'from "level1_b/level2_b/level3_b"', :path => ['level1_c', 'level2_a', 'level3_a'] do
      it { should have_attributes(:tags => {'tlevel' => 'top'}) }
      it { should have_attributes(:parameters => {'plevel' => 'level3_a'}) }
      it { should have_attributes(:stackname => 'level1_c-level2_a-level3_a') }
    end
  end

  describe '#build_meta' do
    include_context 'yaml configs'
    include_context 'templates'

    let :template_json do
      JSON.dump({'Parameters' => {'from_template' => {'Default' => 'ze-default'}}})
    end

    let :cli_args do
      {
        :overrides => overrides,
        :stack_path => [template_body.path],
      }
    end
    let(:overrides) { {} }

    subject { CuffSert.build_meta(cli_args) }
    
    it { should have_attributes(:stack_uri => URI.parse("file://#{template_body.path}")) }
    it { should have_attributes(:parameters => include('from_template' => nil)) }
    
    context 'given a parameter override' do
      let(:overrides) do 
        {:parameters => {:stackname => 'customname', 'from_template' => 'overridden'}}
      end

      it { should have_attributes(:parameters => include('from_template' => 'overridden')) }
    end

    context 'given a metadata file, selector and tag override' do
      let :cli_args do
        super().merge({:metadata => config_file.path, :selector => ['level1_a']})
      end

      it { should have_attributes(:tags => include('tlevel' => 'level1_a')) }

      it 'defaults suffix from file name because level1_a has no declared suffix' do
        should have_attributes(:stackname => "level1_a-#{File.basename(config_file.path, '.yml')}")
      end
      
      context 'with a tag override' do
        let(:overrides) { {:tags => {'another' => 'tag'}} }
        it { should have_attributes(:tags => include('tlevel' => 'level1_a')) }
        it { should have_attributes(:tags => include('another' => 'tag')) }
      end
      
      context 'with a stackname override' do
        let(:overrides) { {:stackname => 'customname'} }
        it { should have_attributes(:stackname => 'customname') }
      end
    end

    context 'safe by default' do
      it { should_not have_attributes(:op_mode => :dangerous_ok) }
    end

    context 'given cil arg' do
      let(:cli_args) { super().merge({:op_mode => :dangerous_ok}) }

      it { should have_attributes(:op_mode => :dangerous_ok) }
    end
  end
end
