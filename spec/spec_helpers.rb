require 'aws-sdk-cloudformation'
require 'simplecov'

SimpleCov.start

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
   Suffix: stack
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
 level1_c:
   Variants:
     level2_a:
       Variants:
         level3_a:
           Parameters:
             - Name: plevel
               Value: level3_a

EOF
  end

  let :config_file do
    config = Tempfile.new(['metadata', '.yml'])
    config.write(config_yaml)
    config.close
    config
  end
end

shared_context 'metadata' do
  include_context 'basic parameters'

  let(:s3url) { 's3://foo/bar' }
  let(:amazonaws_url) { 'https://s3.amazonaws.com/foo/bar' }
  let :meta do
    meta = CuffSert::StackConfig.new
    meta.selected_path = [stack_name.split(/-/)]
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

shared_context 'changesets' do
  include_context 'basic parameters'

  let(:change_set_id) { 'ze-change-set-id' }

  let :stack_update_change_set do
    { :id => change_set_id, :stack_id => 'ze-stack' }
  end

  let :change_set_summary do
    Aws::CloudFormation::Types::ChangeSetSummary.new({
      :change_set_id => change_set_id,
      :change_set_name => 'ze-change-set-name',
    })
  end

  let :no_change_set do
    Aws::CloudFormation::Types::ListChangeSetsOutput.new({
      :summaries => []
    })
  end
  
  let :change_set_list do
    Aws::CloudFormation::Types::ListChangeSetsOutput.new({
      :summaries => [change_set_summary]
    })
  end

  let :change_set_in_progress do
    Aws::CloudFormation::Types::DescribeChangeSetOutput.new({
      :change_set_id => change_set_id,
      :stack_id => stack_id,
      :stack_name => stack_name,
      :status => 'CREATE_IN_PROGRESS',
      :changes => change_set_changes.map { |c| {:resource_change => c} },
    })
  end

  let :change_set_ready do
    Aws::CloudFormation::Types::DescribeChangeSetOutput.new({
      :change_set_id => change_set_id,
      :stack_id => stack_id,
      :stack_name => stack_name,
      :status => 'CREATE_COMPLETE',
      :changes => change_set_changes.map { |c| {:resource_change => c} },
    })
  end

  let :change_set_failed do
    Aws::CloudFormation::Types::DescribeChangeSetOutput.new({
      :change_set_id => change_set_id,
      :stack_id => stack_id,
      :stack_name => stack_name,
      :status => 'FAILED',
      :status_reason => 'The submitted information didn\'t contain changes. Submit different information to create a change set.',
      :changes => change_set_changes.map { |c| {:resource_change => c} },
    })
  end

  let :change_set_changes do
    []
  end

  let :r1_modify do
    Aws::CloudFormation::Types::ResourceChange.new({
      :action => 'Modify',
      :replacement => 'Never',
      :logical_resource_id => 'resource1_id',
      :resource_type => 'AWS::EC2::VPC',
      :scope => ['Properties'],
      :details => [
        {
          :target => {
            :attribute => 'Properties',
            :name => 'Foo',
          },
        }
      ],
    })
  end

  let :r1_replace do
    Aws::CloudFormation::Types::ResourceChange.new({
      :action => 'Modify',
      :replacement => 'True',
      :logical_resource_id => 'resource1_id',
      :resource_type => 'AWS::EC2::VPC',
    })
  end

  let :r1_conditional_replace do
    Aws::CloudFormation::Types::ResourceChange.new({
      :action => 'Modify',
      :replacement => 'Conditional',
      :logical_resource_id => 'resource1_id',
      :resource_type => 'AWS::EC2::VPC',
    })
  end

  let :r2_add do
    Aws::CloudFormation::Types::ResourceChange.new({
      :action => 'Add',
      :replacement => 'False',
      :logical_resource_id => 'resource2_id',
      :resource_type => 'AWS::EC2::VPC',
    })
  end

  let :r3_delete do
    Aws::CloudFormation::Types::ResourceChange.new({
      :action => 'Remove',
      :replacement => 'False',
      :logical_resource_id => 'resource3_id',
      :resource_type => 'AWS::EC2::VPC',
    })
  end
end

shared_context 'stack states' do
  include_context 'basic parameters'

  let :stack_complete do
    {
      :stack_id => stack_id,
      :stack_name => stack_name,
      :stack_status => 'CREATE_COMPLETE',
    }
  end

  let :stack_in_progress do
    {
      :stack_id => stack_id,
      :stack_name => stack_name,
      :stack_status => 'CREATE_IN_PROGRESS',
    }
  end

  let :stack_rolled_back do
    Aws::CloudFormation::Types::Stack.new({
      :stack_id => stack_id,
      :stack_name => stack_name,
      :stack_status => 'ROLLBACK_COMPLETE',
    })
  end

  let :stack_deleting do
    {
      :stack_id => stack_id,
      :stack_name => stack_name,
      :stack_status => 'DELETE_IN_PROGRESS',
    }
  end

  let :stack_deleted do
    {
      :stack_id => stack_id,
      :stack_name => stack_name,
      :stack_status => 'DELETE_COMPLETE',
    }
  end

  let :stack_complete_describe do
    {:stacks => [stack_complete]}
  end

  let :stack_in_progress_describe do
    {:stacks => [stack_in_progress]}
  end

  let :stack_rolled_back_describe do
    {:stacks => [stack_rolled_back]}
  end

  let :stack_deleting_describe do
    {:stacks => [stack_deleting]}
  end

  let :stack_deleted_describe do
    {:stacks => [stack_deleted]}
  end
end

shared_context 'stack events' do
  include_context 'basic parameters'

  let :r1_old do
    Aws::CloudFormation::Types::StackEvent.new({
      :event_id => 'r1_old',
      :stack_id => stack_id,
      :logical_resource_id => 'resource1_name',
      :physical_resource_id => 'resource1_id',
      :resource_type => 'AWS::EC2::VPC',
      :resource_status => 'CREATE_COMPLETE',
      :timestamp => DateTime.rfc3339('2011-08-23T01:02:28.025Z').to_time,
    })
  end

  let :r1_done do
    Aws::CloudFormation::Types::StackEvent.new({
      :event_id => 'r1_done',
      :stack_id => stack_id,
      :logical_resource_id => 'resource1_name',
      :physical_resource_id => 'resource1_id',
      :resource_type => 'AWS::EC2::VPC',
      :resource_status => 'CREATE_COMPLETE',
      :timestamp => DateTime.rfc3339('2013-08-23T01:02:28.025Z').to_time,
    })
  end

  let :r1_deleted do
    Aws::CloudFormation::Types::StackEvent.new({
      :event_id => 'r1_deleted',
      :stack_id => stack_id,
      :logical_resource_id => 'resource1_id',
      :resource_status => 'DELETE_COMPLETE',
      :timestamp => DateTime.rfc3339('2013-08-23T01:02:28.025Z').to_time,
    })
  end

  let :r2_progress do
    Aws::CloudFormation::Types::StackEvent.new({
      :event_id => 'r2_progress',
      :stack_id => stack_id,
      :logical_resource_id => 'resource2_name',
      :physical_resource_id => 'resource2_id',
      :resource_type => 'AWS::EC2::Instance',
      :resource_status => 'CREATE_IN_PROGRESS',
      :timestamp => DateTime.rfc3339('2013-08-23T01:02:28.025Z').to_time,
    })
  end

  let :r2_done do
    Aws::CloudFormation::Types::StackEvent.new({
      :event_id => 'r2_done',
      :stack_id => stack_id,
      :logical_resource_id => 'resource2_name',
      :physical_resource_id => 'resource2_id',
      :resource_type => 'AWS::EC2::Instance',
      :resource_status => 'CREATE_COMPLETE',
      :timestamp => DateTime.rfc3339('2013-08-23T01:02:38.534Z').to_time,
    })
  end

  let :r2_failed do
    Aws::CloudFormation::Types::StackEvent.new({
      :event_id => 'r2_failed',
      :stack_id => stack_id,
      :logical_resource_id => 'resource2_name',
      :physical_resource_id => 'resource2_id',
      :resource_type => 'AWS::EC2::Instance',
      :resource_status => 'CREATE_FAILED',
      :resource_status_reason => 'Insufficient permissions',
      :timestamp => DateTime.rfc3339('2013-08-23T01:02:28.025Z').to_time,
    })
  end

  let :r2_rolling_back do
    Aws::CloudFormation::Types::StackEvent.new({
      :event_id => 'r2_rolling_back',
      :stack_id => stack_id,
      :logical_resource_id => 'resource2_name',
      :physical_resource_id => 'resource2_id',
      :resource_type => 'AWS::EC2::Instance',
      :resource_status => 'DELETE_IN_PROGRESS',
      :timestamp => DateTime.rfc3339('2013-08-23T01:02:28.025Z').to_time,
    })
  end

  let :r2_deleting do
    Aws::CloudFormation::Types::StackEvent.new({
      :event_id => 'r2_deleting',
      :stack_id => stack_id,
      :logical_resource_id => 'resource2_name',
      :physical_resource_id => 'resource2_id',
      :resource_status => 'DELETE_IN_PROGRESS',
      :timestamp => DateTime.rfc3339('2013-08-23T01:02:38.534Z').to_time,
    })
  end

  let :r2_deleted do
    Aws::CloudFormation::Types::StackEvent.new({
      :event_id => 'r2_deleted',
      :stack_id => stack_id,
      :logical_resource_id => 'resource2_name',
      :physical_resource_id => 'resource2_id',
      :resource_type => 'AWS::EC2::Instance',
      :resource_status => 'DELETE_COMPLETE',
      :timestamp => DateTime.rfc3339('2013-08-23T01:02:38.534Z').to_time,
    })
  end

  let :r2_updating do
    Aws::CloudFormation::Types::StackEvent.new({
      :event_id => 'r2_updating',
      :stack_id => stack_id,
      :logical_resource_id => 'resource2_name',
      :physical_resource_id => 'resource2_id',
      :resource_type => 'AWS::EC2::Instance',
      :resource_status => 'UPDATE_IN_PROGRESS',
      :timestamp => DateTime.rfc3339('2013-08-23T01:02:38.534Z').to_time,
    })
  end

  let :r2_updated do
    Aws::CloudFormation::Types::StackEvent.new({
      :event_id => 'r2_updated',
      :stack_id => stack_id,
      :logical_resource_id => 'resource2_name',
      :physical_resource_id => 'resource2_id',
      :resource_type => 'AWS::EC2::Instance',
      :resource_status => 'UPDATE_COMPLETE',
      :timestamp => DateTime.rfc3339('2013-08-23T01:02:38.534Z').to_time,
    })
  end

  let :s1_done do
    Aws::CloudFormation::Types::StackEvent.new({
      :event_id => 's1_done',
      :stack_id => stack_id,
      :logical_resource_id => stack_name,
      :physical_resource_id => stack_id,
      :resource_type => 'AWS::CloudFormation::Stack',
      :resource_status => 'CREATE_COMPLETE',
      :timestamp => DateTime.rfc3339('2013-08-23T01:02:38.534Z').to_time,
    })
  end

  let :s1_rolled do
    Aws::CloudFormation::Types::StackEvent.new({
      :event_id => 's1_rolled',
      :stack_id => stack_id,
      :logical_resource_id => stack_name,
      :physical_resource_id => stack_id,
      :resource_type => 'AWS::CloudFormation::Stack',
      :resource_status => 'ROLLBACK_COMPLETE',
      :timestamp => DateTime.rfc3339('2013-08-23T01:02:38.534Z').to_time,
    })
  end

  let :s1_deleted do
    Aws::CloudFormation::Types::StackEvent.new({
      :event_id => 's1_rolled',
      :stack_id => stack_id,
      :logical_resource_id => stack_name,
      :physical_resource_id => stack_id,
      :resource_type => 'AWS::CloudFormation::Stack',
      :resource_status => 'DELETE_COMPLETE',
      :timestamp => DateTime.rfc3339('2013-08-23T01:02:38.534Z').to_time,
    })
  end

  let :too_old_events do
    { :stack_events => [r1_old] }
  end

  let :stack_in_progress_events do
    { :stack_events => [r2_progress, r1_done] }
  end

  let :stack_complete_events do
    { :stack_events => [s1_done, r2_done, r1_done] }
  end

  let :stack_rolled_back_events do
    {:stack_events => [s1_rolled, r2_deleted, r1_done] }
  end

  let :stack_deleting_events do
    {:stack_events => [r2_deleting, r1_deleted] }
  end

  let :stack_deleted_events do
    {:stack_events => [s1_deleted, r2_deleted, r1_deleted] }
  end
end
