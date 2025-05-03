class LandingController < ApplicationController
    def index
        @username = ENV.fetch("USERNAME", "env is not set")
        @password = ENV.fetch("PASSWORD", "env is not set")
    end
end
