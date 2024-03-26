module bitmove::simple_payment_streaming {
    //==============================================================================================
    //                                  Dependencies
    //==============================================================================================
    use sui::event;
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::object::{Self, UID, ID};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
    use sui::error::{SuiError, SErr};

    //==============================================================================================
    //                                  Constants 
    //==============================================================================================
    const Second: u64 = 1000;
    
    //==============================================================================================
    //                                  Error codes 
    //==============================================================================================
    const ESenderCannotBeReceiver: u64 = 0;
    const EPaymentMustBeGreaterThanZero: u64 = 1;
    const EDurationMustBeGreaterThanZero: u64 = 2;
    const EPassTimeMustBeGreaterThanZero: u64 = 3;
    const EUnauthorizedClaim: u64 = 4;

    //==============================================================================================
    //                                  Module structs 
    //==============================================================================================
    struct Stream<phantom PaymentCoin> has key {
        id: UID, 
        sender: address, 
        duration_in_seconds: u64,
        last_timestamp_claimed_seconds: u64,
        amount: Balance<PaymentCoin>,
    }

    //==============================================================================================
    //                                  Event structs 
    //==============================================================================================
    struct StreamCreatedEvent has copy, drop {
        stream_id: ID, 
        sender: address, 
        receiver: address, 
        duration_in_seconds: u64, 
        amount: u64
    }

    struct StreamClaimedEvent has copy, drop {
        stream_id: ID, 
        receiver: address, 
        amount: u64
    }

    struct StreamClosedEvent has copy, drop {
        stream_id: ID, 
        receiver: address, 
        sender: address, 
        amount_to_receiver: u64,
        amount_to_sender: u64
    }

    //==============================================================================================
    //                                  Functions
    //==============================================================================================

    // Check if the sender is authorized to claim the stream
    public fun authorized_to_claim<PaymentCoin>(
        stream: &Stream<PaymentCoin>,
        claimer: address
    ): bool {
        stream.sender == claimer
    }

    public fun create_stream<PaymentCoin>(
        receiver: address, 
        payment: Coin<PaymentCoin>,
        duration_in_seconds: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let payment_value = coin::value(&payment);

        assert!(
            sender != receiver,
            SuiError::malformed_argument(SErr::InvalidOwner)
        );
        assert!(
            payment_value > 0,
            SuiError::malformed_argument(SErr::InvalidPayment)
        );
        assert!(
            duration_in_seconds > 0,
            SuiError::malformed_argument(SErr::InvalidDuration)
        );

        let current_time_seconds = clock::timestamp_ms(clock) / Second;

        let stream_uid = object::new(ctx);
        let stream_id = object::uid_to_inner(&stream_uid);

        let stream = Stream<PaymentCoin> {
            id: stream_uid,
            sender: sender,
            duration_in_seconds: duration_in_seconds,
            last_timestamp_claimed_seconds: current_time_seconds,
            amount: balance::into_balance(payment),
        };

        transfer::transfer(stream, receiver);

        event::emit(
            StreamCreatedEvent {
                stream_id: stream_id,
                sender: sender,
                receiver: receiver,
                duration_in_seconds: duration_in_seconds,
                amount: payment_value
            }
        );
    }

    public fun claim_stream<PaymentCoin>(
        stream: Stream<PaymentCoin>, 
        clock: &Clock, 
        ctx: &mut TxContext
    ): Coin<PaymentCoin> {
        
        let current_time_seconds = clock::timestamp_ms(clock) / Second;

        let pass_time_seconds = current_time_seconds - stream.last_timestamp_claimed_seconds;
        assert!(pass_time_seconds > 0, EPassTimeMustBeGreaterThanZero);

        let stream_amount_value = balance::value(&stream.amount);

        assert!(
            authorized_to_claim(&stream, tx_context::sender(ctx)),
            SuiError::access_denied(EUnauthorizedClaim)
        );

        let claim_amount = if pass_time_seconds < stream.duration_in_seconds {
            stream_amount_value * pass_time_seconds / stream.duration_in_seconds
        } else {
            stream_amount_value
        };

        let claim_amount_balance = balance::split(&mut stream.amount, claim_amount);
        let claim_amount_coin= coin::from_balance(claim_amount_balance, ctx);

        let sender = tx_context::sender(ctx);

        event::emit(
            StreamClaimedEvent {
                stream_id: object::uid_to_inner(&stream.id),
                receiver: sender,
                amount: claim_amount
            }
        );

        if claim_amount == stream_amount_value {
            object::delete(stream.id);
        } else {
            transfer::transfer(stream, sender);
        }

        claim_amount_coin
    }

    public fun close_stream<PaymentCoin>(
        stream: Stream<PaymentCoin>,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<PaymentCoin> {
        
        let current_time_seconds = clock::timestamp_ms(clock) / Second;

        let pass_time_seconds = current_time_seconds - stream.last_timestamp_claimed_seconds;
        assert!(pass_time_seconds > 0, EPassTimeMustBeGreaterThanZero);

        let stream_amount_value = balance::value(&stream.amount);

        let claim_amount = if pass_time_seconds < stream.duration_in_seconds {
            stream_amount_value * pass_time_seconds / stream.duration_in_seconds
        } else {
            stream_amount_value
        };

        let claim_amount_balance = balance::split(&mut stream.amount, claim_amount);
        let claim_amount_coin= coin::from_balance(claim_amount_balance, ctx);

        let sender = tx_context::sender(ctx);

        if claim_amount == stream_amount_value {
            object::delete(stream.id);
        } else {
            transfer::transfer(stream, sender);
        }

        event::emit(
            StreamClosedEvent {
                stream_id: object::uid_to_inner(&stream.id),
                receiver: sender,
                sender: stream.sender,
                amount_to_receiver: claim_amount,
                amount_to_sender: stream_amount_value - claim_amount
            }
        );

        claim_amount_coin
    }

    // Getters
    public fun get_stream_sender<PaymentCoin>(stream: &Stream<PaymentCoin>): address {
        stream.sender
    }

    public fun get_stream_duration_in_seconds<PaymentCoin>(stream: &Stream<PaymentCoin>): u64 {
        stream.duration_in_seconds
    }

    public fun get_stream_last_timestamp_claimed_seconds<PaymentCoin>(stream: &Stream<PaymentCoin>): u64 {
        stream.last_timestamp_claimed_seconds
    }

    public fun get_stream_amount<PaymentCoin>(stream: &Stream<PaymentCoin>): &Balance<PaymentCoin> {
        &stream.amount
    }

    public fun get_stream_amount_value<PaymentCoin>(stream: &Stream<PaymentCoin>): u64 {
        let balance = &stream.amount;
        balance::value(balance)
    }
}
``
