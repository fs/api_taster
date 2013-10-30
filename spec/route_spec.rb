require 'spec_helper'

module ApiTaster
  describe Route do
    context "undefined ApiTaster.routes" do
      it "errors out" do
        Route.route_set = nil
        expect { Route.normalise_routes! }.to raise_exception(ApiTaster::Exception)
      end
    end

    let(:app_home_route) do
      {
        :id   => 1,
        :name => 'home',
        :verb => 'GET',
        :path => '/home',
        :reqs => {
          :controller => 'application',
          :action => 'home'
        }
      }
    end

    before do
      routes = ActionDispatch::Routing::RouteSet.new
      routes.draw do
        get 'home' => 'application#home', :as => :home
        match 'dual_action' => 'dummy/action', :via => [:get, :delete]
        resources :users do
          resources :comments
        end
        mount Rails.application => '/app'
        mount proc {} => '/rack_app'

        get 'rails/info/properties' => 'rails/info#properties', :as => :rails_info_properties
        get '/' => 'rails/welcome#index'
      end

      Rails.application.stub(:routes).and_return(routes)
      Route.map_routes
    end

    it "lazy loads the mapping" do
      Route.mappings.should be_kind_of(Proc)
    end

    it "#routes" do
      Route.routes.first.should == app_home_route
    end

    it "finds rack app routes" do
      Route.find_by_verb_and_path(:get, '/app/home').should_not == nil
    end

    it "outputs routes for all verbs" do
      Route.find_by_verb_and_path(:get, '/dual_action').should_not == nil
      Route.find_by_verb_and_path(:delete, '/dual_action').should_not == nil
    end

    it "#grouped_routes" do
      home_route = Route.find_by_verb_and_path(:get, '/app/home')
      Route.supplied_params[home_route[:id]] = {}

      Route.grouped_routes.has_key?('application').should == true
      Route.grouped_routes.has_key?('comments').should == false
    end

    it "#find" do
      Route.find(1).should == app_home_route
      Route.find(999).should == nil
    end

    it "#find_by_verb_and_path" do
      Route.find_by_verb_and_path(:get, '/home').should == app_home_route
      Route.find_by_verb_and_path(:get, '/dummy').should == nil
      Route.find_by_verb_and_path(:delete, '/home').should == nil
    end

    context "get data of a route" do
      before do
        Route.stub(:routes).and_return([{
          :id   => 0,
          :path => '/dummy/:dummy_id'
        }, {
          :id   => 999,
          :path => 'a_non_existing_dummy',
          :verb => 'get'
        }])
        Route.supplied_params[0] = [{ :dummy_id => 1, :hello => 'world' }]
      end

      it "#params_for" do
        Route.params_for(Route.find(999)).should have_key(:undefined)

        2.times do
          Route.params_for(Route.find(0)).should == [{
            :url_params  => { :dummy_id => 1 },
            :post_params => { :hello => 'world' }
          }]
        end
      end

      it "#comment_for" do
        markdown_comment = "Heading\n=======\n * List item 1\n * List item 2"
        Route.comments[0] = markdown_comment

        Route.comment_for(Route.find(0)).should == markdown_comment
      end

      it "#metadata_for" do
        metadata = { :hello => 'world' }
        Route.metadata[0] = metadata

        Route.metadata_for(Route.find(0)).should == metadata
      end
    end

    context "#missing_definitions and #defined_definitions" do
      let(:path) { '/awesome_route' }
      let(:routes) { Route.routes }

      subject { Route }

      before do
        stub_routes = ActionDispatch::Routing::RouteSet.new
        stub_routes.draw do
          get 'awesome_route' => 'awesome#route'
          put 'awesome_route' => 'awesome#route'
          patch 'awesome_route' => 'awesome#route'
        end
        Rails.application.stub(:routes).and_return(stub_routes)
      end

      context 'when routes are not defined' do
        before do
          Route.map_routes
        end

        its(:missing_definitions) { should eq routes }
        its(:defined_definitions) { should be_blank }
      end

      context 'when routes are defined' do
        before do
          Route.map_routes "#{Rails.root}/lib/api_tasters/route"
        end

        its(:missing_definitions) { should eq Array.wrap Route.find_by_verb_and_path(:get, path) }
        its(:defined_definitions) { should eq Array.wrap Route.find_by_verb_and_path(:patch, path) }
      end
    end

    context "private methods" do
      it "#discover_rack_app" do
        klass = Class.new
        klass.stub_chain(:class, :name).and_return(ActionDispatch::Routing::Mapper::Constraints)
        klass.stub(:app).and_return('klass')

        Route.send(:discover_rack_app, klass).should == 'klass'
      end

      it "#discover_rack_app" do
        Route.send(:discover_rack_app, ApiTaster::Engine).should == ApiTaster::Engine
      end
    end
  end
end
