require 'test_helper'

class Api::V1::RubygemsControllerTest < ActionController::TestCase
  should "route old paths to new controller" do
    get_route = {:controller => 'api/v1/rubygems', :action => 'show', :id => "rails", :format => "json"}
    assert_recognizes(get_route, '/api/v1/gems/rails.json')

    post_route = {:controller => 'api/v1/rubygems', :action => 'create'}
    assert_recognizes(post_route, :path => '/api/v1/gems', :method => :post)
  end

  def self.should_respond_to_show(format, &block)
    should assign_to(:rubygem) { @rubygem }
    should respond_with :success
    should "return a hash" do
      response = yield(@response.body)
      assert_not_nil response
      assert_kind_of Hash, response
    end
  end

  def self.should_respond_to(format, &block)
    context "with #{format.to_s.upcase} for a hosted gem" do
      setup do
        @rubygem = Factory(:rubygem)
        Factory(:version, :rubygem => @rubygem)
        get :show, :id => @rubygem.to_param, :format => format
      end

      should_respond_to_show(format, &block)
    end

    context "with #{format.to_s.upcase} for a hosted gem with a period in its name" do
      setup do
        @rubygem = Factory(:rubygem, :name => 'foo.rb')
        Factory(:version, :rubygem => @rubygem)
        get :show, :id => @rubygem.to_param, :format => format
      end

      should_respond_to_show(format, &block)
    end

    context "with #{format.to_s.upcase} for a gem that doesn't match the slug" do
      setup do
        @rubygem = Factory(:rubygem, :name => "ZenTest", :slug => "zentest")
        Factory(:version, :rubygem => @rubygem)
        get :show, :id => "ZenTest", :format => format
      end

      should_respond_to_show(format, &block)
    end
  end

  context "When logged in" do
    setup do
      @user = Factory(:user)
      sign_in_as(@user)
    end

    context "On GET to show" do
      should_respond_to(:json) do |body|
        MultiJson.decode body
      end

      should_respond_to(:yaml) do |body|
       YAML.load body
      end

      should_respond_to(:xml) do |body|
        Hash.from_xml(Nokogiri.parse(body).to_xml)
      end
    end

    context "On GET to show for a gem that not hosted" do
      setup do
        @rubygem = Factory(:rubygem)
        assert @rubygem.versions.count.zero?
        get :show, :id => @rubygem.to_param, :format => "json"
      end

      should assign_to(:rubygem) { @rubygem }
      should respond_with :not_found
      should "say not be found" do
        assert_match /does not exist/, @response.body
      end
    end

    context "On GET to show for a gem that doesn't exist" do
      setup do
        @name = FactoryGirl.generate(:name)
        assert ! Rubygem.exists?(:name => @name)
        get :show, :id => @name, :format => "json"
      end

      should respond_with :not_found
      should "say the rubygem was not found" do
        assert_match /not be found/, @response.body
      end
    end
  end

  def self.should_respond_to(format)
    context "with #{format.to_s.upcase} for a list of gems" do
      setup do
        @mygems = [ Factory(:rubygem, :name => "SomeGem"), Factory(:rubygem, :name => "AnotherGem") ]
        @mygems.each do |rubygem|
          Factory(:version, :rubygem => rubygem)
          Factory(:ownership, :user => @user, :rubygem => rubygem)
        end

        @other_user = Factory(:user)
        @not_my_rubygem = Factory(:rubygem, :name => "NotMyGem")
        Factory(:version, :rubygem => @not_my_rubygem)
        Factory(:ownership, :user => @other_user, :rubygem => @not_my_rubygem)

        get :index, :format => format
      end

      should assign_to(:rubygems) { [@rubygem] }
      should respond_with :success
      should "return a hash" do
        assert_not_nil yield(@response.body)
      end
      should "only return my gems" do
        gem_names = yield(@response.body).map { |rubygem| rubygem['name'] }.sort
        assert_equal ["AnotherGem", "SomeGem"], gem_names
      end
    end
  end

  context "with a confirmed user authenticated" do
    setup do
      @user = Factory(:user)
      @request.env["HTTP_AUTHORIZATION"] = @user.api_key
    end

    context "On GET to index" do
      should_respond_to :json do |body|
        MultiJson.decode body
      end

      should_respond_to :yaml do |body|
        YAML.load body
      end

      should_respond_to :xml do |body|
        Hash.from_xml(Nokogiri.parse(body).to_xml)['rubygems']
      end
    end

    context "On POST to create for new gem" do
      setup do
        @request.env["RAW_POST_DATA"] = gem_file.read
        post :create
      end
      should respond_with :success
      should assign_to(:_current_user) { @user }
      should "register new gem" do
        assert_equal 1, Rubygem.count
        assert_equal @user, Rubygem.last.ownerships.first.user
        assert_equal "Successfully registered gem: test (0.0.0)", @response.body
      end
    end

    context "On POST to create for existing gem" do
      setup do
        rubygem = Factory(:rubygem, :name => "test")
        Factory(:ownership, :rubygem => rubygem, :user => @user)
        Factory(:version, :rubygem => rubygem, :number => "0.0.0", :updated_at => 1.year.ago, :created_at => 1.year.ago)
        @request.env["RAW_POST_DATA"] = gem_file("test-1.0.0.gem").read
        post :create
      end
      should respond_with :success
      should assign_to(:_current_user) { @user }
      should "register new version" do
        assert_equal @user, Rubygem.last.ownerships.first.user
        assert_equal 1, Rubygem.last.ownerships.count
        assert_equal 2, Rubygem.last.versions.count
        assert_equal "Successfully registered gem: test (1.0.0)", @response.body
      end
    end

    context "On POST to create for a repush" do
      setup do
        rubygem = Factory(:rubygem,
                          :name       => "test")
        Factory(:ownership, :rubygem => rubygem, :user => @user)

        @date = 1.year.ago
        @version = Factory(:version,
                           :rubygem    => rubygem,
                           :number     => "0.0.0",
                           :updated_at => @date,
                           :created_at => @date,
                           :summary    => "Freewill",
                           :authors    => ["Geddy Lee"],
                           :built_at   => @date)

        @request.env["RAW_POST_DATA"] = gem_file.read
        post :create
      end
      should respond_with :conflict
      should "not register new version" do
        version = Rubygem.last.reload.versions.most_recent
        assert_equal @date.to_s(:db), version.built_at.to_s(:db), "(date)"
        assert_equal "Freewill", version.summary, '(summary)'
        assert_equal "Geddy Lee", version.authors, '(authors)'
      end
    end

    context "On POST to create with bad gem" do
      setup do
        @request.env["RAW_POST_DATA"] = "really bad gem"
        post :create
      end
      should respond_with :unprocessable_entity
      should "not register gem" do
        assert Rubygem.count.zero?
        assert_match /RubyGems\.org cannot process this gem/, @response.body
      end
    end

    context "On POST to create for someone else's gem" do
      setup do
        @other_user = Factory(:user)
        create_gem(@other_user, :name => "test")
        @rubygem.reload

        @request.env["RAW_POST_DATA"] = gem_file("test-1.0.0.gem").read
        post :create
      end
      should respond_with 403
      should assign_to(:_current_user) { @user }
      should "not allow new version to be saved" do
        assert_equal 1, @rubygem.ownerships.size
        assert_equal @other_user, @rubygem.ownerships.first.user
        assert_equal 1, @rubygem.versions.size
        assert_equal "You do not have permission to push to this gem.", @response.body
      end
    end

    context "for a gem SomeGem with a version 0.1.0" do
      setup do
        @rubygem  = Factory(:rubygem, :name => "SomeGem")
        @v1       = Factory(:version, :rubygem => @rubygem, :number => "0.1.0", :platform => "ruby")
        Factory(:ownership, :user => @user, :rubygem => @rubygem)
      end

      context "ON DELETE to yank for existing gem version" do
        setup do
          delete :yank, :gem_name => @rubygem.to_param, :version => @v1.number
        end
        should respond_with :success
        should "keep the gem, deindex, remove owner" do
          assert_equal 1, @rubygem.versions.count
          assert @rubygem.versions.indexed.count.zero?
          assert @rubygem.ownerships.count.zero?
        end
      end

      context "and a version 0.1.1" do
        setup do
          @v2 = Factory(:version, :rubygem => @rubygem, :number => "0.1.1", :platform => "ruby")
        end

        context "ON DELETE to yank for version 0.1.1" do
          setup do
            delete :yank, :gem_name => @rubygem.to_param, :version => @v2.number
          end
          should respond_with :success
          should "keep the gem, deindex it, and keep the owners" do
            assert_equal 2, @rubygem.versions.count
            assert_equal 1, @rubygem.versions.indexed.count
            assert_equal 1, @rubygem.ownerships.count
          end
        end
      end

      context "and a version 0.1.1 and platform x86-darwin-10" do
        setup do
          @v2 = Factory(:version, :rubygem => @rubygem, :number => "0.1.1", :platform => "x86-darwin-10")
        end

        context "ON DELETE to yank for version 0.1.1 and x86-darwin-10" do
          setup do
            delete :yank, :gem_name => @rubygem.to_param, :version => @v2.number, :platform => @v2.platform
          end
          should respond_with :success
          should "keep the gem, deindex it, and keep the owners" do
            assert_equal 2, @rubygem.versions.count
            assert_equal 1, @rubygem.versions.indexed.count
            assert_equal 1, @rubygem.ownerships.count
          end
          should "show platform in response" do
            assert_equal "Successfully yanked gem: SomeGem (0.1.1-x86-darwin-10)", @response.body
          end
        end
      end

      context "ON DELETE to yank for existing gem with invalid version" do
        setup do
          delete :yank, :gem_name => @rubygem.to_param, :version => "0.2.0"
        end
        should respond_with :not_found
        should "not modify any versions" do
          assert_equal 1, @rubygem.versions.count
          assert_equal 1, @rubygem.versions.indexed.count
        end
      end

      context "ON DELETE to yank for someone else's gem" do
        setup do
          @other_user = Factory(:user)
          @request.env["HTTP_AUTHORIZATION"] = @other_user.api_key
          delete :yank, :gem_name => @rubygem.to_param, :version => '0.1.0'
        end
        should respond_with :forbidden
      end

      context "ON DELETE to yank for an already yanked gem" do
        setup do
          @v1.yank!
          delete :yank, :gem_name => @rubygem.to_param, :version => '0.1.0'
        end
        should respond_with :unprocessable_entity
      end
    end

    context "for a gem SomeGem with a yanked version 0.1.0 and unyanked version 0.1.1" do
      setup do
        @rubygem  = Factory(:rubygem, :name => "SomeGem")
        @v1       = Factory(:version, :rubygem => @rubygem, :number => "0.1.0", :platform => "ruby", :indexed => false)
        @v2       = Factory(:version, :rubygem => @rubygem, :number => "0.1.1", :platform => "ruby")
        @v3       = Factory(:version, :rubygem => @rubygem, :number => "0.1.2", :platform => "x86-darwin-10", :indexed => false)
        Factory(:ownership, :user => @user, :rubygem => @rubygem)
      end

      context "ON PUT to unyank for version 0.1.0" do
        setup do
          put :unyank, :gem_name => @rubygem.to_param, :version => @v1.number
        end
        should respond_with :success
        #should change("the rubygem's indexed version count", :by => 1) { @rubygem.versions.indexed.count }
        should "re-index 0.1.0" do
          assert @v1.reload.indexed?
        end
      end

      context "ON PUT to unyank for version 0.1.2 and platform x86-darwin-10" do
        setup do
          put :unyank, :gem_name => @rubygem.to_param, :version => @v3.number, :platform => @v3.platform
        end
        should respond_with :success
        #should change("the rubygem's indexed version count", :by => 1) { @rubygem.versions.indexed.count }
        should "re-index 0.1.2" do
          assert @v3.reload.indexed?
        end
      end


      context "ON PUT to unyank for version 0.1.1" do
        setup do
          put :unyank, :gem_name => @rubygem.to_param, :version => @v2.number
        end
        should respond_with :unprocessable_entity
      end
    end
  end

  def should_return_latest_gems(gems)
    assert_equal 2, gems.length
    gems.each {|g| assert g.is_a?(Hash) }
    assert_equal @rubygem_2.attributes['name'], gems[0]['name']
    assert_equal @rubygem_3.attributes['name'], gems[1]['name']
  end

  def should_return_just_updated_gems(gems)
    assert_equal 3, gems.length
    gems.each {|g| assert g.is_a?(Hash) }
    assert_equal @rubygem_1.attributes['name'], gems[0]['name']
    assert_equal @rubygem_2.attributes['name'], gems[1]['name']
    assert_equal @rubygem_3.attributes['name'], gems[2]['name']
  end

  context "No signed in-user" do
    context "On GET to index with JSON for a list of gems" do
      setup do
        get :index, :format => "json"
      end
      should "deny access" do
        assert_response 401
        assert_match "Access Denied. Please sign up for an account at http://rubygems.org", @response.body
      end
    end

    context "On GET to latest" do
      setup do
        @rubygem_1 = Factory(:rubygem)
        @version_1 = Factory(:version, :rubygem => @rubygem_1)
        @version_2 = Factory(:version, :rubygem => @rubygem_1)

        @rubygem_2 = Factory(:rubygem)
        @version_3 = Factory(:version, :rubygem => @rubygem_2)

        @rubygem_3 = Factory(:rubygem)
        @version_4 = Factory(:version, :rubygem => @rubygem_3)

        stub(Rubygem).latest(50){ [@rubygem_2, @rubygem_3] }
      end

      should "return correct JSON for latest gems" do
        get :latest, :format => :json
        should_return_latest_gems MultiJson.decode(@response.body)
      end

      should "return correct YAML for latest gems" do
        get :latest, :format => :yaml
        should_return_latest_gems YAML.load(@response.body)
      end

      should "return correct XML for latest gems" do
        get :latest, :format => :xml
        gems = Hash.from_xml(Nokogiri.parse(@response.body).to_xml)['rubygems']
        should_return_latest_gems(gems)
      end
    end

    context "On GET to just_updated" do
      setup do
        @rubygem_1 = Factory(:rubygem)
        @version_1 = Factory(:version, :rubygem => @rubygem_1)
        @version_2 = Factory(:version, :rubygem => @rubygem_1)

        @rubygem_2 = Factory(:rubygem)
        @version_3 = Factory(:version, :rubygem => @rubygem_2)

        @rubygem_3 = Factory(:rubygem)
        @version_4 = Factory(:version, :rubygem => @rubygem_3)

        stub(Version).just_updated(50){ [@version_2, @version_3, @version_4] }
      end

      should "return correct JSON for just_updated gems" do
        get :just_updated, :format => :json
        should_return_just_updated_gems MultiJson.decode(@response.body)
      end

      should "return correct YAML for just_updated gems" do
        get :just_updated, :format => :yaml
        should_return_just_updated_gems YAML.load(@response.body)
      end

      should "return correct XML for just_updated gems" do
        get :just_updated, :format => :xml
        gems = Hash.from_xml(Nokogiri.parse(@response.body).to_xml)['rubygems']
        should_return_just_updated_gems(gems)
      end
    end

  end
end
