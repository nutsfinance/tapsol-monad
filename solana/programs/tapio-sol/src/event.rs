use anchor_lang::prelude::*;

/// emit when a pool is created with its fees and amplitude
#[event]
pub struct CreatePool {
    pub a: u64,
    pub tokens: Vec<Pubkey>,
    pub mint_fee: u64,
    pub swap_fee: u64,
    pub redeem_fee: u64,
}

/// emit when users mint a pool token and record the pool state
#[event]
pub struct Minted {
    pub minter: Pubkey,
    pub a: u64,
    pub input_amounts: Vec<u64>,
    pub min_output_amount: u64,
    pub balances: Vec<u64>,
    pub total_supply: u64,
    pub fee_amount: u64,
    pub output_amount: u64,
}

/// emit when users swap tokens and record the pool state
#[event]
pub struct TokenSwapped {
    pub swapper: Pubkey,
    pub a: u64,
    pub input_asset: Pubkey,
    pub output_asset: Pubkey,
    pub input_amount: u64,
    pub min_output_amount: u64,
    pub balances: Vec<u64>,
    pub total_supply: u64,
    pub output_amount: u64,
}

/// emit when users redeem tokens and record the pool state
#[event]
pub struct RedeemedProportion {
    pub redeemer: Pubkey,
    pub a: u64,
    pub input_amount: u64,
    pub min_output_amounts: Vec<u64>,
    pub balances: Vec<u64>,
    pub total_supply: u64,
    pub fee_amount: u64,
    pub output_amounts: Vec<u64>,
}

/// emit when users redeem tokens and record the pool state
#[event]
pub struct RedeemedSingle {
    pub redeemer: Pubkey,
    pub a: u64,
    pub input_amount: u64,
    pub output_asset: Pubkey,
    pub min_output_amount: u64,
    pub balances: Vec<u64>,
    pub total_supply: u64,
    pub fee_amount: u64,
    pub output_amount: u64,
}

/// emit when admins modify pool amplitude
#[event]
pub struct AModified {
    pub value: u64,
    pub time: u64,
}
