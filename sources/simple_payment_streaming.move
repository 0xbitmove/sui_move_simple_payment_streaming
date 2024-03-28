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
   const Second: u64 = 1000; // Constant representing 1 second in milliseconds

   //==============================================================================================
   //                                  Error codes 
   //==============================================================================================
   const ESenderCannotBeReceiver: u64 = 0; // Error code for when the sender and receiver are the same address
   const EPaymentMustBeGreaterThanZero: u64 = 1; // Error code for when the payment amount is zero
   const EDurationMustBeGreaterThanZero: u64 = 2; // Error code for when the stream duration is zero
   const EPassTimeMustBeGreaterThanZero: u64 = 3; // Error code for when the time since the last claim is zero

   //==============================================================================================
   //                                  Module structs 
   //==============================================================================================
   /* 
       A stream is a payment where the receiver can claim the payment over time. The stream has the 
       following properties:
           - id: The unique ID of the stream.
           - sender: The address of the sender who created the stream.
           - duration_in_seconds: The duration of the stream in seconds.
           - last_timestamp_claimed_seconds: The timestamp (in seconds) of the last claim made on the stream.
           - amount: The remaining balance of the stream.
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
           - stream_id: The ID of the created stream.
           - sender: The address of the sender who created the stream.
           - receiver: The address of the receiver who can claim the stream.
           - duration_in_seconds: The duration of the stream in seconds.
           - amount: The initial amount of the stream.
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
           - stream_id: The ID of the claimed stream.
           - receiver: The address of the receiver who claimed the stream.
           - amount: The amount claimed from the stream.
   */
   struct StreamClaimedEvent has copy, drop {
       stream_id: ID, 
       receiver: address, 
       amount: u64
   }

   /* 
       Event emitted when a stream is closed. 
           - stream_id: The ID of the closed stream.
           - receiver: The address of the receiver who closed the stream.
           - sender: The address of the sender who created the stream.
           - amount_to_receiver: The final amount claimed by the receiver.
           - amount_to_sender: The remaining amount returned to the sender.
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
       Creates a new stream from the sender and sends it to the receiver. Aborts if the sender is 
       the same as the receiver, if the payment amount is zero, or if the duration is zero. 
       @type-param PaymentCoin: The type of coin used for the payment.
       @param receiver: The address of the receiver who can claim the stream.
       @param payment: The payment coin to be streamed.
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
       let sender = tx_context::sender(ctx); // Get the address of the sender
       let payment_value = coin::value(&payment); // Get the value of the payment coin
       let payment_balance = coin::into_balance(payment); // Convert the payment coin to a balance

       assert!(sender != receiver, ESenderCannotBeReceiver); // Abort if the sender and receiver are the same
       assert!(payment_value > 0, EPaymentMustBeGreaterThanZero); // Abort if the payment amount is zero
       assert!(duration_in_seconds > 0, EDurationMustBeGreaterThanZero); // Abort if the duration is zero

       let current_time_seconds = clock::timestamp_ms(clock) / Second; // Get the current timestamp in seconds

       let stream_uid = object::new(ctx); // Create a new object ID for the stream
       let stream_id = object::uid_to_inner(&stream_uid); // Get the inner ID of the stream

       let stream = Stream<PaymentCoin> {
           id: stream_uid,
           sender: sender,
           duration_in_seconds: duration_in_seconds,
           last_timestamp_claimed_seconds: current_time_seconds, // Set the last claimed timestamp to the current time
           amount: payment_balance,
       };

       transfer::transfer(stream, receiver); // Transfer the stream object to the receiver

       event::emit( // Emit a StreamCreatedEvent
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
       @type-param PaymentCoin: The type of coin used for the payment.
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
       
       let current_time_seconds = clock::timestamp_ms(clock) / Second; // Get the current timestamp in seconds

       let pass_time_seconds = current_time_seconds - stream.last_timestamp_claimed_seconds; // Calculate the time since the last claim
       assert!(pass_time_seconds > 0, EPassTimeMustBeGreaterThanZero); // Abort if the time since the last claim is zero

       let stream_amount_value = balance::value(&stream.amount); // Get the value of the remaining stream balance

       let claim_amount = stream_amount_value; // Initialize the claim amount to the full remaining balance
       let is_active = false; // Initialize the stream as inactive

       if (pass_time_seconds < stream.duration_in_seconds) { // If the stream is still active
           claim_amount = stream_amount_value * pass_time_seconds / stream.duration_in_seconds; // Calculate the claim amount based on the time since the last claim

           stream.duration_in_seconds = stream.duration_in_seconds - pass_time_seconds; // Reduce the remaining stream duration
           stream.last_timestamp_claimed_seconds = stream.last_timestamp_claimed_seconds + pass_time_seconds; // Update the last claimed timestamp
           is_active = true; // Set the stream as active
       };

       let claim_amount_balance = balance::split(&mut stream.amount, claim_amount); // Split the claim amount from the stream balance
       let claim_amount_coin= coin::from_balance(claim_amount_balance, ctx); // Convert the claim amount balance to a coin

       let sender = tx_context::sender(ctx); // Get the address of the receiver (the sender of this transaction)

       event::emit( // Emit a StreamClaimedEvent
           StreamClaimedEvent {
               stream_id: object::uid_to_inner(&stream.id),
               receiver: sender,
               amount: claim_amount
           }
       );

       if (is_active) { // If the stream is still active
           transfer::transfer(stream, sender); // Transfer the updated stream back to the receiver
       } else { // If the stream is closed
           let Stream {
               id: stream_uid, 
               sender:_, 
               duration_in_seconds:_, 
               last_timestamp_claimed_seconds:_, 
               amount:stream_balance} // Destructure the remaining stream balance
           = stream;

           object::delete(stream_uid); // Delete the stream object
           balance::destroy_zero(stream_balance); // Destroy the remaining balance if it's zero
       };

       claim_amount_coin // Return the claimed coin
   }

   /* 
       Closes the stream. If the stream is still active, the amount claimed is calculated based on 
       the time since the last claim. If the stream is closed, the remaining amount is claimed. The
       claimed amount is sent to the receiver. The remaining amount is sent to the sender of the 
       stream.
       @type-param PaymentCoin: The type of coin used for the payment.
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
       
       let current_time_seconds = clock::timestamp_ms(clock) / Second; // Get the current timestamp in seconds

       let pass_time_seconds = current_time_seconds - stream.last_timestamp_claimed_seconds; // Calculate the time since the last claim
       assert!(pass_time_seconds > 0, EPassTimeMustBeGreaterThanZero); // Abort if the time since the last claim is zero

       let stream_amount_value = balance::value(&stream.amount); // Get the value of the remaining stream balance

       let claim_amount = stream_amount_value; // Initialize the claim amount to the full remaining balance
       let is_active = false; // Initialize the stream as inactive

       if (pass_time_seconds < stream.duration_in_seconds) { // If the stream is still active
           claim_amount = stream_amount_value * pass_time_seconds / stream.duration_in_seconds; // Calculate the claim amount based on the time since the last claim

           stream.duration_in_seconds = stream.duration_in_seconds - pass_time_seconds; // Reduce the remaining stream duration
           stream.last_timestamp_claimed_seconds = stream.last_timestamp_claimed_seconds + pass_time_seconds; // Update the last claimed timestamp
           is_active = true; // Set the stream as active
       };

       let claim_amount_balance = balance::split(&mut stream.amount, claim_amount); // Split the claim amount from the stream balance
       let claim_amount_coin= coin::from_balance(claim_amount_balance, ctx); // Convert the claim amount balance to a coin

       let sender = tx_context::sender(ctx); // Get the address of the receiver (the sender of this transaction)

       if (is_active) { // If the stream is still active
           let stream_left_value= balance::value(&stream.amount); // Get the value of the remaining stream balance
           let stream_left_coin = coin::take(&mut stream.amount, stream_left_value, ctx); // Convert the remaining stream balance to a coin
           transfer::public_transfer(stream_left_coin, stream.sender); // Transfer the remaining coin back to the original sender
       }; 

       event::emit( // Emit a StreamClosedEvent
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
           amount:stream_balance} // Destructure the remaining stream balance
       = stream;

       object::delete(stream_uid); // Delete the stream object
       balance::destroy_zero(stream_balance); // Destroy the remaining balance if it's zero

       claim_amount_coin // Return the claimed coin
   }

   // Getter functions for the Stream struct fields
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