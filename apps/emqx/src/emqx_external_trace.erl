%%--------------------------------------------------------------------
%% Copyright (c) 2023-2024 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------
-module(emqx_external_trace).

-include("emqx_external_trace.hrl").

%% --------------------------------------------------------------------
%% Trace in Rich mode callbacks

%% Client Connect/Disconnect
-callback client_connect(Packet, InitAttrs, fun((Packet) -> Res)) -> Res when
    Packet :: emqx_types:packet(),
    InitAttrs :: attrs(),
    Res :: term().

-callback client_disconnect(Packet, InitAttrs, fun((Packet) -> Res)) -> Res when
    Packet :: emqx_types:packet(),
    InitAttrs :: attrs(),
    Res :: term().

-callback client_subscribe(Packet, InitAttrs, fun((Packet) -> Res)) -> Res when
    Packet :: emqx_types:packet(),
    InitAttrs :: attrs(),
    Res :: term().

-callback client_unsubscribe(Packet, InitAttrs, fun((Packet) -> Res)) -> Res when
    Packet :: emqx_types:packet(),
    InitAttrs :: attrs(),
    Res :: term().

-callback client_authn(Packet, InitAttrs, fun((Packet) -> Res)) -> Res when
    Packet :: emqx_types:packet(),
    InitAttrs :: attrs(),
    Res :: term().

-callback client_authz(Packet, InitAttrs, fun((Packet) -> Res)) -> Res when
    Packet :: emqx_types:packet(),
    InitAttrs :: attrs(),
    Res :: term().

%% Message Processing Spans
%% PUBLISH(form Publisher) -> ROUTE -> FORWARD(optional) -> DISPATCH -> DELIVER(to Subscribers)
-callback msg_publish(Packet, InitAttrs, fun((Packet) -> Res)) -> Res when
    Packet :: emqx_types:packet(),
    InitAttrs :: attrs(),
    Res :: term().

-callback msg_route(Delivery, InitAttrs, fun((Delivery) -> Res)) -> Res when
    InitAttrs :: attrs(),
    Delivery :: emqx_types:delivery(),
    Res :: term().

-callback msg_dispatch(Delivery, InitAttrs, fun((Delivery) -> Res)) -> Res when
    InitAttrs :: attrs(),
    Delivery :: emqx_types:delivery(),
    Res :: term().

%% @doc Trace message forwarding
%% The span `message.forward` always starts in the publisher process and ends in the subscriber process.
%% They are logically two unrelated processes. So the SpanCtx always need to be propagated.
-callback msg_forward(Delivery, InitAttrs, fun((Delivery) -> Res)) -> Res when
    InitAttrs :: attrs(),
    Delivery :: emqx_types:delivery(),
    Res :: term().

-callback msg_handle_forward(Delivery, InitAttrs, fun((Delivery) -> Res)) -> Res when
    InitAttrs :: attrs(),
    Delivery :: emqx_types:delivery(),
    Res :: term().

-callback msg_deliver(
    TraceAction,
    list(Deliver) | Packet | list(Packet),
    Attrs
) -> Deliver when
    TraceAction :: ?EXT_TRACE_START | ?EXT_TRACE_STOP,
    Deliver :: emqx_types:deliver(),
    Packet :: emqx_types:packet(),
    Attrs :: attrs().

%% --------------------------------------------------------------------
%% Span enrichments APIs

-callback add_span_attrs(Attrs) -> ok when
    Attrs :: attrs() | attrs_meta().

-callback add_span_event(EventName, Attrs) -> ok when
    EventName :: event_name(),
    Attrs :: attrs() | attrs_meta().

%% --------------------------------------------------------------------
%% Legacy mode callbacks

%% -callback end_trace_send(Packet | [Packet]) -> ok when
%%     Packet :: emqx_types:packet().

-optional_callbacks(
    [
        add_span_attrs/1,
        add_span_event/2,
        client_authn/3,
        client_authz/3
    ]
).

%% --------------------------------------------------------------------

-export([
    client_connect/3,
    client_disconnect/3,
    client_subscribe/3,
    client_unsubscribe/3,
    client_authn/3,
    client_authz/3,
    msg_publish/3,
    msg_route/3,
    msg_dispatch/3,
    msg_forward/3,
    msg_handle_forward/3,
    msg_deliver/3
]).

-export([
    add_span_attrs/1,
    add_span_event/2
]).

-export([
    provider/0,
    register_provider/1,
    unregister_provider/1
]).

-define(PROVIDER, {?MODULE, trace_provider}).

%% TODO:
%% check both trace_mode and trace_provider
-define(with_provider(IfRegistered, IfNotRegistered),
    case persistent_term:get(?PROVIDER, undefined) of
        undefined ->
            IfNotRegistered;
        Provider ->
            Provider:IfRegistered
    end
).

%%--------------------------------------------------------------------
%% provider API
%%--------------------------------------------------------------------

-spec register_provider(module()) -> ok | {error, term()}.
register_provider(Module) when is_atom(Module) ->
    case is_valid_provider(Module) of
        true ->
            persistent_term:put(?PROVIDER, Module);
        false ->
            {error, invalid_provider}
    end.

-spec unregister_provider(module()) -> ok | {error, term()}.
unregister_provider(Module) ->
    case persistent_term:get(?PROVIDER, undefined) of
        Module ->
            persistent_term:erase(?PROVIDER),
            ok;
        _ ->
            {error, not_registered}
    end.

-spec provider() -> module() | undefined.
provider() ->
    persistent_term:get(?PROVIDER, undefined).

%%--------------------------------------------------------------------
%% Trace in Rich mode API
%%--------------------------------------------------------------------

%% @doc Start a trace event for Client CONNECT
-spec client_connect(Packet, InitAttrs, fun((Packet) -> Res)) -> Res when
    Packet :: emqx_types:packet(),
    InitAttrs :: attrs(),
    Res :: term().
client_connect(Packet, InitAttrs, ProcessFun) ->
    ?with_provider(?FUNCTION_NAME(Packet, InitAttrs, ProcessFun), ProcessFun(Packet)).

%% @doc Start a trace event for Client DISCONNECT
-spec client_disconnect(Packet, InitAttrs, fun((Packet) -> Res)) -> Res when
    Packet :: emqx_types:packet(),
    InitAttrs :: attrs(),
    Res :: term().
client_disconnect(Packet, InitAttrs, ProcessFun) ->
    ?with_provider(?FUNCTION_NAME(Packet, InitAttrs, ProcessFun), ProcessFun(Packet)).

%% @doc Start a trace event for Client SUBSCRIBE
-spec client_subscribe(Packet, InitAttrs, fun((Packet) -> Res)) -> Res when
    Packet :: emqx_types:packet(),
    InitAttrs :: attrs(),
    Res :: term().
client_subscribe(Packet, InitAttrs, ProcessFun) ->
    ?with_provider(?FUNCTION_NAME(Packet, InitAttrs, ProcessFun), ProcessFun(Packet)).

%% @doc Start a trace event for Client UNSUBSCRIBE
-spec client_unsubscribe(Packet, InitAttrs, fun((Packet) -> Res)) -> Res when
    Packet :: emqx_types:packet(),
    InitAttrs :: attrs(),
    Res :: term().
client_unsubscribe(Packet, InitAttrs, ProcessFun) ->
    ?with_provider(?FUNCTION_NAME(Packet, InitAttrs, ProcessFun), ProcessFun(Packet)).

%% @doc Start a sub-span for Client AUTHN
-spec client_authn(Packet, InitAttrs, fun((Packet) -> Res)) -> Res when
    Packet :: emqx_types:packet(),
    InitAttrs :: attrs(),
    Res :: term().
client_authn(Packet, InitAttrs, ProcessFun) ->
    ?with_provider(?FUNCTION_NAME(Packet, InitAttrs, ProcessFun), ProcessFun(Packet)).

%% @doc Start a sub-span for Client AUTHZ
-spec client_authz(Packet, InitAttrs, fun((Packet) -> Res)) -> Res when
    Packet :: emqx_types:packet(),
    InitAttrs :: attrs(),
    Res :: term().
client_authz(Packet, InitAttrs, ProcessFun) ->
    ?with_provider(?FUNCTION_NAME(Packet, InitAttrs, ProcessFun), ProcessFun(Packet)).

%% TODO:
%% split to:
%% `msg_publish/3` for legacy_mode
%% `trace_client_publish/3` for end_to_end_mode
%% @doc Trace message processing from publisher
-spec msg_publish(Packet, InitAttrs, fun((Packet) -> Res)) -> Res when
    Packet :: emqx_types:packet(),
    InitAttrs :: attrs(),
    Res :: term().
msg_publish(Packet, InitAttrs, ProcessFun) ->
    ?with_provider(?FUNCTION_NAME(Packet, InitAttrs, ProcessFun), ProcessFun(Packet)).

-spec msg_route(Delivery, InitAttrs, fun((Delivery) -> Res)) -> Res when
    Delivery :: emqx_types:delivery(),
    InitAttrs :: attrs(),
    Res :: term().
msg_route(Delivery, InitAttrs, ProcessFun) ->
    ?with_provider(?FUNCTION_NAME(Delivery, InitAttrs, ProcessFun), ProcessFun(Delivery)).

-spec msg_dispatch(Delivery, InitAttrs, fun((Delivery) -> Res)) -> Res when
    Delivery :: emqx_types:delivery(),
    InitAttrs :: attrs(),
    Res :: term().
msg_dispatch(Delivery, InitAttrs, ProcessFun) ->
    ?with_provider(?FUNCTION_NAME(Delivery, InitAttrs, ProcessFun), ProcessFun(Delivery)).

-spec msg_forward(Delivery, InitAttrs, fun((Delivery) -> Res)) -> Res when
    Delivery :: emqx_types:delivery(),
    InitAttrs :: attrs(),
    Res :: term().
msg_forward(Delivery, InitAttrs, ProcessFun) ->
    ?with_provider(?FUNCTION_NAME(Delivery, InitAttrs, ProcessFun), ProcessFun(Delivery)).

-spec msg_handle_forward(Delivery, InitAttrs, fun((Delivery) -> Res)) -> Res when
    InitAttrs :: attrs(),
    Delivery :: emqx_types:delivery(),
    Res :: term().
msg_handle_forward(Delivery, InitAttrs, ProcessFun) ->
    ?with_provider(?FUNCTION_NAME(Delivery, InitAttrs, ProcessFun), ProcessFun(Delivery)).

%% TODO:
%% split to:
%% `msg_deliver/3` for end_to_end_mode
%% `start_trace_send/2` and `end_trace_send/1` for legacy_mode

%% @doc Start Trace message delivery to subscriber
-spec msg_deliver(
    TraceAction,
    list(Deliver) | Packet | list(Packet),
    Attrs
) -> Deliver when
    TraceAction :: ?EXT_TRACE_START | ?EXT_TRACE_STOP,
    Deliver :: emqx_types:deliver(),
    Packet :: emqx_types:packet(),
    Attrs :: attrs().
msg_deliver(TraceAction, DeliverOrPackets, Attrs) ->
    ?with_provider(
        ?FUNCTION_NAME(TraceAction, DeliverOrPackets, Attrs),
        deliver_without_provider(TraceAction, DeliverOrPackets)
    ).

%% --------------------------------------------------------------------
%% Span enrichments APIs
%% --------------------------------------------------------------------

%% @doc Enrich trace attributes
-spec add_span_attrs(AttrsOrMeta) -> ok when
    AttrsOrMeta :: attrs() | attrs_meta().
add_span_attrs(AttrsOrMeta) ->
    _ = catch ?with_provider(?FUNCTION_NAME(AttrsOrMeta), ok),
    ok.

%% @doc Add trace event
-spec add_span_event(EventName, AttrsOrMeta) -> ok when
    EventName :: event_name(),
    AttrsOrMeta :: attrs() | attrs_meta().
add_span_event(EventName, AttrsOrMeta) ->
    _ = catch ?with_provider(?FUNCTION_NAME(EventName, AttrsOrMeta), ok),
    ok.

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

deliver_without_provider(?EXT_TRACE_START, DeliverOrPackets) ->
    DeliverOrPackets;
deliver_without_provider(?EXT_TRACE_STOP, _Packets) ->
    ok.

%% TODO:
%% 1. Add more checks for the provider module and functions
%% 2. Add more checks for the trace functions
is_valid_provider(Module) ->
    lists:all(
        fun({F, A}) -> erlang:function_exported(Module, F, A) end,
        ?MODULE:behaviour_info(callbacks) -- ?MODULE:behaviour_info(optional_callbacks)
    ).
