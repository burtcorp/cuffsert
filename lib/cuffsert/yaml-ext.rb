require 'yaml'

module YAML
  %w[Ref].each do |name|
    add_domain_type('cuffsert', name) do |tag, value|
      {name => value}
    end
  end

  add_domain_type('cuffsert', 'GetAtt') do |_, value|
    if value.is_a? String
      {'Fn::GetAtt' => value.split('.')}
    else
      {'Fn::GetAtt' => value}
    end
  end

  %w[
    Base64 Cidr FindInMap GetAZs ImportValue Join Select Split Sub Transform
    And Equals If Not Or
  ].each do |name|
    add_domain_type('cuffsert', name) do |tag, value|
      {['Fn', name].join('::') => value}
    end
  end
end
