-module(exometer_influxdb_test).

-include_lib("eunit/include/eunit.hrl").
-include_lib("exometer_core/include/exometer.hrl").

-include("state.hrl").

-import(exometer_report_influxdb, [evaluate_subscription_options/5,
                                   exometer_info/2,
                                   make_packet/5,
                                   maybe_send/4,
                                   name/1]).


evaluate_subscription_options(MetricId, Options) ->
    evaluate_subscription_options(MetricId, Options, #{}, undefined, []).

evaluate_subscription_options_test() ->
    ?assertEqual({[a, b, c], #{}},
                 evaluate_subscription_options([a, b, c], [])),

    ?assertEqual({[a, b, c], #{tag => d}},
                 evaluate_subscription_options([a, b, c], [{tags, [{tag, d}]}])),

    ?assertEqual({[b, c], #{tag => a}},
                 evaluate_subscription_options([a, b, c], [{tags, [{tag, {from_name, 1}}]}])),

    ?assertEqual({[a, c], #{tag1 => b, tag2 => d}},
                 evaluate_subscription_options([a, b, c], [{tags, [{tag1, {from_name, 2}}, {tag2, d}]}])),

    ?assertEqual({test_name, #{}},
                 evaluate_subscription_options([a, b, c], [{series_name, test_name}])),

    ?assertEqual({<<"test_name">>, #{}},
                 evaluate_subscription_options([a, b, c], [{series_name, <<"test_name">>}])),

    ?assertEqual({test_name, #{}},
                 evaluate_subscription_options([a, b, c], [], [], test_name, [])),

    ?assertEqual({[a, b, c], #{}},
                 evaluate_subscription_options([a, b, c], [{tags, [{tag, undefined}, {undefined, value}]},
                                                           {formatting, [{purge, [{tag_keys, undefined},
                                                                                  {tag_values, undefined}]}]}
                                                          ])),

    DefaultFormatting1 = [{purge, [{tag_keys, undefined}, {tag_values, undefined}]}],
    ?assertEqual({[a, b, c], #{}},
                 evaluate_subscription_options([a, b, c], [{tags, [{tag, undefined}, {undefined, value}]}], [], undefined, DefaultFormatting1)),

    ?assertEqual({[a, b, c], #{tag => b}},
                 evaluate_subscription_options([a, b, c], [{tags, [{tag, {from_name, 2}}]},
                                                           {formatting, [{purge, [{all_from_name, false}]}]}
                                                          ])),

    DefaultFormatting2 = [{purge, [{all_from_name, false}]}],
    ?assertEqual({[a, b, c], #{tag => b}},
                 evaluate_subscription_options([a, b, c], [{tags, [{tag, {from_name, 2}}]}], [], undefined, DefaultFormatting2)),

    ok.

make_packet_with_binary_time_series_test() ->
    {Name, Tags} = evaluate_subscription_options([some, metric, id], [{series_name, <<"binary_id">>}]),
    ?assertEqual(<<"binary_id value=1i ">>,
                 make_bin_packet(Name, Tags, #{value => 1}, false, u)),
    ok.

make_packet_without_timestamping_test() ->
    {Name1, Tags1} = evaluate_subscription_options([a, b, c], []),
    ?assertEqual(<<"a_b_c value=1i ">>,
                 make_bin_packet(Name1, Tags1, #{value => 1}, false, u)),

    {Name2, Tags2} = evaluate_subscription_options([a, b, c], [{tags, [{tag, d}]}]),
    ?assertEqual(<<"a_b_c,tag=d value=1i ">>,
                 make_bin_packet(Name2, Tags2, #{value => 1}, false, u)),

    {Name3, Tags3} = evaluate_subscription_options([a, b, c], [{tags, [{tag, {from_name, 2}}]}]),
    ?assertEqual(<<"a_c,tag=b value=1i ">>,
                 make_bin_packet(Name3, Tags3, #{value => 1}, false, u)),

    {Name4, Tags4} = evaluate_subscription_options([a, b, c], [{tags, [{tag1, d}, {tag2, {from_name, 2}}]}]),
    ?assertEqual(<<"a_c,tag1=d,tag2=b value=1i ">>,
                 make_bin_packet(Name4, Tags4, #{value => 1}, false, u)),

    {Name5, Tags5} = evaluate_subscription_options([a, b, c], [{tags, [{tag, d}]}]),
    ?assertEqual(<<"a_b_c,tag=d value=1i,value2=2i ">>,
                 make_bin_packet(Name5, Tags5, #{value => 1, value2 => 2}, false, u)),

    {Name6, Tags6} = evaluate_subscription_options([a, b, c], [{tags, [{tag1, d}, {tag2, {from_name, 2}}]}]),
    ?assertEqual(<<"a_c,tag1=d,tag2=b value=1i,value2=2i ">>,
                 make_bin_packet(Name6, Tags6, #{value => 1, value2 => 2}, false, u)),
    ok.

make_packet_with_timestamping_test() ->
    {Name1, Tags1} = evaluate_subscription_options([a, b, c], []),

    ?assertEqual(<<"a_b_c value=1i 1456993524527361000">>,
                 make_bin_packet(Name1, Tags1, #{value => 1}, true, n)),

    ?assertEqual(<<"a_b_c value=1i 1456993524527361">>,
                 make_bin_packet(Name1, Tags1, #{value => 1}, true, u)),

    ?assertEqual(<<"a_b_c value=1i 1456993524527">>,
                 make_bin_packet(Name1, Tags1, #{value => 1}, true, ms)),

    ?assertEqual(<<"a_b_c value=1i 1456993525">>,
                 make_bin_packet(Name1, Tags1, #{value => 1}, true, s)),

    ?assertEqual(<<"a_b_c value=1i 24283225">>,
                 make_bin_packet(Name1, Tags1, #{value => 1}, true, m)),

    ?assertEqual(<<"a_b_c value=1i 404720">>,
                 make_bin_packet(Name1, Tags1, #{value => 1}, true, h)),
    ok.

make_packet_with_integer_timestamping_test() ->
    {Name1, Tags1} = evaluate_subscription_options([a, b, c], []),

    ?assertEqual(<<"a_b_c value=1i 10000">>, 
                 make_bin_packet(Name1, Tags1, #{value => 1}, 10000, n)),

    ?assertEqual(<<"a_b_c value=1i 10000">>, 
                 make_bin_packet(Name1, Tags1, #{value => 1}, 10000, s)),

    ok.

subscribtions_module_test() ->
    {ok, Socket} = gen_udp:open(8089),
    Subscribers =  [ 
        {reporters, [
            {exometer_report_influxdb, [{autosubscribe, true}, 
                                        {subscriptions_module, exometer_influxdb_subscribe_mod}, 
                                        {protocol, udp}, {port, 8089}, {tags, [{region, ru}]}]}
        ]}],
    error_logger:tty(false),
    application:set_env(lager, handlers, [{lager_console_backend, none}]),
    application:set_env(exometer_core, report, Subscribers),
    {ok, Apps} = application:ensure_all_started(exometer_influxdb),

    exometer:update_or_create([metric, test], 1, histogram, []),
    exometer:update_or_create([metric, test1], 2, histogram, []),

    timer:sleep(100),
    ?assertEqual(5, length(exometer_report:list_subscriptions(exometer_report_influxdb))),

    Retries = [{Name ++ [DP], Retry} || {subscriber, {_, _, Name, DP, Retry, _}, _, _} <- ets:tab2list(?EXOMETER_SUBS)],
    ?assertEqual(true, proplists:get_value([metric, test, median], Retries)),
    ?assertEqual(false, proplists:get_value([metric, test1, max], Retries)),

    [application:stop(App) || App <- Apps],
    gen_udp:close(Socket),
    ok.

send_udp_packet_when_it_hits_size_limit_test() ->
    TestServerPort = 55555,
    {ok, ServerSocket} = gen_udp:open(TestServerPort, [{active, false}]),
    {ok, ClientSocket} = gen_udp:open(0),
    State1 = #state{protocol = udp,
                    connection = ClientSocket,
                    host = "localhost",
                    port = TestServerPort,
                    batch_window_size = 99999,
                    max_udp_size = 70,
                    precision = s,
                    timestamping = false},
    {ok, State2} = maybe_send(flights, [{type, departure}], #{count => 3}, State1), % fits into packet - send
    {ok, State3} = maybe_send(flights, [{type, arrival}],   #{count => 2}, State2), % fits into packet - send
    {ok, State4} = maybe_send(flights, [{type, arrival}],   #{count => 1}, State3), % doesn't fit - save for later
    {ok, State5} = maybe_send(flights, [{type, arrival}],   #{count => 1}, State4), % doesn't fit - save for later
    {ok, {_Address, _Port, Packet1}} = gen_udp:recv(ServerSocket, 0, 9999),

    ?assertEqual("flights,type=departure count=3i \n"
                 "flights,type=arrival count=2i \n", Packet1),

    ?assertEqual(<<"flights,type=arrival count=1i \n"
                   "flights,type=arrival count=1i \n">>, State5#state.collected_metrics),

    % Send the remaining metrics when the current batch window ends
    {ok, State6} = exometer_info({exometer_influxdb, send}, State5),
    {ok, {_Address1, _Port1, Packet2}} = gen_udp:recv(ServerSocket, 0, 9999),

    ?assertEqual("flights,type=arrival count=1i \n"
                 "flights,type=arrival count=1i \n", Packet2),

    ?assertEqual(<<>>, State6#state.collected_metrics).

name_test() ->
    ?assertEqual(<<"things">>,   name(things)),
    ?assertEqual(<<"things">>,   name(<<"things">>)),
    ?assertEqual(<<"foo_bar">>,  name([foo, bar])),
    ?assertEqual(<<"97_98_99">>, name("abc")).

make_bin_packet(Name, Tags, Fields, Timestamping, Precision) ->
    binary:list_to_bin(make_packet(Name, Tags, Fields, Timestamping, Precision)).
