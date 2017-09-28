require 'cuff/metadata'
require 'cuffit/main'
require 'spec_helpers'

# Use cases:
# - existing stack, new to cuffsert; create metadata
#   bin/cuffit -s '' --name ... -m ./foo.yml
# - stack changed, update metadata
#   bin/cuffit -s '' [--name ...] -m ./foo.yml
# - have new template, need metadata
#   bin/cuffsert -s '' ./template.json

describe 'Cuff.new_meta' do
end

describe 'CuttIt.extract_from_stack' do
  include_context 'stack states'

  subject { CuffIt.extract_from_stack(stack) }

  context 'given completed stack' do
    let(:stack) do
      stack_complete_describe.merge(
        :parameters => [
          {:parameter_key => 'p1', :parameter_value => 'v1'}
        ],
        :tags => [
          {:key => 't1', :value => 'v1'}
        ]
      )
    end

    it 'extracts parameters from desc' do
      should include(:parameters => {'p1' => 'v1'})
    end

    it 'extracts tags from desc' do
      should include(:tags => {'t1' => 'v1'})
    end
  end
end

describe 'CuffIt.extract_from_template' do
  include_context 'templates'

  let :template_json do
    YAML.dump({
      'Parameters' => {
        'p1' => { 'Default' => 'v1' }
      }
    })
  end

  subject { CuffIt.extract_from_template(template_body) }

  it { should include('p1' => 'v1') }
end

describe 'CuffIt.apply_meta' do
  include_context 'metadata'

  let :stack_variant do
    {
      'stack' => {
        'StackName' => 'custom',
        'Parameters' => [
          {'Name' => 'p3', 'Value' => 'v3'}
        ],
        'Tags' => [
          {'Name' => 't1', 'Value' => 'v1'},
          {'Name' => 't3', 'Value' => 'v3'}
        ]
      }
    }
  end

  let :ze_variant do
    {
      'ze' => {
        'Variants' => stack_variant
      }
    }
  end

  subject { CuffIt.apply_meta(config, meta) }

  context 'given non-existent config, creates it' do
    let :meta do
      Cuff::StackConfig.new.tap do |meta|
        meta.selected_path = [stack_name.split(/-/)]
        meta.stackname = 'custom'
        meta.parameters = {'p1' => 'v1'}
        meta.tags = {'t1' => 'v1', 't2' => 'v2'}
        meta.stack_uri = URI.parse(s3url)
      end
    end

    let :config do
      nil
    end

    it { should include('Format' => 'v1') }
    it { should include('Variants' => ze_variant) }
    it { should_not include('Tags', 'Parameters') }
  end

  context 'given existing config file' do
    include_context 'yaml configs'

    let :config do
      { 'Variants' => ze_variant }
    end

    context 'and stack path is new' do
      let :meta do
        super().tap do |meta|
          meta.selected_path = ['ze', 'new']
        end
      end

      it { should have_hash_path('Variants/ze/Variants' => include('new')) }
      it { should have_hash_path('Variants/ze/Variants/new/Parameters' => include('Name' => 'p1')) }
      it { should have_hash_path('Variants/ze/Variants/stack/Parameters' => include('Name' => 'p3')) }
    end

    context 'and stack path exists' do
      it { should have_hash_path('Variants/ze/Variants/stack/Parameters' => include('Name' => 'p1')) }
      it { should_not have_hash_path('Variants/ze/Variants/stack/Parameters' => include('Name' => 'p3')) }
    end

    context 'and stack path exists, with more general parameter exists' do
      let :ze_variant do
        super().tap do |ze_variant|
          ze_variant['Parameters'] = {'Name' => 'p1', 'Value' => 'v1'}
        end
      end

      it { should_not have_hash_path('Variants/ze/Variants/stack/Parameters' => include('Name' => 'p1')) }
      it { should have_hash_path('Variants/ze/Parameters' => include('Name' => 'p1')) }
    end

    context 'and stack path has a default with irrelevant parameter' do
      let :meta do
        super().tap do |meta|
          meta.selected_path = ['ze']
        end
      end

      let :ze_variant do
        super().tap do |ze_variant|
          ze_variant['DefaultPath'] = 'stack'
        end
      end

      it { should have_hash_path('Variants/ze/Parameters' => include('Name' => 'p1')) }
      it { should_not have_hash_path('Variants/ze/Variants/stack/Parameters' => include('Name' => 'p3')) }
    end

    context 'and stack path has a default with relevant tag' do
      let :meta do
        super().tap do |meta|
          meta.selected_path = ['ze']
        end
      end

      let :ze_variant do
        super().tap do |ze_variant|
          ze_variant['DefaultPath'] = 'stack'
        end
      end

      it { should_not have_hash_path('Variants/ze/Tags' => include('Name' => 't1')) }
      it { should have_hash_path('Variants/ze/Variants/stack/Tags' => include('Name' => 't1')) }
    end
  end
end

describe 'CuffIt.run' do
  it 'does not explode' do
    CuffIt.main(['-s', 'foo-bar', '-m', metadata])
  end
end
