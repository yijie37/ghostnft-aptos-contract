module ghostnft::nft_rental_regular {
    use std::debug;
    // use std::signer;
    use std::string::{Self, String};
    use std::option::{Option};

    use aptos_std::table::{Table};

    // use aptos_framework::account::{create_resource_account};
    // use aptos_framework::account::{SignerCapability, create_resource_account};
    // use std::vector;

    // use aptos_framework::account;
    // use aptos_framework::event::{Self, EventHandle};
    // use aptos_framework::timestamp::{Self};
    // use aptos_std::ed25519;
    // use aptos_token::token::{Self, TokenDataId, TokenId};
    use aptos_token::token::{TokenId};
    // use aptos_framework::resource_account;

    const SECONDS_PER_DAY: u64 = 86400;

    struct Promise has store {
        inital_owner: address,
        rented: bool,
        kept: bool,
        claimed: bool,
        tenant: Option<address>,
        rent_per_day: u64,
        start_time: u64,
        end_time: Option<u64>,
        total_rent: u64,
        rent_token_type: String,
    }

    struct PromiseCollection has store {
        platform_fee_rate: u64,
        min_rent_period: u64,
        claimer_percent: u64,
        app_percent: u64,
        app_wallet_address: address,
        platform_wallet_address: address,

        promises: Table<TokenId, Promise>,
        payments: Table<TokenId, u64>,
        rent_fees: Table<TokenId, u64>,
        user_rented: Table<address, Table<TokenId, u64>>,
    }

    public entry fun init() {
    // public entry fun init(sender: &signer) {
      // let (resource_signer, resource_signer_cap) = create_resource_account(sender, b"resource_signer");
    }

    public fun speak(): string::String {
        string::utf8(b"Hello World")
    }

    #[test]
    public fun test_speak() {
        let res = speak();

        let a: u64 = 33333333;
        let b: u64 = 200;
        let c: u64 = 10000;

        debug::print(& (a * b / c));
        debug::print(&res);

        let except = string::utf8(b"Hello World");
        assert!(res == except, 0);
    }
}