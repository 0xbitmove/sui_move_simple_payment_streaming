module bitmove::simple_payment_streaming_tests {
    //==============================================================================================
    //                                      Dependencies
    //==============================================================================================
    use std::vector;
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::balance;

    use bitmove::simple_payment_streaming::{ESenderCannotBeReceiver, Stream, create_stream, claim_stream, close_stream, 
        get_stream_sender, get_stream_duration_in_seconds, get_stream_amount, 
        get_stream_last_timestamp_claimed_seconds};

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use sui::test_utils::assert_eq;

    //==============================================================================================
    //                                      Tests
    //==============================================================================================
    #[test]
    fun test_create_stream_success() {
        let stream_creator = @0xa;
        let stream_receiver = @0xb;

        let scenario_val = test_scenario::begin(stream_creator);
        let scenario = &mut scenario_val;

        {
            clock::share_for_testing(clock::create_for_testing(test_scenario::ctx(scenario)));
        };

        test_scenario::next_tx(scenario, stream_creator);

        let stream_amount = 1_000_000_000;
        let stream_duration_in_seconds = 1_000; // 1000s

        {
            let payment_coin = coin::mint_for_testing<SUI>(stream_amount, 
                test_scenario::ctx(scenario));

            let clock = test_scenario::take_shared<Clock>(scenario);

            create_stream<SUI>(
                stream_receiver,
                payment_coin,
                stream_duration_in_seconds,
                &clock,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(clock);
        };

        let tx = test_scenario::next_tx(scenario, stream_creator);

        let expected_events_emitted = 1;
        let expected_created_objects = 1;
        assert_eq(
            test_scenario::num_user_events(&tx), 
            expected_events_emitted
        );
        assert_eq(
            vector::length(&test_scenario::created(&tx)),
            expected_created_objects
        );

        {
            let stream = test_scenario::take_from_address<Stream<SUI>>(
                scenario, stream_receiver);

            assert_eq(
                get_stream_sender(&stream), 
                stream_creator
            );

            assert_eq(
                get_stream_duration_in_seconds(&stream), 
                stream_duration_in_seconds
            );

            assert_eq(
                balance::value(get_stream_amount(&stream)), 
                stream_amount
            );

            test_scenario::return_to_address(stream_receiver, stream);
        };

        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = ESenderCannotBeReceiver)]
    fun test_create_stream_failure_sender_is_receiver() {
        let stream_creator = @0xa;
        let stream_receiver = stream_creator;

        let scenario_val = test_scenario::begin(stream_creator);
        let scenario = &mut scenario_val;
        {
            clock::share_for_testing(clock::create_for_testing(test_scenario::ctx(scenario)));
        };
        test_scenario::next_tx(scenario, stream_creator);

        let stream_amount = 1_000_000_000;
        let stream_duration_in_seconds = 1_000;
        {
            let payment_coin = coin::mint_for_testing<SUI>(stream_amount, test_scenario::ctx(scenario));
            let clock = test_scenario::take_shared<Clock>(scenario);

            create_stream<SUI>(
                stream_receiver, 
                payment_coin, 
                stream_duration_in_seconds, 
                &clock, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(clock);
        };
        let tx = test_scenario::next_tx(scenario, stream_creator);
        let expected_events_emitted = 1;
        let expected_created_objects = 1;
        assert_eq(
            test_scenario::num_user_events(&tx), 
            expected_events_emitted
        );
        assert_eq(
            vector::length(&test_scenario::created(&tx)),
            expected_created_objects
        );

        {
            let stream = test_scenario::take_from_address<Stream<SUI>>(scenario, stream_receiver);

            assert_eq(
                get_stream_sender(&stream), 
                stream_creator
            );
            assert_eq(
                get_stream_duration_in_seconds(&stream), 
                stream_duration_in_seconds
            );
            assert_eq(
                balance::value(get_stream_amount(&stream)), 
                stream_amount
            );

            test_scenario::return_to_address(stream_receiver, stream);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_claim_stream_success_claim_10_percent() {
        let stream_creator = @0xa;
        let stream_receiver = @0xb;

        let scenario_val = test_scenario::begin(stream_creator);
        let scenario = &mut scenario_val;
        {
            clock::share_for_testing(clock::create_for_testing(test_scenario::ctx(scenario)));
        };
        test_scenario::next_tx(scenario, stream_creator);

        let stream_amount = 1_000_000_000;
        let stream_duration_in_seconds = 1_000;
        {
            let payment_coin = coin::mint_for_testing<SUI>(stream_amount, test_scenario::ctx(scenario));
            let clock = test_scenario::take_shared<Clock>(scenario);

            create_stream<SUI>(
                stream_receiver, 
                payment_coin, 
                stream_duration_in_seconds, 
                &clock, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(clock);
        };
        test_scenario::next_tx(scenario, stream_receiver);

        let time_forward_seconds = stream_duration_in_seconds / 10;
        let expected_claim_amount = stream_amount / 10;
        {
            let stream = test_scenario::take_from_address<Stream<SUI>>(scenario, stream_receiver);
            let clock = test_scenario::take_shared<Clock>(scenario);
            clock::increment_for_testing(&mut clock, time_forward_seconds * 1000);

            let claimed_coin = claim_stream<SUI>(
                stream, 
                &clock, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(clock);

            assert_eq(
                coin::value(&claimed_coin), 
                expected_claim_amount
            );
            coin::burn_for_testing(claimed_coin);
        };
        let tx = test_scenario::next_tx(scenario, stream_receiver);
        let expected_events_emitted = 1;
        let expected_created_objects = 0;
        let expected_deleted_objects = 0;
        assert_eq(
            test_scenario::num_user_events(&tx), 
            expected_events_emitted
        );
        assert_eq(
            vector::length(&test_scenario::created(&tx)),
            expected_created_objects
        );
        assert_eq(
            vector::length(&test_scenario::deleted(&tx)),
            expected_deleted_objects
        );

        {
            let stream = test_scenario::take_from_address<Stream<SUI>>(scenario, stream_receiver);

            assert_eq(
                balance::value(get_stream_amount(&stream)), 
                stream_amount - expected_claim_amount
            );
            assert_eq(
                get_stream_last_timestamp_claimed_seconds(&stream), 
                time_forward_seconds
            );
            assert_eq(
                get_stream_duration_in_seconds(&stream), 
                stream_duration_in_seconds - time_forward_seconds
            );
            assert_eq(
                get_stream_sender(&stream), 
                stream_creator
            );

            test_scenario::return_to_address(stream_receiver, stream);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_close_stream_success_close_25_percent_after_50_claimed() {
        let stream_creator = @0xa;
        let stream_receiver = @0xb;

        let scenario_val = test_scenario::begin(stream_creator);
        let scenario = &mut scenario_val;
        {
            clock::share_for_testing(clock::create_for_testing(test_scenario::ctx(scenario)));
        };
        test_scenario::next_tx(scenario, stream_creator);

        let stream_amount = 1_000_000_000;
        let stream_duration_in_seconds = 1_000;
        {
            let payment_coin = coin::mint_for_testing<SUI>(stream_amount, 
                test_scenario::ctx(scenario));
            let clock = test_scenario::take_shared<Clock>(scenario);

            create_stream<SUI>(
                stream_receiver, 
                payment_coin, 
                stream_duration_in_seconds, 
                &clock, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(clock);
        };
        test_scenario::next_tx(scenario, stream_receiver);

        let time_forward_seconds_1 = stream_duration_in_seconds / 2;
        let expected_claim_amount_1 = stream_amount / 2;
        {
            let stream = test_scenario::take_from_address<Stream<SUI>>(scenario, stream_receiver);
            let clock = test_scenario::take_shared<Clock>(scenario);
            clock::increment_for_testing(&mut clock, time_forward_seconds_1 * 1000);

            let claimed_coin = claim_stream<SUI>(
                stream, 
                &clock, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(clock);

            assert_eq(
                coin::value(&claimed_coin), 
                expected_claim_amount_1
            );
            coin::burn_for_testing(claimed_coin);
        };
        let tx = test_scenario::next_tx(scenario, stream_receiver);
        let expected_events_emitted = 1;
        let expected_created_objects = 0;
        let expected_deleted_objects = 0;
        assert_eq(
            test_scenario::num_user_events(&tx), 
            expected_events_emitted
        );
        assert_eq(
            vector::length(&test_scenario::created(&tx)),
            expected_created_objects
        );
        assert_eq(
            vector::length(&test_scenario::deleted(&tx)),
            expected_deleted_objects
        );

        {
            let stream = test_scenario::take_from_address<Stream<SUI>>(scenario, stream_receiver);

            assert_eq(
                balance::value(get_stream_amount(&stream)), 
                stream_amount - expected_claim_amount_1
            );
            assert_eq(
                get_stream_last_timestamp_claimed_seconds(&stream),
                time_forward_seconds_1
            );
            assert_eq(
                get_stream_duration_in_seconds(&stream), 
                stream_duration_in_seconds - time_forward_seconds_1
            );
            assert_eq(
                get_stream_sender(&stream), 
                stream_creator
            );

            test_scenario::return_to_address(stream_receiver, stream);
        };
        test_scenario::next_tx(scenario, stream_receiver);

        let time_forward_seconds_2 = stream_duration_in_seconds / 4;
        let expected_amount_to_sender = stream_amount / 4;
        let expected_amount_to_receiver = stream_amount / 4;
        {
            let stream = test_scenario::take_from_address<Stream<SUI>>(scenario, stream_receiver);
            let clock = test_scenario::take_shared<Clock>(scenario);
            clock::increment_for_testing(&mut clock, time_forward_seconds_2 * 1000);

            let claimed_coin = close_stream<SUI>(
                stream, 
                &clock, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(clock);

            assert_eq(
                coin::value(&claimed_coin), 
                expected_amount_to_receiver
            );
            coin::burn_for_testing(claimed_coin);
        };
        let tx = test_scenario::next_tx(scenario, stream_creator);
        let expected_events_emitted = 1;
        let expected_created_objects = 1;
        let expected_deleted_objects = 1;
        assert_eq(
            test_scenario::num_user_events(&tx), 
            expected_events_emitted
        );
        assert_eq(
            vector::length(&test_scenario::created(&tx)),
            expected_created_objects
        );
        assert_eq(
            vector::length(&test_scenario::deleted(&tx)),
            expected_deleted_objects
        );

        {
            let coin = test_scenario::take_from_address<Coin<SUI>>(scenario, stream_creator);

            assert_eq(
                coin::value(&coin), 
                expected_amount_to_sender
            );

            test_scenario::return_to_address(stream_creator, coin);
        };
        test_scenario::end(scenario_val);        
    }
}