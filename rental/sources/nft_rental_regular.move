module deployer::nft_rental_regular {
    use std::debug;
    use std::error;
    use std::option::{Self, Option};
    use std::signer::address_of;
    use std::string::{Self, String};
    use std::vector;

    use aptos_std::table::{Self, Table};
    // use aptos_std::table_with_length::{Self, TableWithLength};
    use ghostnft::iterable_table::{Self, IterableTable};
    // use aptos_std::iterable_table::{Self, IterableTable};

    // use aptos_framework::account::{create_resource_account};
    use aptos_framework::account::{Self, SignerCapability, create_resource_account};

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

    const ERENT_TERM_NOT_END: u64 = 7;

    const ERENT_TERM_ENDED: u64 = 8;

    const EPROMISE_BROKEN: u64 = 9;

    const ENOT_INIT_OWNER: u64 = 10;

    const ECLAIMER_IS_OWNER: u64 = 11;

    struct Promise has store, drop, copy {
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
        current_guarantee: u64
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

        promises: IterableTable<TokenId, Promise>,
        payments: Table<TokenId, u64>,
        rent_fees: Table<TokenId, u64>,
        user_rented: Table<address, IterableTable<TokenId, u64>>,
        user_tokens: Table<address, vector<u64>>,
        tokens_properties: Table<TokenId, PropertyMap>
    }

    fun init_module(
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

            promises: iterable_table::new(),
            payments: table::new(),
            rent_fees: table::new(),
            user_rented: table::new(),
            user_tokens: table::new(),
            tokens_properties: table::new()
        })
    }

    // Lessor listing one token for renting
    public entry fun make_promise(
        sender: &signer,
        token_name: String,
        property_version: u64,
        end_time: u64,
        rent_per_day: u64,
        rent_token_type: u8 // currently aptos
    ) acquires PromiseCollection {
        let sender_address = address_of(sender);
        let promise_collection = borrow_global_mut<PromiseCollection>(@deployer);
        let token_id: TokenId = get_token_id(promise_collection, token_name, property_version);

        // Token is not listed
        assert!(!iterable_table::contains(&promise_collection.promises, token_id), error::invalid_state(ETOKEN_NOT_LISTED));
        
        // Rent token type is valid
        assert!(rent_token_type == RENT_TOKEN_TYPE_APTOS, error::invalid_argument(EBAD_TOKEN_TYPE));

        // Sender owns the token
        assert!(token::balance_of(sender_address, token_id) > 0, error::not_found(EUSER_NOT_OWN_TOKEN));

        let resource_signer = account::create_signer_with_capability(&promise_collection.signer_cap);

        iterable_table::remove(&mut promise_collection.promises, token_id);
        iterable_table::add(&mut promise_collection.promises, token_id, Promise{
            inital_owner: sender_address,
            rented: false,
            kept: true,
            claimed: false,
            tenant: option::none(),
            rent_per_day,
            start_time: timestamp::now_seconds(),
            end_time,
            total_rent: 0,
            rent_token_type,
            current_guarantee: promise_collection.guarantee
        });

        // Pledge guarantee
        coin::transfer<ghostnft::gnft_coin_mintable::GnftCoin>(
            sender, 
            address_of(&resource_signer), 
            promise_collection.guarantee
        );

        // Insert user_tokens
        let user_tokens = table::borrow_mut(&mut promise_collection.user_tokens, sender_address);
        vector::push_back(user_tokens, property_version);

        // Record tokens properties
        let property_map = token::get_property_map(sender_address, token_id);
        table::upsert(&mut promise_collection.tokens_properties, token_id, property_map);
    }

    // Tenant renting a listed token
    public entry fun fill_promise(
        sender: &signer,
        token_name: String,
        property_version: u64,
        // rent_token_type: u8
    ) acquires PromiseCollection {
        let sender_address = address_of(sender);
        let promise_collection = borrow_global_mut<PromiseCollection>(@deployer);
        let token_id: TokenId = get_token_id(promise_collection, token_name, property_version);

        // Token is listed
        assert!(iterable_table::contains(&promise_collection.promises, token_id), error::invalid_state(ETOKEN_NOT_LISTED));

        let promise = iterable_table::borrow_mut(&mut promise_collection.promises, token_id);
        // Tenant is none
        assert!(option::is_none(&promise.tenant), error::unavailable(EBAD_TENANT));

        // Token is not rented
        assert!(!promise.rented, error::invalid_state(ETOKEN_ALREADY_RENTED));

        let resource_signer = account::create_signer_with_capability(&promise_collection.signer_cap);
        let now_seconds = timestamp::now_seconds();
        // Transfer rent and fee
        let days: u64 = (promise.end_time - now_seconds + SECONDS_PER_DAY - 1) / SECONDS_PER_DAY;
        let total_rent = promise.rent_per_day * days;
        let fee = total_rent * promise_collection.platform_fee_rate / 100;

        if(promise.rent_token_type == RENT_TOKEN_TYPE_APTOS) {
            // Total rent to platform
            coin::transfer<AptosCoin>(
                sender,
                address_of(&resource_signer),
                total_rent
            );

            // Fee to treasury
            coin::transfer<AptosCoin>(
                sender, 
                promise_collection.platform_wallet_address, 
                fee
            );
        };

        // Update rent user info
        let rent_info = table::borrow_mut(&mut promise_collection.user_rented, sender_address);
        iterable_table::add(rent_info, token_id, now_seconds);

        // Update promise status
        promise.rented = true;
        promise.start_time = now_seconds;
        promise.total_rent = total_rent;
    }


    public entry fun end_promise(
        sender: &signer,
        token_name: String,
        property_version: u64
    ) acquires PromiseCollection {
        let sender_address = address_of(sender);
        let promise_collection = borrow_global_mut<PromiseCollection>(@deployer);
        let token_id: TokenId = get_token_id(promise_collection, token_name, property_version);

        let now_seconds = timestamp::now_seconds();

        // Token is listed
        assert!(iterable_table::contains(&promise_collection.promises, token_id), error::invalid_state(ETOKEN_NOT_LISTED));
        let promise = iterable_table::borrow_mut(&mut promise_collection.promises, token_id);

        // Sender owns the token
        assert!(token::balance_of(sender_address, token_id) > 0, error::not_found(EUSER_NOT_OWN_TOKEN));

        // Rent term ends
        assert!(promise.end_time <= now_seconds, error::invalid_state(ERENT_TERM_NOT_END));

        // Promise not been broken
        assert!(promise.kept, error::invalid_state(EPROMISE_BROKEN));

        // Sender is initial owner
        assert!(sender_address == promise.inital_owner, error::invalid_argument(ENOT_INIT_OWNER));

        let promise = iterable_table::borrow_mut(&mut promise_collection.promises, token_id);
        let resource_signer = account::create_signer_with_capability(&promise_collection.signer_cap);

        // Return guarantee
        coin::transfer<ghostnft::gnft_coin_mintable::GnftCoin>(
            &resource_signer, 
            sender_address,
            promise.current_guarantee
        );

        // Transfer rent to lessor
        if(promise.rent_token_type == RENT_TOKEN_TYPE_APTOS) {
            coin::transfer<AptosCoin>(
                &resource_signer,
                sender_address,
                promise.total_rent
            )
        };

        // Update rent user info
        let rent_info = table::borrow_mut(&mut promise_collection.user_rented, sender_address);
        iterable_table::remove(rent_info, token_id);
        // TODO: check empty

        // Update user tokens
        let user_tokens = table::borrow_mut(&mut promise_collection.user_tokens, sender_address);
        let (exists, idx) = vector::index_of(user_tokens, &property_version);
        if(exists) {
            vector::remove(user_tokens, idx);
        }
    }

    public entry fun claim(
        sender: &signer,
        token_name: String,
        property_version: u64
    ) acquires PromiseCollection {
        let sender_address = address_of(sender);
        let promise_collection = borrow_global_mut<PromiseCollection>(@deployer);
        let token_id: TokenId = get_token_id(promise_collection, token_name, property_version);

        // Token is listed
        assert!(iterable_table::contains(&promise_collection.promises, token_id), error::invalid_state(ETOKEN_NOT_LISTED));
        let promise = iterable_table::borrow_mut(&mut promise_collection.promises, token_id);

        // Promise not been claimed
        assert!(promise.kept, error::invalid_state(EPROMISE_BROKEN));

        // Claimer is not init owner
        assert!(sender_address != promise.inital_owner, error::invalid_state(ECLAIMER_IS_OWNER));

        // In rent term
        assert!(promise.end_time > timestamp::now_seconds(), error::invalid_state(ERENT_TERM_ENDED));

        let resource_signer = account::create_signer_with_capability(&promise_collection.signer_cap);
        let guarantee = promise.current_guarantee;
        let claimer_amount = guarantee * promise_collection.claimer_percent / 100;
        let app_amount = guarantee * promise_collection.app_percent / 100;
        let user_amount = guarantee - claimer_amount - app_amount;

        // Reward claimer
        coin::transfer<ghostnft::gnft_coin_mintable::GnftCoin>(
            &resource_signer, 
            sender_address,
            claimer_amount
        );

        // Compensation to app
        coin::transfer<ghostnft::gnft_coin_mintable::GnftCoin>(
            &resource_signer, 
            promise_collection.app_wallet_address,
            app_amount
        );

        if( !option::is_none(&promise.tenant) ) {
            // Compensation to tenant
            coin::transfer<ghostnft::gnft_coin_mintable::GnftCoin>(
                &resource_signer, 
                *option::borrow(&promise.tenant),
                user_amount
            );

            // Return rent to tenant
            if(promise.rent_token_type == RENT_TOKEN_TYPE_APTOS) {
                coin::transfer<AptosCoin>(
                    &resource_signer,
                    *option::borrow(&promise.tenant),
                    promise.total_rent
                )
            }
        }
    }

    public entry fun get_user_rented(user: address): Option<vector<Promise>> acquires PromiseCollection {
        let ret_promises = vector::empty<Promise>();
        let promise_collection = borrow_global_mut<PromiseCollection>(@deployer);
        if(table::contains(&promise_collection.user_rented, user)) {
            let rent_info = table::borrow_mut(&mut promise_collection.user_rented, user);
            let key = iterable_table::head_key(rent_info);
            let now = timestamp::now_seconds();
            while (option::is_some(&key)) {
                let (_, prev, next) = iterable_table::borrow_iter(rent_info, *option::borrow(&key));
                let token_id = option::borrow(&prev);
                let promise = iterable_table::borrow_mut(&mut promise_collection.promises, *token_id);
                if(promise.end_time > now) {
                    vector::push_back(&mut ret_promises, *promise);
                };
                key = next;
            };
            if(vector::length(&ret_promises) > 0) {
                option::some(ret_promises)
            } else {
                option::none()
            }
        } else {
            option::none()
        }
    }

    public entry fun get_all_rented(): Option<vector<Promise>> acquires PromiseCollection {
        let ret_promises = vector::empty<Promise>();
        let promise_collection = borrow_global_mut<PromiseCollection>(@deployer);
        let key = iterable_table::head_key(&promise_collection.promises);
        let now = timestamp::now_seconds();

        while (option::is_some(&key)) {
            let (value, _, next) = iterable_table::borrow_iter(&promise_collection.promises, *option::borrow(&key));
            let promise = *value;
            if(promise.end_time > now) {
                vector::push_back(&mut ret_promises, promise);
            };
            key = next;
        };

        if(vector::length(&ret_promises) > 0) {
            option::some(ret_promises)
        } else {
            option::none()
        }
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