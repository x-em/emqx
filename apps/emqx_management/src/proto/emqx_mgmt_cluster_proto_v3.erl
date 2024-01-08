%%--------------------------------------------------------------------
%% Copyright (c) 2024 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_mgmt_cluster_proto_v3).

-behaviour(emqx_bpapi).

-export([
    introduced_in/0,
    invite_node/3,
    connected_replicants/1
]).

-include_lib("emqx/include/bpapi.hrl").

introduced_in() ->
    "5.5.0".

-spec invite_node(node(), node(), timeout()) -> ok | ignore | {error, term()} | emqx_rpc:badrpc().
invite_node(Node, Self, Timeout) when is_integer(Timeout) ->
    rpc:call(Node, emqx_mgmt_api_cluster, join, [Self], Timeout).

-spec connected_replicants([node()]) -> emqx_rpc:multicall_result().
connected_replicants(Nodes) ->
    rpc:multicall(Nodes, emqx_mgmt_api_cluster, connected_replicants, [], 30_000).
