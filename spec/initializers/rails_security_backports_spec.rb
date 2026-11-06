require 'rails_helper'

# config/initializers/monkey_patches/rails_security_backports.rb and the Active Storage analyzers
# setting in config/application.rb, which stand in for the Rails 8.0.5.2 security fixes on 7.2
describe 'Rails security backports' do # rubocop:disable RSpec/DescribeClass
  describe 'safe_constantize (GHSA-8474-xrp6-wh69)' do
    it 'does not compile the requested name as a regexp when autoloading fails' do
      allow(ActiveSupport::Inflector).to receive(:constantize).and_raise(LoadError, 'Unable to autoload constant Foo([, expected it')

      expect(ActiveSupport::Inflector.safe_constantize('Foo([')).to be_nil
    end

    it 'still re-raises a LoadError about a different constant' do
      allow(ActiveSupport::Inflector).to receive(:constantize).and_raise(LoadError, 'cannot load such file -- other')

      expect { ActiveSupport::Inflector.safe_constantize('Foo') }.to raise_error(LoadError)
    end

    it 'keeps resolving normal constants' do
      expect('Campaign'.safe_constantize).to eq(Campaign)
      expect('NoSuchConstantHere'.safe_constantize).to be_nil
    end
  end

  describe 'ActionController::Parameters#each_key (GHSA-wm3x-v3qw-4jh3)' do
    it 'returns the Parameters instance, which mass assignment rejects unless permitted' do
      params = ActionController::Parameters.new(name: 'Bob', admin: true)
      result = params.each_key { |_key| nil }

      expect(result).to be(params)
      expect(result.permitted?).to be false
      expect(params.each_key.to_a).to eq(%w[name admin])
    end
  end

  it 'only runs the libvips image analyzer on attachments' do
    expect(ActiveStorage.analyzers).to eq([ActiveStorage::Analyzer::ImageAnalyzer::Vips])
  end
end
