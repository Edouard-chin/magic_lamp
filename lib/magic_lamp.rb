require "rake"

require "magic_lamp/callbacks"

require "magic_lamp/configuration"
require "magic_lamp/fixture_creator"
require "magic_lamp/render_catcher"
require "magic_lamp/engine"

require "tasks/lint_task"
require "tasks/fixture_names_task"

module MagicLamp
  APPLICATION = "application"
  LAMP = "_lamp"
  SPEC = "spec"
  STARS = "**"
  TEST = "test"
  Genie = Engine

  class AmbiguousFixtureNameError < StandardError
  end

  class UnregisteredFixtureError < StandardError
  end

  class AlreadyRegisteredFixtureError < StandardError
  end

  class ArgumentError < StandardError
  end

  class << self
    attr_accessor :registered_fixtures, :configuration

    def path
      Rails.root.join(directory_path)
    end

    def register_fixture(options = {}, &render_block)
      raise_missing_block_error(render_block, __method__)

      options[:controller] ||= ::ApplicationController
      options[:extend] = Array(options[:extend])
      options[:render_block] = render_block
      fixture_name = fixture_name_or_raise(options.delete(:name), options[:controller], render_block)

      if registered?(fixture_name)
        raise AlreadyRegisteredFixtureError, "a fixture called '#{fixture_name}' has already been registered"
      end

      registered_fixtures[fixture_name] = options
    end

    alias_method :register, :register_fixture
    alias_method :fixture, :register_fixture
    alias_method :rub, :register_fixture
    alias_method :wish, :register_fixture

    def configure(&block)
      raise_missing_block_error(block, __method__)
      self.configuration = Configuration.new
      block.call(configuration)
    end

    def registered?(fixture_name)
      registered_fixtures.key?(fixture_name)
    end

    def load_config
      load_all(config_files)
    end

    def load_lamp_files
      self.registered_fixtures = {}
      load_config
      load_all(lamp_files)
    end

    def generate_fixture(fixture_name)
      unless registered?(fixture_name)
        raise UnregisteredFixtureError, "'#{fixture_name}' is not a registered fixture"
      end
      controller_class, block = registered_fixtures[fixture_name].values_at(:controller, :render_block)
      FixtureCreator.new(configuration).generate_template(controller_class, &block)
    end

    def generate_all_fixtures
      load_lamp_files
      registered_fixtures.keys.each_with_object({}) do |fixture_name, fixtures|
        fixtures[fixture_name] = generate_fixture(fixture_name)
      end
    end

    private

    def fixture_name_or_raise(fixture_name, controller_class, block)
      if fixture_name.nil? && configuration.infer_names
        default_fixture_name(controller_class, block)
      elsif fixture_name.nil?
        raise ArgumentError, "You must specify a name since `infer_names` is configured to `false`"
      else
        fixture_name
      end
    end

    def raise_missing_block_error(block, method_name)
      if block.nil?
        raise ArgumentError, "MagicLamp##{method_name} requires a block"
      end
    end

    def config_files
      Dir[path.join(STARS, "magic#{LAMP}_config.rb")]
    end

    def lamp_files
      Dir[path.join(STARS, "*#{LAMP}.rb")]
    end

    def default_fixture_name(controller_class, block)
      first_arg = first_render_arg(block)
      fixture_name = template_name(first_arg).to_s
      if fixture_name.blank?
        raise AmbiguousFixtureNameError, "Unable to infer fixture name"
      end
      fixture_name = prepend_controller_name(fixture_name, controller_class)
      fixture_name
    end

    def first_render_arg(block)
      render_catcher = RenderCatcher.new(configuration)
      render_catcher.first_render_argument(&block)
    end

    def template_name(render_arg)
      if render_arg.is_a?(Hash)
        render_arg[:template] || render_arg[:partial]
      else
        render_arg
      end
    end

    def prepend_controller_name(fixture_name, controller_class)
      controller_name = controller_class.controller_name
      if starts_with_controller_name?(fixture_name, controller_name)
        fixture_name
      else
        "#{controller_name}/#{fixture_name}"
      end
    end

    def starts_with_controller_name?(fixture_name, controller_name)
      controller_name_regex = Regexp.new("\\A#{controller_name}")
      fixture_name.match(controller_name_regex) || controller_name == APPLICATION
    end

    def directory_path
      Dir.exist?(Rails.root.join(SPEC)) ? SPEC : TEST
    end

    def load_all(files)
      files.each { |file| load file }
    end
  end
end

MagicLamp.configuration = MagicLamp::Configuration.new
