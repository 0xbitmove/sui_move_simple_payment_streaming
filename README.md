# sui move simple payment streaming module

The simple payment streaming module allows a sender to create a stream to a receiver. A stream is a payment that is sent to the receiver that the receiver can claim over time. Instead of receiving the full payment at once or being restricted to fixed installments, the receiver can claim the pending payments at any time. The sender can close the stream at any time, which will send the claimed amount to the receiver and the unclaimed amount to the sender.

## Creating a stream
    Anyone can create a stream to anyone else with any coin. The sender specifies the receiver, the payment, and the duration of the stream. The duration is specified in seconds. The receiver can start claiming the stream immediately after it is created. 

## Claiming a stream
    The receiver can claim the stream at any time. The amount claimed is calculated based on the time since the last claim. If the stream duration has passed, the receiver will receive the full amount and the stream will be closed (deleted).

## Closing a stream
    The receiver can close the stream at any time. The amount to send to the receiver and the amount of to send back to the sender is calculated based on the time since the last claim.  If the stream duration has passed, the receiver will receive the full amount and the sender will receive nothing. When a stream is closed, it should be deleted.