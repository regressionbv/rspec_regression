require 'json'
require 'httparty'

module RspecRegression
  class QueryRegressor
    attr :current_example, :examples

    class << self
      def regressor
        @regressor ||= new
      end

      def start_example(example)
        x = RspecRegression::Example.new(example)
        regressor.start x.slugify(example), example.metadata[:location]
      end

      def end_example
        regressor.end
      end

      def store
        regressor.store
      end
    end

    def initialize
      @sqls = []
      @examples = []
      @subscribed_to_notifications = false
    end

    def start(example_name, example_location)
      subscribe_to_notifications unless @subscribed_to_notifications
      @current_example = { example_name: example_name, example_location: example_location, queries: [] }
    end

    def end
      examples << current_example
      @current_example = nil
    end

    def store
      return if ENV['NO_REGRESSOR_NO'].present?
      RegressorStore.new(examples).store
    end

    def add_query(query)
      current_example[:queries] << RspecRegression::Sql.new(query).clean unless current_example.nil?
    end

    private

    def subscribe_to_notifications
      ActiveSupport::Notifications.subscribe "sql.active_record" do |name, started, finished, unique_id, data|
        RspecRegression::QueryRegressor.regressor.add_query data[:sql]
      end

      @subscribed_to_notifications = true
    end
  end

  class RegressorStore
    def initialize(examples)
      @examples = examples
    end

    def store
      HTTParty.post regressor_url, body: body, headers: headers
    end

    private

    attr_reader :examples

    def body
      {
        result_data: examples,
        project_id: project_id,
        tag: tag,
      }
    end

    def headers
      {
        'AUTHORIZATION' => "Token token=\"#{regressor_api_token}\"",
      }
    end

    def regressor_domain
      ENV.fetch 'REGRESSOR_DOMAIN', 'http://regressor.herokuapp.com'
    end

    def regressor_project_id
      ENV['REGRESSOR_PROJECT_ID']
    end

    def regressor_url
      "#{regressor_domain}/api/results"
    end

    def regressor_api_token
      ENV['REGRESSOR_API_TOKEN']
    end

    def project_id
      ENV['REGRESSOR_PROJECT_ID']
    end

    def tag
      ENV['REGRESSOR_TAG']
    end
  end
end
