require 'yaml'

module YAML
  %w[Ref].each do |name|
    add_domain_type('cuffsert', name) do |tag, value|
      {name => value}
    end
  end

  add_domain_type('cuffsert', 'GetAtt') do |_, value|
    {'Fn::GetAtt' => value.to_s.split('.')}
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
