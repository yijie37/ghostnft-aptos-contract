module ghostnft::gnft_coin_mintable {
    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::coin::MintCapability;
    use std::string;

    const EMINT_TOO_MUCH: u64 = 1;

    struct GnftCoin has key {}

    struct CoinInfo has key {
        mint_rate: u64,
        mint_cap: MintCapability<GnftCoin>
    }

    fun init_module(resource: &signer) {
        let decimals: u8 = 8;
        let mint_rate: u64 = 10000000000;
        let monitor_supply: bool = false;
        let (burn_cap,freeze_cap, mint_cap) = coin::initialize<GnftCoin>(
            resource,
            string::utf8(b"Gnft coin for GhostNFT testing"),
            string::utf8(b"GNFT"),
            decimals,
            monitor_supply,
        );
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_freeze_cap(freeze_cap);
        move_to(resource, CoinInfo {
            mint_rate,
            mint_cap
        });
        // faucet::retrieve_resource_account_cap(resource);
    }

    public entry fun mint(to: address) acquires CoinInfo {
        let amount: u64 = 10000000000;
        let fcoin = borrow_global<CoinInfo>(@ghostnft);
        // assert!(amount <= fcoin.mint_rate, EMINT_TOO_MUCH);
        let mint = coin::mint<GnftCoin>(amount, &fcoin.mint_cap);
        coin::deposit(to, mint);
    }

    public entry fun claim(claimer: &signer) acquires CoinInfo {
        let to = signer::address_of(claimer);
        if (!coin::is_account_registered<GnftCoin>(to)) {
            coin::register<GnftCoin>(claimer)
        };
        mint(to)
    }
}