require 'fluent/mixin/rewrite_tag_name'

class Fluent::GraphiteOutput < Fluent::Output
  Fluent::Plugin.register_output('graphite', self)

  include Fluent::HandleTagNameMixin
  include Fluent::Mixin::RewriteTagName

  config_param :host, :string
  config_param :port, :integer, default: 2003
  config_param :tag_for, :string, default: 'prefix'
  config_param :name_keys, :string, default: nil
  config_param :name_key_pattern, :string, default: nil

  def initialize
    super
    require 'graphite-api'
  end

  def start
    super
    @client = GraphiteAPI.new(graphite: "#{@host}:#{@port}")
  end

  def configure(conf)
    super

    if !['prefix', 'suffix', 'ignore'].include?(@tag_for)
      raise Fluent::ConfigError, 'out_graphite: can specify to tag_for only prefix, suffix or ignore'
    end

    if !@name_keys && !@name_key_pattern
      raise Fluent::ConfigError, 'out_graphite: missing both of name_keys and name_key_pattern'
    end
    if @name_keys && @name_key_pattern
      raise Fluent::ConfigError, 'out_graphite: cannot specify both of name_keys and name_key_pattern'
    end

    if @name_keys
      @name_keys = @name_keys.split(',')
    end
    if @name_key_pattern
      @name_key_pattern = Regexp.new(@name_key_pattern)
    end
  end

  def emit(tag, es, chain)
    es.each do |time, record|
      emit_tag = tag.dup
      filter_record(emit_tag, time, record)
      next unless metrics = format_metrics(emit_tag, record)
      post(metrics, time)
    end

    chain.next
  end

  def format_metrics(tag, record)
    filtered_record = if @name_keys
                        record.select { |k,v| @name_keys.include?(k) }
                      else # defined @name_key_pattern
                        record.select { |k,v| @name_key_pattern.match(k) }
                      end

    return nil if filtered_record.empty?

    metrics = {}
    filtered_record.each do |k, v|
      key = case @tag_for
            when 'ignore' then k
            when 'prefix' then tag + k
            when 'suffix' then k + '.' + tag.sub(/\.$/, '')
            end

      metrics[key.gsub(/\s+/, '_')] = v.to_f
    end
    metrics
  end

  def post(metrics, time)
    @client.metrics(metrics, time)
  rescue Errno::ECONNREFUSED
    $log.warn "out_graphite: connection refused by #{@host}:#{@port}"
  end
end
