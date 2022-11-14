module ghostnft::nft_mintable {
  use aptos_token::token;
  use std::string;
  use aptos_token::token::{TokenDataId};
  use aptos_framework::account::{SignerCapability, create_resource_account};
  use aptos_framework::account;
  use std::vector;
  use aptos_framework::timestamp;
  use std::signer::address_of;
  #[test_only]
  use aptos_framework::account::create_account_for_test;

  struct MintingNFT has key {
      minter_cap:SignerCapability,
      token_data_id:TokenDataId,
      expiration_timestamp: u64,
  }

  public entry fun init(sender:&signer, maximum:u64, expiration_timestamp:u64){
      // create the resource account that we'll use to create tokens
      let (resource_signer,resource_signer_cap) = create_resource_account(sender, b"minter");

      //create the nft collection
      token::create_collection(
          &resource_signer,
          string::utf8(b"Collection name"),
          string::utf8(b"Collection description"),
          string::utf8(b"Collection uri"),
          1,
          vector<bool>[false,false,false]
      );

      // create a token data id to specify which token will be minted
      let token_data_id = token::create_tokendata(
          &resource_signer,
          string::utf8(b"Collection name"),
          string::utf8(b"Token name"),
          string::utf8(b"Token description"),
          maximum,
          string::utf8(b"Token uri"),
          @ghostnft,
          1,
          0,
          // we don't allow any mutation to the token
          token::create_token_mutability_config(
              &vector<bool>[ false, false, false, false, true ]
          ),
          vector::empty<string::String>(),
          vector::empty<vector<u8>>(),
          vector::empty<string::String>(),
      );

      move_to(sender, MintingNFT {
          minter_cap: resource_signer_cap,
          token_data_id,
          expiration_timestamp,
      });

  }

  public entry fun mint(sender:&signer) acquires MintingNFT {
      // get the collection minter and check if the collection minting is disabled or expired
      let minting_nft = borrow_global_mut<MintingNFT>(@ghostnft);
      assert!(timestamp::now_seconds() < minting_nft.expiration_timestamp, 0);

      //mint fee
      // coin::transfer<AptosCoin>(sender, @fee_receiver, minting_nft.uintprice);

      // mint token to the receiver
      let resource_signer = account::create_signer_with_capability(&minting_nft.minter_cap);
      let token_id = token::mint_token(&resource_signer, minting_nft.token_data_id, 1);
      token::direct_transfer(&resource_signer, sender, token_id, 1);

      // mutate the token properties to update the property version of this token
      let (creator_address, collection, name) = token::get_token_data_id_fields(&minting_nft.token_data_id);
      token::mutate_token_properties(
          &resource_signer,
          address_of(sender),
          creator_address,
          collection,
          name,
          0,
          1,
          vector::empty<string::String>(),
          vector::empty<vector<u8>>(),
          vector::empty<string::String>(),
      );
  }

  #[test(sender=@ghostnft, aptos_framework=@aptos_framework)]
  fun mint_test(sender:&signer, aptos_framework: &signer) acquires MintingNFT {
      // set up global time for testing purpose
      timestamp::set_time_has_started_for_testing(aptos_framework);
      create_account_for_test(@ghostnft);
      create_account_for_test(@aptos_framework);

      init(sender, 10, 1000);
      mint(sender);
      mint(sender);
      mint(aptos_framework);

      // check that the nft_receiver has the token in their token store
      let minting_nft = borrow_global_mut<MintingNFT>(@ghostnft);
      let resource_signer = account::create_signer_with_capability(&minting_nft.minter_cap);
      let resource_signer_addr = address_of(&resource_signer);
      let token_id_1 = token::create_token_id_raw(resource_signer_addr, string::utf8(b"Collection name"), string::utf8(b"Token name"), 1);
      let token_id_2 = token::create_token_id_raw(resource_signer_addr, string::utf8(b"Collection name"), string::utf8(b"Token name"), 2);
      let token_id_3 = token::create_token_id_raw(resource_signer_addr, string::utf8(b"Collection name"), string::utf8(b"Token name"), 3);

      assert!(token::balance_of(@ghostnft,token_id_1) == 1,0);
      assert!(token::balance_of(@ghostnft,token_id_2) == 1,0);
      assert!(token::balance_of(@aptos_framework,token_id_3) == 1,0);
  }
}