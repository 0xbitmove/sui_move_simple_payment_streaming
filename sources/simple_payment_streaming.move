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

    //==============================================================================================
    //                                  Module structs 
    //==============================================================================================
    /* 
        A stream is a payment where the receiver can claim the payment over time. The stream has the 
        following properties:
            - id: The unique id of the stream.
            - sender: The address of the sender.
            - duration_in_seconds: The duration of the stream in seconds.
            - last_timestamp_claimed_seconds: The timestamp of the last claim.
            - amount: The amount of the stream.
    */
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

    /* 
        Event emitted when a stream is created. 
            - stream_id: The id of the stream.
            - sender: The address of the sender.
            - receiver: The address of the receiver.
            - duration_in_seconds: The duration of the stream in seconds.
            - amount: The amount of the stream.
    */
    struct StreamCreatedEvent has copy, drop {
        stream_id: ID, 
        sender: address, 
        receiver: address, 
        duration_in_seconds: u64, 
        amount: u64
    }

    /* 
        Event emitted when a stream is claimed. 
            - stream_id: The id of the stream.
            - receiver: The address of the receiver.
            - amount: The amount claimed.
    */
    struct StreamClaimedEvent has copy, drop {
        stream_id: ID, 
        receiver: address, 
        amount: u64
    }

    /* 
        Event emitted when a stream is closed. 
            - stream_id: The id of the stream.
            - receiver: The address of the receiver.
            - sender: The address of the sender.
            - amount_to_receiver: The amount claimed by the receiver.
            - amount_to_sender: The amount claimed by the sender.
    */
    struct StreamClosedEvent has copy, drop {
        stream_id: ID, 
        receiver: address, 
        sender: address, 
        amount_to_receiver: u64,
        amount_to_sender: u64
    }

    //==============================================================================================
    //                                      Functions
    //==============================================================================================

    /* 
        Creates a new stream from the sender and sends it to the receiver. Abort if the sender is 
        the same as the receiver, if the payment is zero, or if the duration is zero. 
        @type-param PaymentCoin: The type of coin to use for the payment.
        @param receiver: The address of the receiver.
        @param payment: The payment to be streamed.
        @param duration_in_seconds: The duration of the stream in seconds.
        @param clock: The clock to use for the stream.
        @param ctx: The transaction context.
    */
	public fun create_stream<PaymentCoin>(
        receiver: address, 
        payment: Coin<PaymentCoin>,
        duration_in_seconds: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let payment_value = coin::value(&payment);
        let payment_balance = coin::into_balance(payment);

        assert!(sender != receiver, ESenderCannotBeReceiver);
        assert!(payment_value > 0, EPaymentMustBeGreaterThanZero);
        assert!(duration_in_seconds > 0, EDurationMustBeGreaterThanZero);

        let current_time_seconds = clock::timestamp_ms(clock) / Second;

        let stream_uid = object::new(ctx);
        let stream_id = object::uid_to_inner(&stream_uid);

        let stream = Stream<PaymentCoin> {
            id: stream_uid,
            sender: sender,
            duration_in_seconds: duration_in_seconds,
            last_timestamp_claimed_seconds: current_time_seconds,
            amount: payment_balance,
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

    /* 
        Claims the stream. If the stream is still active, the amount claimed is calculated based on 
        the time since the last claim. If the stream is closed, the remaining amount is claimed. The
        claimed amount is sent to the receiver.  
        @type-param PaymentCoin: The type of coin to use for the payment.
        @param stream: The stream to claim.
        @param clock: The clock to use for the stream.
        @param ctx: The transaction context.
        @return: The coin claimed.
    */
    public fun claim_stream<PaymentCoin>(
        stream: Stream<PaymentCoin>, 
        clock: &Clock, 
        ctx: &mut TxContext
    ): Coin<PaymentCoin> {
        
        let current_time_seconds = clock::timestamp_ms(clock) / Second;

        let pass_time_seconds = current_time_seconds - stream.last_timestamp_claimed_seconds;
        assert!(pass_time_seconds > 0, EPassTimeMustBeGreaterThanZero);

        let stream_amount_value = balance::value(&stream.amount);

        let claim_amount = stream_amount_value; 
        let is_active = false;

        if (pass_time_seconds < stream.duration_in_seconds) {
            claim_amount = stream_amount_value * pass_time_seconds / stream.duration_in_seconds;

            stream.duration_in_seconds = stream.duration_in_seconds - pass_time_seconds;
            stream.last_timestamp_claimed_seconds = stream.last_timestamp_claimed_seconds + pass_time_seconds;
            is_active = true;
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

        if (is_active) {
            transfer::transfer(stream, sender);
        } else {
            let Stream {
                id: stream_uid, 
                sender:_, 
                duration_in_seconds:_, 
                last_timestamp_claimed_seconds:_, 
                amount:stream_balance} 
            = stream;

            object::delete(stream_uid);

            balance::destroy_zero(stream_balance);
        };

        claim_amount_coin
    }

    /* 
        Closes the stream. If the stream is still active, the amount claimed is calculated based on 
        the time since the last claim. If the stream is closed, the remaining amount is claimed. The
        claimed amount is sent to the receiver. The remaining amount is sent to the sender of the 
        stream.
        @type-param PaymentCoin: The type of coin to use for the payment.
        @param stream: The stream to close.
        @param clock: The clock to use for the stream.
        @param ctx: The transaction context.
        @return: The coin claimed.
    */
    public fun close_stream<PaymentCoin>(
        stream: Stream<PaymentCoin>,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<PaymentCoin> {
        
        let current_time_seconds = clock::timestamp_ms(clock) / Second;

        let pass_time_seconds = current_time_seconds - stream.last_timestamp_claimed_seconds;
        assert!(pass_time_seconds > 0, EPassTimeMustBeGreaterThanZero);

        let stream_amount_value = balance::value(&stream.amount);

        let claim_amount = stream_amount_value; 
        let is_active = false;

        if (pass_time_seconds < stream.duration_in_seconds) {
            claim_amount = stream_amount_value * pass_time_seconds / stream.duration_in_seconds;

            stream.duration_in_seconds = stream.duration_in_seconds - pass_time_seconds;
            stream.last_timestamp_claimed_seconds = stream.last_timestamp_claimed_seconds + pass_time_seconds;
            is_active = true;
        };

        let claim_amount_balance = balance::split(&mut stream.amount, claim_amount);
        let claim_amount_coin= coin::from_balance(claim_amount_balance, ctx);

        let sender = tx_context::sender(ctx);

        if (is_active) {
            let stream_left_value= balance::value(&stream.amount);
            let stream_left_coin = coin::take(&mut stream.amount, stream_left_value, ctx);
            transfer::public_transfer(stream_left_coin, stream.sender);
        }; 

        event::emit(
            StreamClosedEvent {
                stream_id: object::uid_to_inner(&stream.id),
                receiver: sender,
                sender: stream.sender,
                amount_to_receiver: claim_amount,
                amount_to_sender: stream_amount_value - claim_amount
            }
        );

        let Stream {
            id: stream_uid, 
            sender:_, 
            duration_in_seconds:_, 
            last_timestamp_claimed_seconds:_, 
            amount:stream_balance} 
        = stream;

        object::delete(stream_uid);

        balance::destroy_zero(stream_balance);

        claim_amount_coin
    }

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