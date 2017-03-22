require 'support/matchers'

describe '#have_hash_path' do
  subject do
    {
      'top' => {'child' => 'leaf'},
      'sibling' => 'other'
    }
  end
 
  it 'finds top' do
    should have_hash_path('top')
  end
  
  it 'finds child' do
    should have_hash_path('top/child')
  end
  
  it 'does not find nonsense' do
    should_not have_hash_path('nonsense')
  end
  
  it 'checks equality' do
    should have_hash_path('top/child' => 'leaf')
    should_not have_hash_path('top/child' => 'nope')
  end
  
  it 'applies matcher if any' do
    should have_hash_path('top' => include('child'))
  end
  
  it 'works recursively' do
    should have_hash_path('top' => have_hash_path('child' => 'leaf'))
  end
end
