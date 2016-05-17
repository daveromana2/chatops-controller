require 'rails_helper'

describe ActionController::Base, type: :controller do
  controller do
    include ChatOps::Controller
    chatops_namespace :test
    chatops_help "ChatOps of and relating to testing"

    chatop :wcid,
    /(?:where can i deploy|wcid)(?: (?<app>\S+))?/,
    "where can i deploy?" do
      return jsonrpc_invalid_params("I need nope, sorry") if jsonrpc_params[:app] == "nope"
      jsonrpc_success "You can deploy #{jsonrpc_params[:app]} just fine."
    end

    chatop :foobar,
    /(?:how can i foo and bar all at once)?/,
    "how to foo and bar" do
      raise "there's always params" unless jsonrpc_params.respond_to?(:[])
      jsonrpc_success "You just foo and bar like it just don't matter"
    end

    def non_chatop_method
      render :text => "Why would you have something thats not a chatop?"
    end
  end

  before :each do
    routes.draw do
      post "/_chatops" => "anonymous#execute"
      get  "/_chatops" => "anonymous#list"
      get  "/other" => "anonymous#non_chatop_method"
    end

    ENV["CHATOPS_AUTH_TOKEN"] = "foo"
    ENV["CHATOPS_ALT_AUTH_TOKEN"] = "bar"
  end

  it "requires authentication" do
    get :list
    expect(response.status).to eq 403
    expect(response.body).to eq "Not authorized"
  end

  it "allows authentication" do
    chatops_auth! "_", ENV["CHATOPS_AUTH_TOKEN"]
    get :list
    expect(response.status).to eq 200
    expect(response).to be_valid_json
  end

  it "allows authentication from a second token" do
    chatops_auth! "_", ENV["CHATOPS_ALT_AUTH_TOKEN"]
    get :list
    expect(response.status).to eq 200
    expect(response).to be_valid_json
  end

  it "requires a correct password" do
    chatops_auth! "_", "oogaboogawooga"
    get :list
    expect(response.status).to eq 403
    expect(response.body).to eq "Not authorized"
  end

  it "does not add authentication to non-chatops routes" do
    get :non_chatop_method
    expect(response.status).to eq 200
    expect(response.body).to eq "Why would you have something thats not a chatop?"
  end

  context "when authenticated" do
    before do
      chatops_auth!
    end

    it "provides a list method" do
      get :list
      expect(response.status).to eq 200
      expect(json_response).to eq({
        "namespace" => "test",
        "help" => "ChatOps of and relating to testing",
        "methods" => {
          "wcid" => {
            "help" => "where can i deploy?",
            "regex" => /(?:where can i deploy|wcid)(?: (?<app>\S+))?/.source,
            "params" => ["app"]
          },
          "foobar" => {
            "help" => "how to foo and bar",
            "regex" => /(?:how can i foo and bar all at once)?/.source,
            "params" => []

          }
        }
      })
    end

    it "requires a user be sent to chatops" do
      post :execute, :method => "foobar"
      expect(response.status).to eq 400
      expect(json_response).to eq({
        "jsonrpc" => "2.0",
        "id" => nil,
        "error" => {
          "code" => -32602,
          "message" => "A username must be supplied as 'user'"
        }
      })
    end

    it "returns method not found for a not found method" do
      post :execute, :method => "barfoo", :user => "foo"
      expect(json_response).to eq({
        "jsonrpc" => "2.0",
        "id" => nil,
        "error" => {
          "code" => -32601,
          "message" => "Method not found"
        }
      })
      expect(response.status).to eq 404
    end

    it "runs a known method" do
      post :execute, :method => "foobar", :user => "foo"
      expect(json_response).to eq({
        "jsonrpc" => "2.0",
        "id" => nil,
        "result" => "You just foo and bar like it just don't matter"
      })
      expect(response.status).to eq 200
    end

    it "passes parameters to methods" do
      post :execute, :method => "wcid", :user => "foo", :params => { "app" => "foo" }
      expect(json_response).to eq({
        "jsonrpc" => "2.0",
        "id" => nil,
        "result" => "You can deploy foo just fine."
      })
      expect(response.status).to eq 200
    end

    it "allows methods to return invalid params with a message" do
      post :execute, :method => "wcid", :user => "foo", :params => { "app" => "nope" }
      expect(response.status).to eq 400
      expect(json_response).to eq({
        "jsonrpc" => "2.0",
        "id" => nil,
        "error" => {
          "code" => -32602,
          "message" => "I need nope, sorry"
        }
      })
    end

    context "rspec helpers" do
      it "makes it easy to test a response" do
        chatop "wcid", :user => "foo", :app => "foo"
        expect(chatop_response).to eq "You can deploy foo just fine."
      end

      it "makes it easy to test an error message" do
        chatop "wcid", :user => "foo", :app => "nope"
        expect(chatop_error).to eq "I need nope, sorry"
      end
    end
  end
end
