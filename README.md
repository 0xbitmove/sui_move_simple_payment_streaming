# sui move simple payment streaming module

The simple payment streaming module allows a sender to create a stream to a receiver. A stream is a payment that is sent to the receiver that the receiver can claim over time. Instead of receiving the full payment at once or being restricted to fixed installments, the receiver can claim the pending payments at any time. The sender can close the stream at any time, which will send the claimed amount to the receiver and the unclaimed amount to the sender.

## FUNCTION

### create_stream: Creating a stream

Anyone can create a stream to anyone else with any coin. The sender specifies the receiver, the payment, and the duration of the stream. The duration is specified in seconds. The receiver can start claiming the stream immediately after it is created. 

### claim_stream: Claiming a stream

The receiver can claim the stream at any time. The amount claimed is calculated based on the time since the last claim. If the stream duration has passed, the receiver will receive the full amount and the stream will be closed (deleted).

### close_stream: Closing a stream

The receiver can close the stream at any time. The amount to send to the receiver and the amount of to send back to the sender is calculated based on the time since the last claim.  If the stream duration has passed, the receiver will receive the full amount and the sender will receive nothing. When a stream is closed, it should be deleted.


## UNITTEST

```bash
sui move test
INCLUDING DEPENDENCY Sui
INCLUDING DEPENDENCY MoveStdlib
BUILDING simple_payment_streaming
Running Move unit tests
[ PASS    ] 0x0::simple_payment_streaming_tests::test_claim_stream_success_claim_10_percent
[ PASS    ] 0x0::simple_payment_streaming_tests::test_close_stream_success_close_25_percent_after_50_claimed
[ PASS    ] 0x0::simple_payment_streaming_tests::test_create_stream_failure_sender_is_receiver
[ PASS    ] 0x0::simple_payment_streaming_tests::test_create_stream_success
Test result: OK. Total tests: 4; passed: 4; failed: 0
```


## DEPLOY

### stream users

stream creator: 0x69872fc4781f115e08f72dd37de1216c431afea4faa4b794e5327da59abce681
stream receiver: 0x5428ab79ddc06a73809077289a05ad7557f14b435283a6100d6ab12af042af56

### publish
```bash
export GAS_BUDGET=100000000
sui client publish --gas-budget $GAS_BUDGET

...
│ Published Objects:                                                                │
│  ┌──                                                                              │
│  │ PackageID: 0xf89714fa8b0ce3e73cdf71d5e4993f6b8900d1f83a192cb088652d0e48aef93c  │
│  │ Version: 1                                                                     │
│  │ Digest: FurPPvdtpPUyHoZ3symC5dsueg955q4gkBk9sLzVpo1d                           │
│  │ Modules: simple_payment_streaming                                              │
│  └──                                                                              │
...

export PACKAGE_ID=0xf89714fa8b0ce3e73cdf71d5e4993f6b8900d1f83a192cb088652d0e48aef93c
```

### create_stream
```bash
export RECEIVER=0x5428ab79ddc06a73809077289a05ad7557f14b435283a6100d6ab12af042af56
export PAYMENT=0x69824c803add0f483fe905a45da0ea6c410c69e74a4cedcf1ed41aba862a7ce5
export DURATION_IN_SECONDS=120
sui client call --function create_stream --package $PACKAGE_ID --module simple_payment_streaming --type-args=0x2::sui::SUI --args $RECEIVER $PAYMENT $DURATION_IN_SECONDS 0x6 --gas-budget $GAS_BUDGET

...
│ Created Objects:                                                                                                                    │
│  ┌──                                                                                                                                │
│  │ ObjectID: 0x62eee5342ac47a9c61d7314abfaa85f7e2094c5caca576a42d0e4d38e18c19c7                                                     │
│  │ Sender: 0x69872fc4781f115e08f72dd37de1216c431afea4faa4b794e5327da59abce681                                                       │
│  │ Owner: Account Address ( 0x5428ab79ddc06a73809077289a05ad7557f14b435283a6100d6ab12af042af56 )                                    │
│  │ ObjectType: 0xf89714fa8b0ce3e73cdf71d5e4993f6b8900d1f83a192cb088652d0e48aef93c::simple_payment_streaming::Stream<0x2::sui::SUI>  │
│  │ Version: 27767295                                                                                                                │
│  │ Digest: E5fmB1u5fMQkV5KEAH4VSpVQF6dHV4F4QXG6fKM4UhhH                                                                             │
│  └──                                                                                                                                │
...

export STREAM=0x62eee5342ac47a9c61d7314abfaa85f7e2094c5caca576a42d0e4d38e18c19c7
```

### claim_stream
```bash
sui client switch --address $RECEIVER
Active address switched to 0x5428ab79ddc06a73809077289a05ad7557f14b435283a6100d6ab12af042af56

sui client call --function claim_stream_to_receiver --package $PACKAGE_ID --module simple_payment_streaming --type-args=0x2::sui::SUI --args $STREAM 0x6 --gas-budget $GAS_BUDGET

│ Created Objects:                                                                                                                    │
│  ┌──                                                                                                                                │
│  │ ObjectID: 0x2a476d66a9aafc9ca1479053ba44fd79b467fbf50e7869a7ef0ed7d0f4ec2db7                                                     │
│  │ Sender: 0x5428ab79ddc06a73809077289a05ad7557f14b435283a6100d6ab12af042af56                                                       │
│  │ Owner: Account Address ( 0x5428ab79ddc06a73809077289a05ad7557f14b435283a6100d6ab12af042af56 )                                    │
│  │ ObjectType: 0x2::coin::Coin<0x2::sui::SUI>                                                                                       │
│  │ Version: 27767358                                                                                                                │
│  │ Digest: 78XPLaJDWguTXVL2GswACXtH93NBVFEqaMYHqFUSeJQ7                                                                             │
│  └──                                                                                                                                │
```

stream receiver claimed amount: **516666**

```json
sui client object 0x2a476d66a9aafc9ca1479053ba44fd79b467fbf50e7869a7ef0ed7d0f4ec2db7 --json
{
  "objectId": "0x2a476d66a9aafc9ca1479053ba44fd79b467fbf50e7869a7ef0ed7d0f4ec2db7",
  "version": "27767358",
  "digest": "78XPLaJDWguTXVL2GswACXtH93NBVFEqaMYHqFUSeJQ7",
  "type": "0x2::coin::Coin<0x2::sui::SUI>",
  "owner": {
    "AddressOwner": "0x5428ab79ddc06a73809077289a05ad7557f14b435283a6100d6ab12af042af56"
  },
  "previousTransaction": "vsBGrrn3PXZw69fbjWhEAzLDERw74qZJTWEBt9taZin",
  "storageRebate": "988000",
  "content": {
    "dataType": "moveObject",
    "type": "0x2::coin::Coin<0x2::sui::SUI>",
    "hasPublicTransfer": true,
    "fields": {
      "balance": "516666",
      "id": {
        "id": "0x2a476d66a9aafc9ca1479053ba44fd79b467fbf50e7869a7ef0ed7d0f4ec2db7"
      }
    }
  }
}
```

### close_stream
```bash
sui client call --function close_stream_to_receiver --package $PACKAGE_ID --module simple_payment_streaming --type-args=0x2::sui::SUI --args $STREAM 0x6 --gas-budget $GAS_BUDGET

...
│ Created Objects:                                                                                 │
│  ┌──                                                                                             │
│  │ ObjectID: 0x00eb0b174a18b66a43793aca1ca271047165738ca87533ae53b60111abfa68ac                  │
│  │ Sender: 0x5428ab79ddc06a73809077289a05ad7557f14b435283a6100d6ab12af042af56                    │
│  │ Owner: Account Address ( 0x5428ab79ddc06a73809077289a05ad7557f14b435283a6100d6ab12af042af56 ) │
│  │ ObjectType: 0x2::coin::Coin<0x2::sui::SUI>                                                    │
│  │ Version: 27767390                                                                             │
│  │ Digest: HqX4Qr4pz9UkJV9qGMAfHyLs9GvsFFBK1vc6UmtKxeTA                                          │
│  └──                                                                                             │
│  ┌──                                                                                             │
│  │ ObjectID: 0xc0cfee9bc35990e2a26b323a1c9c314811304d31ac3b8949de6bdecef828c068                  │
│  │ Sender: 0x5428ab79ddc06a73809077289a05ad7557f14b435283a6100d6ab12af042af56                    │
│  │ Owner: Account Address ( 0x69872fc4781f115e08f72dd37de1216c431afea4faa4b794e5327da59abce681 ) │
│  │ ObjectType: 0x2::coin::Coin<0x2::sui::SUI>                                                    │
│  │ Version: 27767390                                                                             │
│  │ Digest: 3zmPrDvAj7RkmJaXyTzRFvcuPZwrVtMTuvQ7mCZZXPAn                                          │
│  └──                                                                                             │
...
```

stream receiver claimed amount: **266667**
```json
sui client object 0x00eb0b174a18b66a43793aca1ca271047165738ca87533ae53b60111abfa68ac --json
{
  "objectId": "0x00eb0b174a18b66a43793aca1ca271047165738ca87533ae53b60111abfa68ac",
  "version": "27767390",
  "digest": "HqX4Qr4pz9UkJV9qGMAfHyLs9GvsFFBK1vc6UmtKxeTA",
  "type": "0x2::coin::Coin<0x2::sui::SUI>",
  "owner": {
    "AddressOwner": "0x5428ab79ddc06a73809077289a05ad7557f14b435283a6100d6ab12af042af56"
  },
  "previousTransaction": "8GDTCLStCnXNX3PR6m5Zr9Qza3HFg9x1thvRF8oM9fLU",
  "storageRebate": "988000",
  "content": {
    "dataType": "moveObject",
    "type": "0x2::coin::Coin<0x2::sui::SUI>",
    "hasPublicTransfer": true,
    "fields": {
      "balance": "266667",
      "id": {
        "id": "0x00eb0b174a18b66a43793aca1ca271047165738ca87533ae53b60111abfa68ac"
      }
    }
  }
}
```

stream creator got remaining amount: **216667**
```json
sui client object 0xc0cfee9bc35990e2a26b323a1c9c314811304d31ac3b8949de6bdecef828c068 --json
{
  "objectId": "0xc0cfee9bc35990e2a26b323a1c9c314811304d31ac3b8949de6bdecef828c068",
  "version": "27767390",
  "digest": "3zmPrDvAj7RkmJaXyTzRFvcuPZwrVtMTuvQ7mCZZXPAn",
  "type": "0x2::coin::Coin<0x2::sui::SUI>",
  "owner": {
    "AddressOwner": "0x69872fc4781f115e08f72dd37de1216c431afea4faa4b794e5327da59abce681"
  },
  "previousTransaction": "8GDTCLStCnXNX3PR6m5Zr9Qza3HFg9x1thvRF8oM9fLU",
  "storageRebate": "988000",
  "content": {
    "dataType": "moveObject",
    "type": "0x2::coin::Coin<0x2::sui::SUI>",
    "hasPublicTransfer": true,
    "fields": {
      "balance": "216667",
      "id": {
        "id": "0xc0cfee9bc35990e2a26b323a1c9c314811304d31ac3b8949de6bdecef828c068"
      }
    }
  }
}
```