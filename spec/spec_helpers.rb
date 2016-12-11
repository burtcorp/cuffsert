RSpec.configure do |rspec|
  rspec.shared_context_metadata_behavior = :apply_to_host_groups
end

shared_context 'basic parameters' do
  let(:stack_id) { 'ze-id' }
  let(:stack_name) { 'ze-stack' }
end

shared_context 'yaml configs' do
  let :config_yaml do
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

  let :config_file do
    config = Tempfile.new('metadata')
    config.write(config_yaml)
    config.close
    config
  end
end

shared_context 'metadata' do
  include_context 'basic parameters'

  let(:s3url) { 's3://foo/bar' }
  let :meta do
    meta = CuffSert::StackConfig.new
    meta.selected_path = [stack_name.split(/-/)]
    meta.tags = {'k1' => 'v1', 'k2' => 'v2'}
    meta.stack_uri = URI.parse(s3url)
    meta
  end
end

shared_context 'templates' do
  let(:template_json) { '{}' }
  let :template_body do
    body = Tempfile.new('template_body')
    body.write(template_json)
    body.rewind
    body
  end
end

shared_context 'stack states' do
  include_context 'basic parameters'

  let :stack_complete do
    {
      'StackId' => stack_id,
      'StackName' => stack_name,
      'StackStatus' => 'CREATE_COMPLETE',
    }
  end

  let :stack_in_progress do
    {
      'StackId' => stack_id,
      'StackName' => stack_name,
      'StackStatus' => 'CREATE_IN_PROGRESS',
    }
  end

  let :stack_rolled_back do
    {
      'StackId' => stack_id,
      'StackName' => stack_name,
      'StackStatus' => 'ROLLBACK_COMPLETE',
    }
  end

  let :stack_complete_describe do
    {'Stacks' => [stack_complete]}
  end

  let :stack_in_progress_describe do
    {'Stacks' => [stack_in_progress]}
  end

  let :stack_rolled_back_describe do
    {'Stacks' => [stack_rolled_back]}
  end
end

shared_context 'stack events' do
  let :r1_done do
    {
      'EventId' => 'r1_done',
      'StackId' => stack_id,
      'LogicalResourceId' => 'resource1_id',
      'ResourceStatus' => 'CREATE_COMPLETE',
      'Timestamp' => '2013-08-23T01:02:28.025Z',
    }
  end

  let :r2_progress do
    {
      'EventId' => 'r2_progress',
      'StackId' => stack_id,
      'LogicalResourceId' => 'resource2_id',
      'ResourceStatus' => 'CREATE_IN_PROGRESS',
      'Timestamp' => '2013-08-23T01:02:28.025Z',
    }
  end

  let :r2_done do
    {
      'EventId' => 'r2_done',
      'StackId' => stack_id,
      'LogicalResourceId' => 'resource2_id',
      'ResourceStatus' => 'CREATE_COMPLETE',
      'Timestamp' => '2013-08-23T01:02:38.534Z',
    }
  end

  let :r2_rolled_back do
    {
      'EventId' => 'r2_rolled_back',
      'StackId' => stack_id,
      'LogicalResourceId' => 'resource2_id',
      'ResourceStatus' => 'DELETE_COMPLETE',
      'Timestamp' => '2013-08-23T01:02:38.534Z',
    }
  end

  let :stack_in_progress_events do
    { 'StackEvents' => [r1_done, r2_progress] }
  end

  let :stack_complete_events do
    { 'StackEvents' => [r1_done, r2_done] }
  end

  let :stack_rolled_back_events do
    {'StackEvents' => [r1_done, r2_rolled_back] }
  end
end

def observe_expect(subject)
  result = []
  error = nil
  Thread.new do
    spinlock = 1
    subject.subscribe(
      lambda { |event| result << event },
      lambda { |err| error = err ; spinlock -= 1 },
      lambda { spinlock -= 1 }
    )

    for n in 1..10
      break if spinlock == 0
      sleep(0.05)
    end
    raise 'timeout' if spinlock == 1
  end.join
  raise error if error
  expect(result)
end
