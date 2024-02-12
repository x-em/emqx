%%--------------------------------------------------------------------
%% Copyright (c) 2024 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

-module(emqx_bridge_s3_SUITE).

-compile(nowarn_export_all).
-compile(export_all).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

-import(emqx_utils_conv, [bin/1]).

%% See `emqx_bridge_s3.hrl`.
-define(BRIDGE_TYPE, <<"s3">>).
-define(CONNECTOR_TYPE, <<"s3">>).

-define(PROXY_NAME, "minio_tcp").
-define(CONTENT_TYPE, "application/x-emqx-payload").

%% CT Setup

all() ->
    emqx_common_test_helpers:all(?MODULE).

init_per_suite(Config) ->
    % Setup toxiproxy
    ProxyHost = os:getenv("PROXY_HOST", "toxiproxy"),
    ProxyPort = list_to_integer(os:getenv("PROXY_PORT", "8474")),
    _ = emqx_common_test_helpers:reset_proxy(ProxyHost, ProxyPort),
    Apps = emqx_cth_suite:start(
        [
            emqx,
            emqx_conf,
            emqx_connector,
            emqx_bridge_s3,
            emqx_bridge,
            emqx_rule_engine,
            emqx_management,
            {emqx_dashboard, "dashboard.listeners.http { enable = true, bind = 18083 }"}
        ],
        #{work_dir => emqx_cth_suite:work_dir(Config)}
    ),
    {ok, _} = emqx_common_test_http:create_default_app(),
    [
        {apps, Apps},
        {proxy_host, ProxyHost},
        {proxy_port, ProxyPort},
        {proxy_name, ?PROXY_NAME}
        | Config
    ].

end_per_suite(Config) ->
    ok = emqx_cth_suite:stop(?config(apps, Config)).

%% Testcases

init_per_testcase(TestCase, Config) ->
    ct:timetrap(timer:seconds(30)),
    ok = snabbkaffe:start_trace(),
    Name = iolist_to_binary(io_lib:format("~s~p", [TestCase, erlang:unique_integer()])),
    ConnectorConfig = connector_config(Name, Config),
    ActionConfig = action_config(Name, Name),
    [
        {connector_type, ?CONNECTOR_TYPE},
        {connector_name, Name},
        {connector_config, ConnectorConfig},
        {bridge_type, ?BRIDGE_TYPE},
        {bridge_name, Name},
        {bridge_config, ActionConfig}
        | Config
    ].

end_per_testcase(_TestCase, _Config) ->
    ok = snabbkaffe:stop(),
    ok.

connector_config(Name, _Config) ->
    BaseConf = emqx_s3_test_helpers:base_raw_config(tcp),
    parse_and_check_config(<<"connectors">>, ?CONNECTOR_TYPE, Name, #{
        <<"enable">> => true,
        <<"description">> => <<"S3 Connector">>,
        <<"host">> => maps:get(<<"host">>, BaseConf),
        <<"port">> => maps:get(<<"port">>, BaseConf),
        <<"access_key_id">> => maps:get(<<"access_key_id">>, BaseConf),
        <<"secret_access_key">> => maps:get(<<"secret_access_key">>, BaseConf),
        <<"transport_options">> => #{
            <<"headers">> => #{
                <<"content-type">> => <<?CONTENT_TYPE>>
            },
            <<"connect_timeout">> => 1000,
            <<"request_timeout">> => 1000,
            <<"pool_size">> => 4,
            <<"max_retries">> => 0,
            <<"enable_pipelining">> => 1
        }
    }).

action_config(Name, ConnectorId) ->
    parse_and_check_config(<<"actions">>, ?BRIDGE_TYPE, Name, #{
        <<"enable">> => true,
        <<"connector">> => ConnectorId,
        <<"parameters">> => #{
            <<"bucket">> => <<"${clientid}">>,
            <<"key">> => <<"${topic}">>,
            <<"content">> => <<"${payload}">>,
            <<"acl">> => <<"public_read">>
        },
        <<"resource_opts">> => #{
            <<"buffer_mode">> => <<"memory_only">>,
            <<"buffer_seg_bytes">> => <<"10MB">>,
            <<"health_check_interval">> => <<"5s">>,
            <<"inflight_window">> => 40,
            <<"max_buffer_bytes">> => <<"256MB">>,
            <<"metrics_flush_interval">> => <<"1s">>,
            <<"query_mode">> => <<"sync">>,
            <<"request_ttl">> => <<"60s">>,
            <<"resume_interval">> => <<"5s">>,
            <<"worker_pool_size">> => <<"4">>
        }
    }).

parse_and_check_config(Root, Type, Name, ConfigIn) ->
    Schema =
        case Root of
            <<"connectors">> -> emqx_connector_schema;
            <<"actions">> -> emqx_bridge_v2_schema
        end,
    #{Root := #{Type := #{Name := Config}}} =
        hocon_tconf:check_plain(
            Schema,
            #{Root => #{Type => #{Name => ConfigIn}}},
            #{required => false, atom_key => false}
        ),
    ct:pal("parsed config: ~p", [Config]),
    ConfigIn.

t_start_stop(Config) ->
    emqx_bridge_v2_testlib:t_start_stop(Config, s3_bridge_stopped).

t_create_via_http(Config) ->
    emqx_bridge_v2_testlib:t_create_via_http(Config).

t_on_get_status(Config) ->
    emqx_bridge_v2_testlib:t_on_get_status(Config, #{}).

t_sync_query(Config) ->
    Bucket = emqx_s3_test_helpers:unique_bucket(),
    Topic = "a/b/c",
    Payload = rand:bytes(1024),
    AwsConfig = emqx_s3_test_helpers:aws_config(tcp),
    ok = erlcloud_s3:create_bucket(Bucket, AwsConfig),
    ok = emqx_bridge_v2_testlib:t_sync_query(
        Config,
        fun() -> mk_message(Bucket, Topic, Payload) end,
        fun(Res) -> ?assertMatch(ok, Res) end,
        s3_bridge_connector_upload_ok
    ),
    ?assertMatch(
        #{
            content := Payload,
            content_type := ?CONTENT_TYPE
        },
        maps:from_list(erlcloud_s3:get_object(Bucket, Topic, AwsConfig))
    ).

mk_message(ClientId, Topic, Payload) ->
    Message = emqx_message:make(bin(ClientId), bin(Topic), Payload),
    {Event, _} = emqx_rule_events:eventmsg_publish(Message),
    Event.
