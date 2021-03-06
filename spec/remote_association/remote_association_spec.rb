require 'spec_helper'

describe RemoteAssociation do
  before(:all) do
    @profiles_json = [
      {profile: {id: 1, user_id: 1, like: "letter A"}},
      {profile: {id: 2, user_id: 2, like: "letter B"}}
    ]
  end

  before(:each) do
    unset_const(:Profile)
    unset_const(:User)
    class Profile < ActiveResource::Base
      self.site = REMOTE_HOST
    end
    class User < ActiveRecord::Base
      include RemoteAssociation::Base
      has_one_remote :profile
    end

    add_user(1,"User A")
    add_user(2,"User B")
  end

  it 'should raise error if can\'t find settings for included remote' do
    lambda{ User.scoped.includes_remote(:whatever) }.should raise_error(RemoteAssociation::SettingsNotFoundError, "Can't find settings for whatever association")
  end

  it 'should prefetch remote associations of models, passed as args of includes_remote' do
    unset_const(:OtherProfile)
    unset_const(:User)
    class OtherProfile < ActiveResource::Base
      self.site = REMOTE_HOST
      self.element_name = "profile"
    end
    class User < ActiveRecord::Base
      include RemoteAssociation::Base
      has_one_remote :profile
      has_one_remote :other_profile
    end

    FakeWeb.register_uri(:get, "#{REMOTE_HOST}/other_profiles.json?user_id%5B%5D=1&user_id%5B%5D=2", body: @profiles_json.to_json)
    FakeWeb.register_uri(:get, "#{REMOTE_HOST}/profiles.json?user_id%5B%5D=1&user_id%5B%5D=2", body: @profiles_json.to_json)

    users = User.scoped.includes_remote(:profile, :other_profile).all
    users.first.profile.like.should eq('letter A')
    users.last.profile.like.should eq('letter B')
    users.first.other_profile.like.should eq('letter A')
    users.last.other_profile.like.should eq('letter B')
  end

  it "should fetch remote objects right after ActiveRecord fetched array of data" do
    FakeWeb.register_uri(:get, "#{REMOTE_HOST}/profiles.json?user_id%5B%5D=2",
       body: [{profile: {id: 2, user_id: 2, like: "letter B"}}].to_json)

    t = User.arel_table
    users = User.where(t[:name].matches('%User%')).includes_remote(:profile).
                         where(t[:name].matches('%B%')).all
    users.map(&:profile).flatten.map(&:like).should eq(['letter B'])
  end

  it "can set additional conditions for API call" do
    unset_const(:OtherProfile)
    unset_const(:User)
    class OtherProfile < ActiveResource::Base
      self.site = REMOTE_HOST
    end
    class User < ActiveRecord::Base
      include RemoteAssociation::Base
      has_one_remote :profile
      has_one_remote :other_profile
    end

    FakeWeb.register_uri(:get, "#{REMOTE_HOST}/profiles.json?user_id%5B%5D=2&search%5Bcountry_equals%5D=Ukraine&search%5Bage_less%5D=30",
       body: [{profile: {id: 2, user_id: 2, like: "letter B"}}].to_json)
    FakeWeb.register_uri(:get, "#{REMOTE_HOST}/other_profiles.json?capitals=false&user_id%5B%5D=2",
       body: [{other_profile: {id: 2, user_id: 2, like: "letter b"}}].to_json)

    users = User.scoped.includes_remote(:profile, :other_profile).
                  where_remote(profile: {search: {country_equals: 'Ukraine'}}, other_profile: {capitals: false} ).
                  where(id: 2).
                  where_remote(profile: {search: {age_less: 30}}).all
    users.first.profile.like.should eq('letter B')
    users.first.other_profile.like.should eq('letter b')

  end

end
