module deployer::nft_rental_regular {
    use std::debug;
    use std::error;
    use std::option::{Self, Option};
    use std::signer::address_of;
    use std::string::{Self, String};
    use std::vector;

    use aptos_std::table::{Self, Table};

    // use aptos_framework::account::{create_resource_account};
    use aptos_framework::account::{SignerCapability, create_resource_account};

    // use aptos_framework::account;
    // use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp::{Self};
    // use aptos_std::ed25519;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_token::token::{Self, TokenId};
    use aptos_token::property_map::PropertyMap;
    // use aptos_framework::resource_account;

    // use ghostnft::gnft_coin_mintable::GnftCoin;

    const SECONDS_PER_DAY: u64 = 86400;

    const FEE_BASE: u64 = 10000;

    const RENT_TOKEN_TYPE_APTOS: u8 = 1;

    const ETOKEN_ALREADY_LISTED: u64 = 1;

    const ETOKEN_NOT_LISTED: u64 = 2;

    const EBAD_TOKEN_TYPE: u64 = 3;

    const EUSER_NOT_OWN_TOKEN: u64 = 4;

    const EBAD_TENANT: u64 = 5;

    const ETOKEN_ALREADY_RENTED: u64 = 6;

    struct Promise has store, drop {
        inital_owner: address,
        rented: bool,
        kept: bool,
        claimed: bool,
        tenant: Option<address>,
        rent_per_day: u64,
        start_time: u64,
        end_time: u64,
        total_rent: u64,
        rent_token_type: u8,
    }

    struct PromiseCollection has key, store {
        signer_cap: SignerCapability,
        // token_resource_address and token_collection_name to determain NFT
        token_creator_address: address,
        token_collection_name: String,

        guarantee: u64,
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
        user_tokens: Table<address, vector<TokenId>>,
        tokens_properties: Table<TokenId, PropertyMap>
    }

    public entry fun init(
        sender: &signer, 
        token_creator_address: address, 
        token_collection_name: String,
        app_wallet_address: address, 
        platform_wallet_address: address
    ) {
        let (_, resource_signer_cap) = create_resource_account(sender, b"regular_rental_signer");

        move_to(sender, PromiseCollection {
            signer_cap: resource_signer_cap,
            token_creator_address,
            token_collection_name,

            guarantee: 10000000000,
            platform_fee_rate: 100,
            min_rent_period: 86400,
            claimer_percent: 40,
            app_percent: 40,
            app_wallet_address,
            platform_wallet_address,

            promises: table::new(),
            payments: table::new(),
            rent_fees: table::new(),
            user_rented: table::new(),
            user_tokens: table::new(),
            tokens_properties: table::new()
        })
    }

    // List one token for renting
    public entry fun make_promise(
        sender: &signer,
        token_name: String,
        property_version: u64,
        rent_per_day: u64,
        rent_token_type: u8 // currently aptos
    ) acquires PromiseCollection {
        let sender_address = address_of(sender);
        let promise_collection = borrow_global_mut<PromiseCollection>(@deployer);
        let token_id: TokenId = get_token_id(promise_collection, token_name, property_version);

        // Token is not listed
        assert!(!table::contains(&promise_collection.promises, token_id), error::not_found(ETOKEN_ALREADY_LISTED));

        // Rent token type is valid
        assert!(rent_token_type == RENT_TOKEN_TYPE_APTOS, error::invalid_argument(EBAD_TOKEN_TYPE));

        // Sender ownes the token
        assert!(token::balance_of(sender_address, token_id) > 0, error::not_found(EUSER_NOT_OWN_TOKEN));

        table::upsert(&mut promise_collection.promises, token_id, Promise{
            inital_owner: sender_address,
            rented: false,
            kept: true,
            claimed: false,
            tenant: option::none(),
            rent_per_day,
            start_time: timestamp::now_seconds(),
            end_time: 0,
            total_rent: 0,
            rent_token_type
        });

        // Guarantee
        coin::transfer<ghostnft::gnft_coin_mintable::GnftCoin>(
            sender, 
            promise_collection.platform_wallet_address, 
            promise_collection.guarantee
        );

        // Insert user_tokens
        let user_tokens = table::borrow_mut(&mut promise_collection.user_tokens, sender_address);
        vector::push_back(user_tokens, token_id);

        // Record tokens properties
        let property_map = token::get_property_map(sender_address, token_id);
        table::upsert(&mut promise_collection.tokens_properties, token_id, property_map);
    }

    // Tenant renting a listed token
    public entry fun fill_promise(
        sender: &signer,
        token_name: String,
        property_version: u64,
        rent_token_type: u8
    ) acquires PromiseCollection {
        let sender_address = address_of(sender);
        let promise_collection = borrow_global_mut<PromiseCollection>(@deployer);
        let token_id: TokenId = get_token_id(promise_collection, token_name, property_version);

        // Rent token type is valid
        assert!(rent_token_type == RENT_TOKEN_TYPE_APTOS, error::invalid_argument(EBAD_TOKEN_TYPE));

        // Token is listed
        assert!(table::contains(&promise_collection.promises, token_id), error::not_found(ETOKEN_NOT_LISTED));

        let promise = table::borrow_mut(&mut promise_collection.promises, token_id);
        // Tenant is none
        assert!(option::is_none(&promise.tenant), error::unavailable(EBAD_TENANT));

        // Token is not rented
        assert!(!promise.rented, error::invalid_state(ETOKEN_ALREADY_RENTED));

        let days: u64 = (promise.end_time - timestamp::now_seconds() + SECONDS_PER_DAY - 1) / SECONDS_PER_DAY;
        let total_rent = promise.rent_per_day * days;
        let fee = total_rent * promise_collection.platform_fee_rate / 100;

        if(rent_token_type == RENT_TOKEN_TYPE_APTOS) {
            // Total rent to platform
            coin::transfer<AptosCoin>(
                sender, 
                promise_collection.platform_wallet_address, 
                total_rent
            );

            // Fee to treasury
            coin::transfer<AptosCoin>(
                sender, 
                @ghostnft, 
                fee
            );
        };

        let rent_info = table::borrow_mut(&mut promise_collection.user_rented, sender_address);
        table::add(rent_info, token_id, timestamp::now_seconds());
    }

    fun get_token_id(promise_collection: &PromiseCollection, token_name: String, property_version: u64): TokenId {
        token::create_token_id_raw(
            promise_collection.token_creator_address, 
            promise_collection.token_collection_name,
            token_name,
            property_version)
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