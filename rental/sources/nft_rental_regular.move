module 0xCAFE::nft_rental_regular {
  use std::debug;
  use std::signer;
  use std::string::{Self, String};
  use std::vector;

  use aptos_framework::account;
  use aptos_framework::event::{Self, EventHandle};
  use aptos_framework::timestamp;
  use aptos_std::ed25519;
  use aptos_token::token::{Self, TokenDataId};
  use aptos_framework::resource_account;

  struct Promise has store {
    
  }

  public fun speak(): string::String {
    string::utf8(b"Hello World")
  }

  #[test]
  public fun test_speak() {
    let res = speak();

    debug::print(&res);

    let except = string::utf8(b"Hello World");
    assert!(res == except, 0);
  }
}